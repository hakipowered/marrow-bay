shader_type spatial;
// World-space (triplanar) PBR surface for level geometry, so walls and floors
// of any size tile correctly with no UV work. Adds per-room character on top
// of the scanned textures: grime creeping up from the floor, water stains
// running down from the ceiling, low-frequency color variation so big walls
// never look like a repeating sticker, and an optional wet sheen.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_size = 2.0;            // metres per texture repeat
uniform vec4 tint : source_color = vec4(1.0);
uniform float normal_strength = 1.0;
uniform float roughness_mul = 1.0;
uniform float grime_height = 0.6;         // metres of grime above floor_y
uniform float grime_amount = 0.55;
uniform float floor_y = 0.0;
uniform float ceiling_y = 3.2;
uniform float stain_amount = 0.35;        // water stains from the ceiling
uniform float variation = 0.18;           // big-scale tone variation
uniform float wetness = 0.0;
uniform float blend_sharpness = 6.0;
uniform float puddles = 0.0;              // standing water on floors (outdoor)
uniform float rain = 0.0;                 // raindrop ripples in the puddles
uniform float wall_wet = 0.0;             // rain running down outdoor walls

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// One layer of raindrop rings: each cell holds one drop at a random spot and
// time; returns the slope of the ring wave in the cell.
vec2 ripple_layer(vec2 p, float t) {
	vec2 c = floor(p);
	vec2 d = fract(p) - 0.5 - (vec2(hash(c + 3.1), hash(c + 7.7)) - 0.5) * 0.4;
	float ph = fract(t + hash(c));
	float r = length(d) + 1e-4;
	float x = r - ph * 0.42;
	float amp = (1.0 - ph) * (1.0 - ph) * exp(-x * x * 1600.0);
	return d / r * amp * sin(x * 90.0);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy / tile_size) * w.x + texture(t, p.xz / tile_size) * w.y + texture(t, p.xy / tile_size) * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(blend_sharpness));
	w /= (w.x + w.y + w.z);
	vec3 alb = tri(albedo_tex, wpos, w).rgb * tint.rgb;
	vec3 arm = tri(arm_tex, wpos, w).rgb;
	vec3 n = tri(normal_tex, wpos, w).rgb;

	float big = fbm(wpos.xz * 0.15 + wpos.y * 0.1);
	alb *= 1.0 - variation * 0.5 + variation * big;

	float is_wall = 1.0 - w.y;
	float h = wpos.y - floor_y;
	float gnoise = fbm(vec2(wpos.x + wpos.z, wpos.y) * 2.5);
	float grime = (1.0 - smoothstep(0.0, grime_height * (0.6 + gnoise), h)) * grime_amount * is_wall;
	float drip_cols = fbm(vec2((wpos.x + wpos.z) * 3.0, 0.0));
	float stain = smoothstep(0.45, 0.8, drip_cols) * smoothstep(ceiling_y - 2.2 * drip_cols, ceiling_y, wpos.y) * stain_amount * is_wall;
	float floor_dirt = w.y * smoothstep(0.55, 0.85, fbm(wpos.xz * 0.7)) * grime_amount * 0.6;
	float dirt = clamp(grime + stain + floor_dirt, 0.0, 0.9);
	alb = mix(alb, alb * vec3(0.38, 0.33, 0.27), dirt);

	float rough = clamp(mix(arm.g * roughness_mul + dirt * 0.15, 0.08, wetness * w.y * smoothstep(0.4, 0.6, big)), 0.03, 1.0);
	// Rain-soaked: every outdoor surface gets darker and glossier, walls
	// in streaks running down from the top.
	if (wall_wet > 0.0) {
		float streak = fbm(vec2((wpos.x + wpos.z) * 4.0, wpos.y * 0.25 - TIME * 0.05));
		float wwet = wall_wet * is_wall * smoothstep(0.35, 0.7, streak);
		alb *= 1.0 - 0.35 * wwet;
		rough = mix(rough, 0.12, wwet);
	}
	// Standing water in the low spots of the floor, with drops landing in it.
	if (puddles > 0.0 && w.y > 0.5) {
		float pm = smoothstep(0.47, 0.41, fbm(wpos.xz * 0.32 + 11.0)) * puddles * w.y;
		alb = mix(alb, alb * 0.42, pm * 0.85);
		rough = mix(rough, 0.02, pm);
		n = mix(n, vec3(0.5, 0.5, 1.0), pm * 0.9);
		if (rain > 0.0) {
			vec2 rp = ripple_layer(wpos.xz * 4.5, TIME * 1.3) + ripple_layer(wpos.xz * 4.5 + 0.5, TIME * 1.3 + 0.37)
				+ ripple_layer(wpos.xz * 4.5 + vec2(0.25, 0.71), TIME * 1.3 + 0.71);
			n.xy += rp * 0.3 * rain * pm;
		}
	}

	ALBEDO = alb;
	AO = arm.r;
	ROUGHNESS = rough;
	METALLIC = arm.b;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = normal_strength;
}
