shader_type spatial;
// A sign plate (Signage.plate): vitreous enamel, painted sheet steel, an
// engraved brass or steel plaque, a cast plate with raised letters, an
// engraved laminate label, a printed card, a clock dial or a signwritten
// board. The letters come from a coverage mask set from the game's fonts;
// everything else (chips, rust from the bolt holes, tarnish, worn paint,
// dirt, foxing) is worked out here in the plate's own metres, so it scales
// with the sign and each sign (its seed) wears differently.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 texel = vec2(0.002);        // one mask pixel, in UV
uniform int style = 0;                   // Signage.STYLES
uniform vec2 size = vec2(0.6, 0.2);      // metres
uniform float corner = 0.01;
uniform vec4 field : source_color = vec4(0.9, 0.88, 0.8, 1.0);
uniform vec4 ink : source_color = vec4(0.06, 0.06, 0.07, 1.0);
uniform vec4 core : source_color = vec4(0.05, 0.045, 0.04, 1.0);
uniform float border = 0.0;              // m; 0 = none
uniform float border_inset = 0.012;
uniform float wear = 0.5;
uniform float dirt = 0.45;
uniform float rust = 0.5;
uniform float seed = 0.0;
uniform float ink_metal = 0.0;           // gilt letters on a board
uniform vec4 fix[8];                     // xy: fixing (m from centre, y up), z: head radius, w: 1 = used
uniform vec4 dial = vec4(0.0);           // track outer r, inner r, hour mark length, 1 = draw

varying float v_edge;
varying float v_back;

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
float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	v_edge = COLOR.r;
	v_back = COLOR.g;
}

// How near a fixing hole (1 at the head, 0 a few cm off).
float holes(vec2 p, float reach) {
	float h = 0.0;
	for (int i = 0; i < 8; i++) {
		if (fix[i].w > 0.5) {
			float d = length(p - fix[i].xy);
			h = max(h, 1.0 - smoothstep(fix[i].z * 1.2, fix[i].z * 1.2 + reach, d));
		}
	}
	return h;
}

// Enamel chips and flaked paint: > 0 where the coating is gone. Most at the
// edges (knocks) and round the bolt holes (rust lifting it from behind).
float chips(vec2 p) {
	vec2 q = p + vec2(seed * 7.13, seed * 3.71);
	float n = fbm(q * 24.0) * 0.72 + noise(q * 90.0) * 0.28;
	float e = -sd_rbox(p, size * 0.5, corner);
	float edge = 1.0 - smoothstep(0.0, 0.028, e);
	return n + edge * 0.48 + holes(p, 0.026) * 0.42 - (1.1 - wear * 0.42);
}

// Rust run down from each fixing and from the top edge.
float streaks(vec2 p) {
	float s = 0.0;
	for (int i = 0; i < 8; i++) {
		if (fix[i].w > 0.5) {
			vec2 d = p - fix[i].xy;
			if (d.y < 0.0) {
				float wob = 0.003 * sin(p.y * 70.0 + float(i) * 2.1) + 0.002 * noise(vec2(p.y * 40.0, float(i)));
				float w = fix[i].z * (0.6 + 0.8 * noise(vec2(p.y * 25.0, float(i) + seed)));
				float col = 1.0 - smoothstep(w * 0.3, w, abs(d.x + wob));
				s = max(s, col * exp(d.y / (0.04 + 0.14 * rust)));
			}
		}
	}
	vec2 q = p + seed;
	float run = smoothstep(0.62, 0.9, noise(vec2(q.x * 55.0, 0.5))) * smoothstep(-size.y * 0.5, size.y * 0.5, p.y) * 0.5;
	return clamp(s + run * (0.3 + rust), 0.0, 1.0) * rust;
}

// Fine cracks in old enamel: the edges of a cell pattern.
float craze(vec2 p) {
	vec2 g = p * 55.0 + seed;
	vec2 i = floor(g), f = fract(g);
	float d1 = 8.0, d2 = 8.0;
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec2 o = vec2(float(x), float(y));
		vec2 c = o + vec2(hash(i + o), hash(i + o + 17.0));
		float d = length(c - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return 1.0 - smoothstep(0.0, 0.05, d2 - d1);
}

float mask_at(vec2 uv) { return texture(mask, uv).r; }

// The letters' slope (per metre, p space: x right, y up), for embossed or
// engraved letters.
vec2 mask_slope(vec2 uv, float m) {
	float mx = mask_at(uv + vec2(texel.x, 0.0));
	float my = mask_at(uv - vec2(0.0, texel.y));
	return vec2(mx - m, my - m) / (texel * size);
}

float border_line(vec2 p) {
	if (border <= 0.0) return 0.0;
	float b = abs(sd_rbox(p, size * 0.5 - border_inset, max(corner - border_inset, 0.001))) - border * 0.5;
	float aa = max(fwidth(b), 0.0002);
	return 1.0 - smoothstep(-aa * 0.5, aa * 0.5, b);
}

float dial_marks(vec2 p) {
	if (dial.w < 0.5) return 0.0;
	float r = length(p);
	float a = atan(p.x, p.y);
	float lw = dial.x * 0.012;
	float aa = max(fwidth(r), 0.0001);
	float rings = 1.0 - smoothstep(lw * 0.5, lw * 0.5 + aa, abs(r - dial.x));
	rings = max(rings, 1.0 - smoothstep(lw * 0.4, lw * 0.4 + aa, abs(r - dial.y)));
	float band = step(dial.y, r) * step(r, dial.x);
	float dm = abs(fract(a / 6.2831853 * 60.0 + 0.5) - 0.5) * 6.2831853 / 60.0 * r;
	float ticks = (1.0 - smoothstep(lw * 0.45, lw * 0.45 + aa, dm)) * band;
	float dh = abs(fract(a / 6.2831853 * 12.0 + 0.5) - 0.5) * 6.2831853 / 12.0 * r;
	float hours = (1.0 - smoothstep(lw * 1.7, lw * 1.7 + aa, dh)) * step(dial.x - dial.z, r) * step(r, dial.x);
	return max(max(rings, ticks), hours);
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	p.y = -p.y;
	vec2 q = p + vec2(seed * 1.37, seed * 2.91);
	float m = mask_at(UV);
	vec3 alb;
	float rough;
	float metal = 0.0;
	float h_scale = 0.0;          // how strongly the slope bends the normal
	vec2 slope = vec2(0.0);
	float ao = 1.0;

	float grime = dirt * (0.25 + 0.6 * fbm(q * 5.0));
	grime += dirt * 0.45 * (1.0 - smoothstep(-size.y * 0.5, -size.y * 0.5 + 0.06, p.y));
	// Dirt gathers round the edge and the heads.
	float e_in = -sd_rbox(p, size * 0.5, corner);
	grime += dirt * 0.35 * (1.0 - smoothstep(0.0, 0.012, e_in));
	grime = clamp(grime, 0.0, 1.0);

	if (style == 0 || style == 1) {
		// Enamel (0) or painted steel (1).
		float ink_m = max(m, border_line(p));
		vec3 face = mix(field.rgb, ink.rgb, ink_m);
		face *= 0.94 + 0.1 * fbm(q * 3.0);
		float c = chips(p);
		float chip = smoothstep(0.0, 0.015, c);
		float rim = smoothstep(-0.05, 0.0, c) * (1.0 - chip);
		vec3 iron = mix(vec3(0.045, 0.04, 0.035), vec3(0.32, 0.14, 0.055), smoothstep(0.3, 0.75, fbm(q * 40.0)));
		if (style == 1) {
			// Paint flakes off to red primer first, then rust.
			iron = mix(core.rgb, iron, smoothstep(0.02, 0.09, c));
		}
		// Rust spreading under the coat round the chips, and running down.
		float stain = smoothstep(-0.14, 0.0, c) * rust * 0.55 + streaks(p) * 0.75;
		face = mix(face, face * vec3(0.62, 0.42, 0.28), clamp(stain, 0.0, 1.0));
		if (style == 0) {
			face = mix(face, face * 0.82, craze(p) * wear * 0.35);
			// The chip's edge shows the pale ground coat.
			face = mix(face, vec3(0.66, 0.67, 0.68), rim * 0.55);
		} else {
			face = mix(face, face * 0.85 + vec3(0.04), rim * 0.4);
		}
		face = mix(face, face * vec3(0.42, 0.37, 0.3), grime * 0.55);
		alb = mix(face, iron, chip);
		float gloss = style == 0 ? 0.14 : 0.55;
		rough = mix(gloss + grime * 0.35 + rim * 0.2, 0.82, chip);
		metal = chip * 0.25;
		// Chips are pits in the coat: slope from the chip field.
		float e = 0.0012;
		float c0 = smoothstep(0.0, 0.02, c);
		float cx = smoothstep(0.0, 0.02, chips(p + vec2(e, 0.0)));
		float cy = smoothstep(0.0, 0.02, chips(p + vec2(0.0, e)));
		slope = -vec2(cx - c0, cy - c0) / e * 0.0005;
		h_scale = 1.0;
		ao = 1.0 - chip * 0.25;
	} else if (style == 2) {
		// Engraved metal plaque: brass by default, steel if the field is grey.
		float eng = max(m, border_line(p));
		float tarnish = smoothstep(0.35, 0.8, fbm(q * 7.0)) * (0.35 + wear * 0.6);
		tarnish = max(tarnish, (1.0 - smoothstep(0.0, 0.02, e_in)) * (0.4 + wear * 0.4));
		float verd = smoothstep(0.62, 0.86, fbm(q * 11.0 + 4.0)) * wear * (1.0 - smoothstep(0.0, 0.05, e_in) * 0.6);
		vec3 metal_col = field.rgb * (0.9 + 0.2 * fbm(q * 18.0));
		vec3 dark = field.rgb * vec3(0.32, 0.28, 0.24);
		vec3 face = mix(metal_col, dark, tarnish);
		face = mix(face, vec3(0.27, 0.38, 0.32), verd * 0.7);
		// Wax in the engraving, gone from some strokes.
		float wax = smoothstep(0.25, 0.55, noise(q * 160.0) + 0.45 - wear * 0.3);
		vec3 groove = mix(dark * 0.6, ink.rgb, wax);
		face = mix(face, face * vec3(0.5, 0.45, 0.4), grime * 0.5);
		alb = mix(face, groove, eng);
		metal = mix(1.0 - verd * 0.8 - tarnish * 0.25, mix(0.6, 0.0, wax), eng);
		rough = mix(0.24 + tarnish * 0.35 + verd * 0.4 + grime * 0.25 + noise(q * 300.0) * 0.08, 0.7, eng);
		slope = -mask_slope(UV, m) * 0.0004;
		h_scale = 1.0;
		ao = 1.0 - eng * 0.35;
	} else if (style == 3) {
		// Cast plate: raised letters and rim, the field painted, paint worn
		// off the high spots to the bare metal.
		float bl = border_line(p);
		float up = max(m, bl);
		float worn = smoothstep(0.45, 0.75, fbm(q * 30.0) + wear * 0.3 - 0.15);
		vec3 bare = core.rgb * (0.85 + 0.3 * noise(q * 120.0));
		vec3 letters = mix(ink.rgb, bare, worn * 0.85);
		float c = chips(p);
		float chip = smoothstep(0.0, 0.02, c);
		vec3 paintc = mix(field.rgb, vec3(0.3, 0.13, 0.06), chip);
		paintc *= 0.88 + 0.2 * fbm(q * 9.0);
		paintc = mix(paintc, paintc * vec3(0.45, 0.4, 0.33), grime * 0.6);
		alb = mix(paintc, letters, up);
		metal = mix(chip * 0.3, worn * 0.8, up);
		rough = mix(0.62 + grime * 0.2, mix(0.55, 0.38, worn), up);
		// Sand-cast pitting plus the raised letters.
		float pit = noise(q * 420.0);
		float pe = 0.0008;
		slope = mask_slope(UV, m) * 0.0012 + vec2(noise(q * 420.0 + vec2(pe * 420.0, 0.0)) - pit, noise(q * 420.0 + vec2(0.0, pe * 420.0)) - pit) / pe * 0.00004;
		if (border > 0.0) {
			float b2 = border_line(p + vec2(0.0008, 0.0));
			float b3 = border_line(p + vec2(0.0, 0.0008));
			slope += vec2(b2 - bl, b3 - bl) / 0.0008 * 0.0012;
		}
		h_scale = 1.0;
		ao = 1.0 - (1.0 - up) * 0.15;
	} else if (style == 4) {
		// Engraved laminate: the cut letters and the chamfered edge show the core.
		float cham = 1.0 - smoothstep(0.0006, 0.0011, e_in);
		float cut = max(m, cham);
		vec3 face = field.rgb * (0.95 + 0.1 * noise(q * 60.0));
		float scratch = smoothstep(0.93, 1.0, noise(vec2(q.x * 900.0 + q.y * 300.0, q.y * 40.0))) * wear;
		face = mix(face, core.rgb * 0.6, scratch * 0.4);
		face = mix(face, face * 0.7 + vec3(0.02, 0.018, 0.015), grime * 0.4);
		alb = mix(face, core.rgb * (0.9 - grime * 0.25), cut);
		rough = mix(0.32 + grime * 0.2 + scratch * 0.2, 0.62, cut);
		slope = -mask_slope(UV, m) * 0.00025;
		h_scale = 1.0;
		ao = 1.0 - m * 0.2;
	} else if (style == 5) {
		// Card or paper: fibres, foxing, a fold, the ink soaked in a little.
		float soak = textureLod(mask, UV, 1.5).r;
		float inkm = max(m, soak * 0.35);
		vec3 paper = field.rgb * (0.92 + 0.12 * fbm(q * 40.0));
		float fox = smoothstep(0.72, 0.9, fbm(q * 26.0 + 9.0)) * (0.4 + wear * 0.6);
		paper = mix(paper, core.rgb, fox * 0.6);
		paper = mix(paper, paper * vec3(0.78, 0.7, 0.55), (1.0 - smoothstep(0.0, 0.025, e_in)) * (0.5 + wear * 0.5));
		paper = mix(paper, paper * vec3(0.55, 0.5, 0.42), grime * 0.4);
		alb = mix(paper, ink.rgb, inkm * 0.95);
		rough = 0.88;
		float fold = 1.0 - smoothstep(0.0, 0.0025, abs(p.y + p.x * 0.07 - size.y * 0.12));
		slope = vec2(0.0, fold * 0.25) + (vec2(noise(q * 260.0), noise(q * 260.0 + 3.0)) - 0.5) * 0.06;
		h_scale = 1.0;
	} else if (style == 6) {
		// A clock dial: enamel face, its minute track and the numerals,
		// crazed and yellowed toward the rim.
		float marks = max(m, dial_marks(p));
		float rr = length(p) / max(size.x * 0.5, 0.001);
		vec3 face = field.rgb * (1.0 - 0.18 * smoothstep(0.4, 1.0, rr));
		face = mix(face, face * vec3(0.92, 0.85, 0.7), fbm(q * 14.0) * 0.4);
		face = mix(face, face * 0.8, craze(p * 1.6) * wear * 0.3);
		face = mix(face, face * vec3(0.5, 0.45, 0.38), grime * 0.4);
		alb = mix(face, ink.rgb, marks);
		rough = 0.22 + grime * 0.35;
	} else {
		// A signwritten board: varnished wood, gilt or painted letters.
		vec2 g = vec2(p.x * 4.0 + fbm(p * 3.0) * 0.6, p.y * 90.0 + fbm(p * vec2(2.0, 30.0)) * 3.0);
		float grain = noise(g) * 0.6 + noise(g * vec2(1.0, 3.1)) * 0.4;
		vec3 wood = field.rgb * mix(0.7, 1.25, grain);
		float worn = smoothstep(0.55, 0.85, fbm(q * 20.0) + wear * 0.25);
		wood = mix(wood, wood * vec3(0.5, 0.42, 0.36), grime * 0.5);
		float inkm = max(m, border_line(p)) * (1.0 - worn * 0.7);
		alb = mix(wood, ink.rgb * (0.85 + 0.25 * noise(q * 200.0)), inkm);
		metal = inkm * ink_metal;
		rough = mix(0.42 + grime * 0.3 + worn * 0.2, mix(0.55, 0.28, ink_metal), inkm);
		slope = -mask_slope(UV, m) * 0.00012;
		h_scale = 1.0;
	}

	if (v_edge > 0.5) {
		// The plate's edge: the field colour, rough and darker; enamel edges
		// are where the iron shows; an engraved label's edge is its core.
		vec3 ed = style == 4 ? core.rgb * 0.8 : (style == 0 || style == 1 ? mix(field.rgb * 0.6, vec3(0.2, 0.09, 0.04), rust) : field.rgb * 0.7);
		alb = ed;
		rough = 0.7;
		metal = style == 2 ? 0.9 : 0.1;
		slope = vec2(0.0);
	}
	if (v_back > 0.5) {
		alb = field.rgb * 0.6;
		slope = vec2(0.0);
	}

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	AO = ao;
	vec3 n = normalize(vec3(-slope * h_scale, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
}
