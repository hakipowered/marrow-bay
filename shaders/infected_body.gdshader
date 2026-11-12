shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Turns a scanned townsperson into one of the infected. The models are made
// from ordinary people; this adds the infection on top: dead grey-green skin
// with mottling and dark veins, sunken eyes, a bite wound, blood around the
// mouth, down the chest and on the hands, plus burns or bile for some types.
// Body regions come from the rest-pose position baked into COLOR (0..1 over
// the model's bounds: x across, y up, z front), so the marks stay put on the
// body while it animates.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_ch = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metal_ch = vec4(0.0, 0.0, 1.0, 0.0);
uniform float roughness = 1.0;
uniform float rough_min = 0.3;    // scanned cloth can come out glossy; keep it matte
uniform float metallic = 1.0;
uniform float normal_scale = 1.0;
uniform bool has_normal = true;

uniform float seed = 0.0;
uniform float pallor = 1.0;
uniform vec3 flesh : source_color = vec3(0.62, 0.62, 0.56);
uniform float veins = 0.8;
uniform float blood = 0.7;
uniform float bite = 1.0;
uniform float grime = 0.35;
uniform float burn = 0.0;
uniform float bile = 0.0;
uniform float skin_legs = 0.0;   // bare legs (gown, shorts)
uniform float ember = 0.0;       // glowing cracks for the burning type

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
float blob(vec2 p, vec2 c, vec2 r) { vec2 d = (p - c) / r; return exp(-dot(d, d)); }

void vertex() {
	rest = COLOR.rgb;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec4 orm = texture(orm_tex, UV);
	// No texture channel (all zero) means use the plain value.
	float rough = clamp((dot(rough_ch, vec4(1.0)) > 0.0 ? dot(orm, rough_ch) : 1.0) * roughness, rough_min, 1.0);
	float metal = (dot(metal_ch, vec4(1.0)) > 0.0 ? dot(orm, metal_ch) : 1.0) * metallic;
	vec3 sp = rest + vec3(seed * 3.7, seed * 1.3, seed * 5.1);
	float x = rest.x - 0.5;           // -0.5 .. 0.5, 0 = centre line
	float ax = abs(x);
	float y = rest.y;
	float front = smoothstep(0.45, 0.7, rest.z);

	// Skin: warm, moderately saturated texels, in places skin shows (head
	// and neck, arms and hands, legs on some types). Clothes are left alone.
	float mx = max(base.r, max(base.g, base.b));
	float mn = min(base.r, min(base.g, base.b));
	float sat = (mx - mn) / max(mx, 1e-3);
	float rg = base.r / max(base.g, 1e-3);
	float warm = step(base.b, base.g + 0.02) * smoothstep(1.04, 1.14, rg) * (1.0 - smoothstep(1.75, 2.2, rg));
	float skin = warm * smoothstep(0.08, 0.2, sat) * (1.0 - smoothstep(0.62, 0.78, sat)) * smoothstep(0.14, 0.26, mx);
	float region = max(smoothstep(0.76, 0.82, y), smoothstep(0.14, 0.2, ax) * smoothstep(0.42, 0.5, y));
	region = max(region, skin_legs * (1.0 - smoothstep(0.32, 0.42, y)));
	skin *= region;

	// Dead flesh: drained of colour, cold grey-green, blotchy.
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	float mottle = fbm3(sp * 14.0);
	vec3 dead = flesh * (lum * 1.25 + 0.06);
	dead = mix(dead, dead * vec3(0.72, 0.6, 0.72), smoothstep(0.5, 0.75, mottle) * 0.8);
	dead = mix(dead, dead * vec3(0.9, 0.95, 0.75), smoothstep(0.55, 0.3, mottle) * 0.4);
	vec3 col = mix(base, dead, skin * pallor);
	float vein = smoothstep(0.955, 0.99, 1.0 - abs(noise3(sp * vec3(26.0, 40.0, 26.0)) * 2.0 - 1.0));
	col = mix(col, vec3(0.13, 0.12, 0.17), vein * veins * skin * 0.75);

	// Sunken, dark eye sockets.
	float eyes = (blob(vec2(x, y), vec2(-0.032, 0.935), vec2(0.022, 0.012)) + blob(vec2(x, y), vec2(0.032, 0.935), vec2(0.022, 0.012))) * front;
	col *= 1.0 - clamp(eyes, 0.0, 1.0) * 0.65 * pallor;

	// Grime everywhere, heavier low down.
	float g = smoothstep(0.45, 0.8, fbm3(sp * 9.0)) * grime * (0.6 + 0.6 * (1.0 - y));
	col = mix(col, col * vec3(0.45, 0.4, 0.33), g);

	// Blood: around the mouth and chin, running down the chest, on the
	// hands and forearms, and spatter.
	float n1 = fbm3(sp * vec3(10.0, 10.0, 10.0));
	float drips = smoothstep(0.62, 0.8, noise3(vec3(rest.x * 60.0 + seed, y * 4.0, rest.z * 60.0)));
	float mouth = blob(vec2(x, y), vec2(0.0, 0.888), vec2(0.035, 0.022)) * front;
	float chest = front * (1.0 - smoothstep(0.08, 0.16, ax)) * smoothstep(0.6, 0.86, y) * (1.0 - smoothstep(0.86, 0.9, y));
	chest *= smoothstep(0.35, 0.6, n1 + drips * 0.5);
	float hands = smoothstep(0.38, 0.46, ax) * smoothstep(0.45, 0.6, n1 + 0.2);
	float spatter = smoothstep(0.7, 0.78, fbm3(sp * 22.0));
	float b = clamp(mouth * 1.6 + chest + hands + spatter * 0.6, 0.0, 1.0) * blood;
	// Bite: a torn wound at the side of the neck.
	float bx = 0.055 * (seed > 0.5 ? 1.0 : -1.0);
	float wound = blob(vec2(x, y), vec2(bx, 0.845), vec2(0.03, 0.025)) * smoothstep(0.3, 0.6, noise3(sp * 40.0) + 0.3);
	wound *= bite;
	vec3 fresh = vec3(0.17, 0.012, 0.01);
	vec3 dried = vec3(0.075, 0.022, 0.016);
	vec3 bcol = mix(dried, fresh, smoothstep(0.4, 0.7, n1));
	col = mix(col, bcol * (0.75 + lum * 0.5), b * 0.88);
	col = mix(col, vec3(0.08, 0.005, 0.005), clamp(wound * 1.4, 0.0, 1.0));
	rough = mix(rough, 0.42, max(b * smoothstep(0.5, 0.7, n1), wound));

	// Bile: sickly yellow-green streaks from the mouth down the front.
	float bl = (mouth * 1.4 + chest * 0.9 + spatter * 0.4) * bile;
	col = mix(col, vec3(0.32, 0.36, 0.06) * (0.6 + lum), clamp(bl, 0.0, 0.9));
	rough = mix(rough, 0.2, clamp(bl, 0.0, 1.0));

	// Burns: charred black crust with raw red underneath.
	float ch = smoothstep(0.42, 0.62, fbm3(sp * 6.0) + 0.12) * burn;
	float crack = smoothstep(0.965, 0.995, 1.0 - abs(noise3(sp * vec3(18.0, 26.0, 18.0)) * 2.0 - 1.0)) * ch * smoothstep(0.55, 0.7, fbm3(sp * 5.0 + 3.0));
	col = mix(col, col * 0.12 + vec3(0.012, 0.01, 0.008), ch);
	col = mix(col, vec3(0.35, 0.05, 0.02), crack * 0.8);
	rough = mix(rough, 0.95, ch);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal * (1.0 - ch);
	EMISSION = vec3(1.0, 0.32, 0.05) * crack * ember * 0.6 * (0.6 + 0.4 * sin(TIME * 3.0 + seed * 10.0));
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
