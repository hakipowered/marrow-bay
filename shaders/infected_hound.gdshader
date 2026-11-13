shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Turns the scanned guard dog into the infected hound: mangy bald patches of
// grey dead skin with dark veins, a flank torn open to the ribs, a gash on the
// haunch and a bitten throat, jaws and chest soaked in blood, yellowed teeth,
// milky dead eyes, wet matted fur. Regions come from the rest-pose position
// baked into COLOR (0..1 over the model's bounds: x across, y up, z from the
// tail tip to the nose), so the marks stay on the body while it animates.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metal_ch = vec4(0.0, 0.0, 1.0, 0.0);
uniform float roughness = 1.0;
uniform float rough_min = 0.62;   // matted fur, not glossy
uniform float metallic = 0.0;
uniform float normal_scale = 1.0;
uniform bool has_normal = true;
uniform float seed = 0.0;
uniform float blood = 0.8;
uniform float mange = 0.4;
uniform float wounds = 1.0;
uniform float eye_glow = 0.22;
// Eye centres in rest space (x offset from the centre line, y, z).
uniform vec3 eye = vec3(0.275, 0.893, 0.926);
uniform float debug_eyes = 0.0;

varying vec3 rest;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm3(vec3 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise3(p); p *= 2.07; a *= 0.5; }
	return v;
}
// Soft ellipse in (side-offset, height, length) space.
float blob3(vec3 p, vec3 c, vec3 r) { vec3 d = (p - c) / r; return exp(-dot(d, d)); }

void vertex() {
	rest = COLOR.rgb;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec4 orm = texture(orm_tex, UV);
	float rough = clamp((dot(rough_ch, vec4(1.0)) > 0.0 ? dot(orm, rough_ch) : 1.0) * roughness, rough_min, 1.0);
	float metal = 0.0;   // fur and flesh: the scan's metal map only makes it look chrome
	float side = seed > 0.5 ? 1.0 : -1.0;
	float x = (rest.x - 0.5) * 2.0;     // -1 .. 1 across, 0 = spine line
	float ax = abs(x);
	float y = rest.y;                   // 0 floor .. 1 ear tips
	float z = rest.z;                   // 0 tail tip .. 1 nose
	vec3 sp = rest * vec3(0.4, 0.94, 1.37) * 4.0 + vec3(seed * 3.7, seed * 1.3, seed * 5.1);
	vec3 q = vec3(ax, y, z);
	float lum = dot(base, vec3(0.3, 0.59, 0.11));

	// Wet, matted fur: darker and a touch cold, grimier low down.
	vec3 col = base * vec3(0.8, 0.78, 0.8);
	col *= 1.0 - (1.0 - smoothstep(0.05, 0.35, y)) * 0.3;
	float n1 = fbm3(sp * 3.0);
	float n2 = fbm3(sp * 7.0 + 11.0);

	// Mange: bald patches of grey-pink dead skin with scabs and dark veins.
	float body = smoothstep(0.12, 0.3, y) * (1.0 - smoothstep(0.86, 0.93, z));
	float bald = smoothstep(0.66, 0.74, n1 + n2 * 0.25) * mange * body * 2.0;
	bald = clamp(bald, 0.0, 1.0);
	vec3 skin = vec3(0.25, 0.2, 0.2) * (0.7 + 0.5 * n2);
	skin = mix(skin, vec3(0.12, 0.05, 0.045), smoothstep(0.58, 0.72, fbm3(sp * 14.0)) * 0.85);
	float vein = smoothstep(0.955, 0.99, 1.0 - abs(noise3(sp * vec3(9.0, 13.0, 9.0)) * 2.0 - 1.0));
	skin = mix(skin, vec3(0.12, 0.1, 0.15), vein * 0.7);
	col = mix(col, skin, bald);

	// Flank torn open to the ribs (one side, by seed).
	vec3 fq = vec3(x * side, y, z);
	float flank = blob3(fq, vec3(0.78, 0.56, 0.56), vec3(0.3, 0.075, 0.07));
	flank *= smoothstep(0.35, 0.6, noise3(sp * 6.0) + flank * 0.4);
	float ribs = smoothstep(0.55, 0.85, sin((z * 34.0 + y * 9.0) * 6.2832) * 0.5 + 0.5);
	float fl = fbm3(sp * 18.0);
	vec3 meat = mix(vec3(0.07, 0.008, 0.008), vec3(0.24, 0.035, 0.03), smoothstep(0.35, 0.75, fl));
	meat = mix(meat, vec3(0.3, 0.2, 0.12), smoothstep(0.72, 0.85, fl) * 0.5);   // fat and sinew
	vec3 rib = vec3(0.48, 0.42, 0.33) * (0.6 + 0.4 * n2);
	vec3 torn = mix(meat, rib, ribs * smoothstep(0.55, 0.9, flank) * smoothstep(0.3, 0.6, fl));
	// Haunch gash on the other side, slanting down and back.
	vec2 gp = vec2(z - 0.28 - (y - 0.5) * 0.35, y - 0.5);
	float gash = exp(-pow(gp.x / 0.02, 2.0) - pow(gp.y / 0.12, 2.0)) * step(0.0, -x * side) * smoothstep(0.45, 0.7, ax);
	// Bitten throat.
	float throat = blob3(fq, vec3(-0.45, 0.66, 0.82), vec3(0.35, 0.05, 0.04)) * smoothstep(0.3, 0.6, noise3(sp * 9.0) + 0.25);
	float wound = clamp(max(flank, max(gash, throat)) * 1.6, 0.0, 1.0) * wounds;
	vec3 rim = vec3(0.16, 0.06, 0.04);
	col = mix(col, rim, smoothstep(0.12, 0.35, wound) * 0.7);
	col = mix(col, torn, smoothstep(0.3, 0.55, wound));
	rough = mix(rough, 0.32, smoothstep(0.3, 0.6, wound));

	// Blood: soaked jaws, running down the throat and chest, on the forelegs.
	float muzzle = smoothstep(0.88, 0.92, z) * smoothstep(0.68, 0.73, y) * (1.0 - smoothstep(0.84, 0.88, y));
	float drips = smoothstep(0.55, 0.8, noise3(vec3(rest.x * 40.0 + seed, y * 3.0, z * 40.0)));
	float chest = smoothstep(0.7, 0.75, z) * (1.0 - smoothstep(0.86, 0.9, z)) * (1.0 - smoothstep(0.35, 0.6, ax));
	chest *= smoothstep(0.3, 0.42, y) * (1.0 - smoothstep(0.8, 0.86, y)) * smoothstep(0.35, 0.6, n1 + drips * 0.6);
	float paws = (1.0 - smoothstep(0.08, 0.2, y)) * smoothstep(0.62, 0.7, z) * smoothstep(0.5, 0.7, n2 + 0.15);
	float spatter = smoothstep(0.7, 0.78, fbm3(sp * 9.0)) * 0.6;
	float b = clamp(muzzle * (0.9 + 0.5 * n2) + chest + paws * 0.7 + spatter + wound * 0.5, 0.0, 1.0) * blood;
	vec3 fresh = vec3(0.3, 0.018, 0.012);
	vec3 dried = vec3(0.09, 0.02, 0.014);
	vec3 bcol = mix(dried, fresh, smoothstep(0.4, 0.7, n2));
	// Teeth stay teeth: yellowed and streaked, not painted over.
	float teeth = muzzle * smoothstep(0.5, 0.7, lum);
	col = mix(col, bcol * (0.8 + lum * 0.5), b * (1.0 - teeth) * 0.9);
	col = mix(col, vec3(0.62, 0.52, 0.32) * (0.6 + lum * 0.5), teeth * 0.6);
	rough = mix(rough, 0.22, b * smoothstep(0.35, 0.65, n2));

	// Dead eyes: milky, with a faint sick glow in the dark.
	float eyes = blob3(vec3(ax, y, z), eye, vec3(0.08, 0.014, 0.011));
	vec3 milk = vec3(0.78, 0.76, 0.62);
	col = mix(col, milk, clamp(eyes * 1.4, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.0, 1.0), debug_eyes * step(0.3, eyes));

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal * (1.0 - wound);
	EMISSION = vec3(0.9, 0.85, 0.5) * clamp(eyes * 1.4, 0.0, 1.0) * eye_glow;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
