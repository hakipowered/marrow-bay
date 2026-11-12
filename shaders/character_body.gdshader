shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Survivor body: the scanned PBR textures plus soft body shaping regions
// (body sliders) and spring-driven secondary motion, done on the skinned
// vertices so the Meshy rig needs no extra bones.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metal_ch = vec4(0.0, 0.0, 1.0, 0.0);
uniform float roughness = 1.0;
uniform float metallic = 1.0;
uniform float normal_scale = 1.0;
uniform bool has_normal = true;
uniform vec4 tint : source_color = vec4(1.0);

const int REGIONS = 6;
uniform vec3 r_center[6];
uniform vec3 r_radius[6];
uniform vec3 r_fwd[6];
uniform vec3 r_offset[6];
uniform float r_inflate[6];
uniform float r_mask[6];
// Regions with the same non-zero group (the two sides of the chest) share
// the growth where they overlap instead of adding it up, so the cleavage
// stays a valley between the cups rather than swelling out past them.
uniform float r_group[6];

void vertex() {
	vec3 v = VERTEX;
	vec3 add = vec3(0.0);
	float ws[REGIONS];
	for (int i = 0; i < REGIONS; i++) {
		ws[i] = 1.0 - smoothstep(0.55, 1.0, length((v - r_center[i]) / max(r_radius[i], vec3(1e-3))));
	}
	for (int i = 0; i < REGIONS; i++) {
		vec3 rel = v - r_center[i];
		vec3 q = rel / max(r_radius[i], vec3(1e-3));
		float w = ws[i];
		if (w <= 0.0) continue;
		float share = 1.0;
		if (r_group[i] > 0.0) {
			float total = 0.0;
			for (int j = 0; j < REGIONS; j++) {
				if (r_group[j] == r_group[i]) total += max(ws[j], 0.0);
			}
			share = w / max(total, 1e-4);
		}
		vec3 dir = normalize(rel + vec3(1e-4));
		float f = dot(dir, r_fwd[i]);
		float facing = smoothstep(-0.25, 0.35, f);
		float m = mix(1.0, facing, r_mask[i]);
		// Shaping grows the mass outwards and a little forwards, so a bigger
		// size projects rather than swelling up into the collarbone.
		vec3 grow = mix(rel, r_fwd[i] * length(rel), 0.35 * r_mask[i]);
		// Secondary motion moves only the soft mass itself: the part in front
		// of the centre, fading out well inside the region and fast below it,
		// so the ribs, the upper abs and the back stay put.
		vec3 qj = q * vec3(1.25, rel.y < 0.0 ? 2.0 : 1.3, 1.0);
		float wj = (1.0 - smoothstep(0.2, 0.75, length(qj))) * smoothstep(0.1, 0.55, f);
		add += grow * r_inflate[i] * m * w * share + r_offset[i] * wj;
	}
	VERTEX = v + add;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * tint.rgb;
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = clamp(dot(orm, rough_ch) * roughness, 0.05, 1.0);
	METALLIC = dot(orm, metal_ch) * metallic;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
