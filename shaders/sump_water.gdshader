shader_type spatial;
// Black, cold, still water in the pump room's flooded sump (chapter 2): a
// nearly opaque skin with slow ripples that catch the red lamps and the
// flashlights. churn boils the surface over the river inlet while it runs,
// swirl turns a whirlpool over the drain while the sump empties, backflow
// belches bubbles up over the drain when the sewer pushes back.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.028, 0.032, 0.026, 1.0);
uniform vec4 silt : source_color = vec4(0.11, 0.1, 0.07, 1.0);
uniform vec4 foam_color : source_color = vec4(0.42, 0.42, 0.38, 1.0);
uniform float opacity = 0.94;
uniform float churn = 0.0;
uniform vec2 churn_at = vec2(0.0, 0.0);   // world xz
uniform float swirl = 0.0;
uniform vec2 swirl_at = vec2(0.0, 0.0);   // world xz
uniform float backflow = 0.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float height(vec2 p, float t) {
	float h = vnoise(p * 1.7 + vec2(t * 0.07, t * 0.05)) * 0.6 + vnoise(p * 4.3 - vec2(t * 0.11, -t * 0.08)) * 0.25;
	h *= 0.012;
	vec2 c = p - churn_at;
	float rc = length(c);
	h += churn * (vnoise(p * 7.0 + vec2(t * 2.3, -t * 1.9)) - 0.5) * 0.05 * exp(-rc * 1.6);
	vec2 s = p - swirl_at;
	float rs = length(s) + 0.001;
	float a = atan(s.y, s.x);
	h += swirl * sin(a * 3.0 + rs * 9.0 - t * 7.0) * 0.028 * exp(-rs * 1.2);
	h -= swirl * 0.05 * exp(-rs * 3.0);
	h += backflow * (vnoise(s * 9.0 + vec2(0.0, t * 3.0)) - 0.5) * 0.06 * exp(-rs * 2.5);
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	float e = 0.02;
	float h0 = height(p, t);
	float hx = height(p + vec2(e, 0.0), t);
	float hz = height(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3(-(hx - h0) / e, 1.0, -(hz - h0) / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Scum and silt drifting on it, foam where it churns.
	float scum = smoothstep(0.62, 0.9, vnoise(p * 2.2 + vec2(t * 0.02, 0.0))) * 0.5;
	float rc = length(p - churn_at);
	float foam = churn * smoothstep(1.2, 0.0, rc) * smoothstep(0.35, 0.75, vnoise(p * 6.0 + vec2(t * 1.7, t * 1.3)));
	float rs = length(p - swirl_at);
	foam += swirl * smoothstep(0.9, 0.1, rs) * smoothstep(0.4, 0.8, vnoise(vec2(atan(p.y - swirl_at.y, p.x - swirl_at.x) * 2.0 - t * 3.0, rs * 5.0)));
	foam += backflow * smoothstep(0.7, 0.0, rs) * smoothstep(0.45, 0.8, vnoise(p * 10.0 + vec2(0.0, t * 4.0)));
	vec3 col = mix(deep.rgb, silt.rgb, scum);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.05, 0.5, clamp(scum + foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = mix(opacity, 1.0, clamp(foam, 0.0, 1.0));
}
