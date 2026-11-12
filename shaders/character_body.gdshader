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

void vertex() {
	vec3 v = VERTEX;
	vec3 add = vec3(0.0);
	for (int i = 0; i < REGIONS; i++) {
		vec3 rel = v - r_center[i];
		float d = length(rel / max(r_radius[i], vec3(1e-3)));
		float w = 1.0 - smoothstep(0.55, 1.0, d);
		if (w <= 0.0) continue;
		float facing = smoothstep(-0.25, 0.35, dot(normalize(rel + vec3(1e-4)), r_fwd[i]));
		float m = mix(1.0, facing, r_mask[i]);
		add += (rel * r_inflate[i] * m + r_offset[i]) * w;
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
