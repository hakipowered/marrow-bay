shader_type canvas_item;
// Full-screen horror grade: film grain, vignette, slight chromatic fringing,
// and a pulsing red edge + desaturation when the player is badly hurt.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.06;
uniform float vignette = 0.25;
uniform float fringe = 0.0015;
uniform float hurt = 0.0;      // 0 healthy .. 1 near death
uniform float fear = 0.0;      // spikes during scares / stalker nearby

float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float f = fringe * (1.0 + fear * 3.0 + hurt * 2.0);
	vec3 col;
	col.r = texture(screen_tex, uv + c * f).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * f).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), hurt * 0.7);
	float pulse = 0.5 + 0.5 * sin(TIME * (4.0 + hurt * 4.0));
	float v = smoothstep(1.0, 0.3, length(c) * (1.0 + vignette));
	col *= mix(1.0, v, 0.6);
	col = mix(col, vec3(0.45, 0.0, 0.0), (1.0 - v) * hurt * (0.5 + 0.5 * pulse));
	col += (rand(uv * TIME) - 0.5) * (grain + fear * 0.05);
	COLOR = vec4(col, 1.0);
}
