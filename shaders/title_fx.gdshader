shader_type canvas_item;
// Title screen overlay: three depths of slanted rain streaks sliding down the
// screen, a dark vignette, and a lightning flash the script drives.

uniform float flash = 0.0;
uniform float rain_amount = 1.0;
uniform vec3 rain_color : source_color = vec3(0.78, 0.82, 0.92);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float aspect = 1.0 / max(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 1e-3);
	float rain = 0.0;
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		float cols = (70.0 + 55.0 * fl) * aspect / 1.2;
		vec2 q = vec2(uv.x + uv.y * 0.1, uv.y);
		float cx = q.x * cols;
		float c = floor(cx);
		float r = hash(vec2(c, fl * 13.0));
		if (r < 0.35) continue;
		float k = 1.2 + r * 0.9;
		float speed = 1.1 + r * 0.5 + fl * 0.35;
		float len = (0.05 + 0.05 * r) * (1.0 - fl * 0.25);
		float t = fract((q.y - TIME * speed) * k + r * 7.13);
		float streak = smoothstep(0.0, len * k, t) * step(t, len * k);
		float dx = abs(fract(cx) - 0.5);
		float thin = smoothstep(0.16 - fl * 0.04, 0.0, dx);
		rain += thin * streak * (0.55 - 0.15 * fl);
	}
	rain = clamp(rain * rain_amount, 0.0, 1.0) * 0.45;
	float vig = smoothstep(0.38, 0.95, length((uv - 0.5) * vec2(1.25, 1.0))) * 0.8;
	float a = max(max(vig, rain), flash * 0.35);
	vec3 col = mix(vec3(0.0), rain_color, rain / max(a, 1e-3));
	col = mix(col, vec3(0.85, 0.9, 1.0), flash);
	COLOR = vec4(col, a);
}
