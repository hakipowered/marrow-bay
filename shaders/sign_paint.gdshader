shader_type spatial;
// Lettering painted onto a surface (Signage.paint): stencilled spray paint,
// chalk, a crisp print, signwriter's brushwork or letters scored into it.
// On a level wall it reads the wall's own triplanar normal and AO/roughness
// maps (the same ones shaders/surface.gdshader uses), so the paint takes the
// shape of every brick: it lies on the faces, thins out and bleeds in the
// joints, chalk only catches the high spots, and the wall's grime and water
// stains run over the paint too. On metal or glass it is flat.
render_mode blend_mix, cull_back, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 texel = vec2(0.002);
uniform int kind = 0;                    // Signage.PAINTS
uniform vec2 size = vec2(1.0, 0.3);
uniform vec4 paint : source_color = vec4(0.86, 0.82, 0.7, 1.0);
uniform float wear = 0.45;
uniform float seed = 0.0;
uniform float base_rough = 0.6;
uniform float base_metal = 0.0;

uniform bool has_surface = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_size = 2.0;
uniform float blend_sharpness = 6.0;
uniform float grime_height = 0.6;
uniform float grime_amount = 0.55;
uniform float floor_y = 0.0;
uniform float ceiling_y = 3.2;
uniform float stain_amount = 0.35;
uniform float normal_strength = 1.0;

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

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy / tile_size) * w.x + texture(t, p.xz / tile_size) * w.y + texture(t, p.xy / tile_size) * w.z;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	p.y = -p.y;
	vec2 q = p + vec2(seed * 1.37, seed * 2.91);

	// The surface under the paint.
	vec3 nm = vec3(0.5, 0.5, 1.0);
	float ao = 1.0;
	float proud = 0.75;           // 1 on a brick's face, 0 down in a joint or pit
	float dirt = 0.0;
	if (has_surface) {
		vec3 w = pow(abs(wnrm), vec3(blend_sharpness));
		w /= (w.x + w.y + w.z);
		vec3 arm = tri(arm_tex, wpos, w).rgb;
		nm = tri(normal_tex, wpos, w).rgb;
		ao = arm.r;
		proud = smoothstep(0.3, 0.85, arm.r);
		// The wall's own grime and water stains, laid over the paint too.
		float is_wall = 1.0 - w.y;
		float gnoise = fbm(vec2(wpos.x + wpos.z, wpos.y) * 2.5);
		float grime = (1.0 - smoothstep(0.0, grime_height * (0.6 + gnoise), wpos.y - floor_y)) * grime_amount * is_wall;
		float drip_cols = fbm(vec2((wpos.x + wpos.z) * 3.0, 0.0));
		float stain = smoothstep(0.45, 0.8, drip_cols) * smoothstep(ceiling_y - 2.2 * drip_cols, ceiling_y, wpos.y) * stain_amount * is_wall;
		dirt = clamp(grime + stain, 0.0, 0.9);
	}

	float m = texture(mask, UV).r;
	float blur = textureLod(mask, UV, 3.0).r;     // a few mm round the letters
	float haze = textureLod(mask, UV, 5.0).r;     // a couple of cm
	float fine = noise(q * 700.0);
	float flake = fbm(q * 13.0) * 0.7 + noise(q * 75.0) * 0.3;
	float gone = smoothstep(0.7 - wear * 0.3, 0.76 - wear * 0.3, flake);
	vec3 col = paint.rgb * (0.94 + 0.12 * fbm(q * 6.0));
	float a = 0.0;
	float rough = 0.6;
	float metal = 0.0;

	if (kind == 0) {
		// Spray through a stencil card: soft-edged, a fine mist of overspray
		// round the letters, thinner and bled under the card in the joints.
		float edge = 0.5 + (fine - 0.5) * 0.18;
		float fw = max(fwidth(m), 0.015);
		float cov = smoothstep(edge - fw * 1.5, edge + fw * 1.5, m);
		float body = cov * mix(0.55, 1.0, proud) * (0.82 + 0.18 * fbm(q * 40.0));
		float bleed = smoothstep(0.1, 0.45, blur) * (1.0 - proud) * 0.55;
		float mist = smoothstep(0.02, 0.35, haze) * step(0.82 - haze * 0.3, fine) * 0.45;
		a = max(max(body, bleed), mist * (1.0 - cov));
		a *= 1.0 - gone * 0.92;
		a *= 0.95 - wear * 0.2;
		rough = 0.68;
	} else if (kind == 1) {
		// Chalk: grains left on the high spots only, a pale smudge round it.
		float grain = noise(q * 1100.0) * 0.55 + noise(q * 320.0) * 0.45;
		float rag = 0.45 + (noise(q * 260.0) - 0.5) * 0.3;
		float cov = smoothstep(rag - 0.12, rag + 0.12, m);
		float catchp = smoothstep(0.32, 0.62, grain * 0.7 + proud * 0.55 - 0.1);
		a = cov * catchp * (0.9 - wear * 0.35);
		a = max(a, smoothstep(0.05, 0.5, blur) * 0.1 * (0.6 + grain * 0.4));
		a *= 1.0 - gone * 0.7;
		rough = 0.96;
		col = paint.rgb * (0.9 + 0.15 * grain);
	} else if (kind == 2) {
		// A crisp print (silkscreen or vinyl): sharp edges, worn in patches,
		// a scuff here and there.
		float fw = max(fwidth(m), 0.01);
		float cov = smoothstep(0.5 - fw, 0.5 + fw, m);
		float scuff = smoothstep(0.6, 0.66, noise(vec2(q.x * 30.0 + q.y * 9.0, q.y * 300.0))) * wear;
		a = cov * (1.0 - gone * 0.95) * (1.0 - scuff * 0.8) * mix(0.8, 1.0, proud);
		rough = 0.42;
	} else if (kind == 3) {
		// Signwriter's brush: a slightly wandering edge, brush streaks along
		// the strokes, paint missing the deepest pits.
		float edge = 0.5 + (noise(q * 180.0) - 0.5) * 0.16;
		float fw = max(fwidth(m), 0.012);
		float cov = smoothstep(edge - fw, edge + fw, m);
		float streak = noise(vec2(q.x * 60.0, q.y * 900.0));
		col *= 0.9 + 0.14 * streak;
		a = cov * mix(0.62, 1.0, proud) * (1.0 - gone * 0.9) * (0.9 + 0.1 * streak);
		rough = 0.5;
	} else {
		// Scored in: thin bright cuts with a dark lip where the edge rolled.
		float cut = smoothstep(0.55, 0.75, m + (fine - 0.5) * 0.2);
		float lip = smoothstep(0.15, 0.45, blur) * (1.0 - cut);
		col = mix(vec3(0.0), paint.rgb, cut);
		a = max(cut * 0.95, lip * 0.35) * (1.0 - gone * 0.5);
		rough = mix(0.8, 0.55, cut);
		metal = cut * base_metal;
		vec2 slope = vec2(texture(mask, UV + vec2(texel.x, 0.0)).r - m, texture(mask, UV - vec2(0.0, texel.y)).r - m);
		nm = normalize(vec3((nm.xy * 2.0 - 1.0) + slope * 1.5, 1.0)) * 0.5 + 0.5;
	}

	col = mix(col, col * vec3(0.38, 0.33, 0.27), dirt);
	col *= mix(0.72, 1.0, ao);
	ALBEDO = col;
	ALPHA = clamp(a * paint.a, 0.0, 1.0);
	ROUGHNESS = clamp(mix(base_rough, rough, 0.7) + dirt * 0.1, 0.05, 1.0);
	METALLIC = metal;
	AO = ao;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_strength;
}
