shader_type spatial;
// A shot-out window pane: a jagged hole where it was hit, sharp shards still
// standing in the frame round it, and cracks running out across what's left.
// Breakable._crack_at() sets it up from the pane's old material.
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.3, 0.36, 0.45, 0.42);
uniform vec3 glow : source_color = vec3(0.16, 0.22, 0.32);
uniform float glow_energy = 0.7;
uniform vec2 pane = vec2(1.5, 1.9);     // metres
uniform vec2 hole_at = vec2(0.5);       // UV of the hit
uniform float hole = 0.6;               // metres, average reach of the hole
uniform float seed = 0.0;

float h1(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

// Spiky outline: the hole's reach at angle a (0..1 round the circle).
float jag(float a) {
	float n = 17.0;
	float x = a * n;
	float i = floor(x);
	float f = fract(x);
	float p = h1(mod(i, n));
	float q = h1(mod(i + 1.0, n));
	// Long thin spikes now and then: glass breaks in daggers.
	float spike = step(0.72, h1(i + 31.0)) * (1.0 - abs(f - 0.5) * 2.0) * 0.9;
	return mix(p, q, f) + spike;
}

void fragment() {
	vec2 p = (UV - hole_at) * pane;
	float d = length(p);
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float r = hole * (0.35 + 0.75 * jag(a));
	if (d < r) {
		discard;
	}
	// Cracks fanning out from the hole.
	float n = 11.0;
	float k = a * n;
	float ki = floor(k);
	float ca = (ki + 0.5 + (h1(ki + 40.0) - 0.5) * 0.7) / n;
	float across = abs(a - ca) * 6.2831853 * d;
	float reach = r + hole * (0.5 + h1(ki + 80.0) * 1.6);
	float crack = (1.0 - smoothstep(0.0025, 0.007, across)) * (1.0 - smoothstep(reach * 0.75, reach, d));
	// A ring crack or two round the hole.
	float ring = 0.0;
	for (int j = 0; j < 2; j++) {
		float rr = r + hole * (0.25 + 0.35 * float(j)) * (0.8 + 0.4 * h1(ki + float(j) * 7.0));
		ring = max(ring, 1.0 - smoothstep(0.002, 0.006, abs(d - rr)));
	}
	ring *= step(0.4, h1(ki + 13.0));
	// The fresh broken edge catches the light.
	float rim = 1.0 - smoothstep(0.0, 0.018, d - r);
	float line = max(max(crack, ring), rim);
	ALBEDO = mix(tint.rgb, vec3(0.82, 0.88, 0.95), line * 0.75);
	ALPHA = clamp(tint.a + line * 0.45, 0.0, 1.0);
	EMISSION = glow * glow_energy + vec3(0.25, 0.3, 0.35) * line * 0.5;
	ROUGHNESS = 0.1;
	SPECULAR = 0.9;
}
