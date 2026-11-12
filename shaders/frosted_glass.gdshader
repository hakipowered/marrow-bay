shader_type spatial;
// Frosted (acid-etched) glass: shows a heavily blurred, tinted copy of what is
// behind it, so a lit room reads as a glow and anyone walking past is only a
// dark shape. Used for the reading-room pane where the Tallyman is first seen.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 tint : source_color = vec3(0.92, 0.96, 0.9);
uniform float blur = 4.5;
uniform float frost = 0.012;
uniform float grime = 0.35;
uniform vec3 base_glow : source_color = vec3(0.035, 0.045, 0.045);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A fixed disc of taps at full resolution: the screen copy has no mipmaps on
// every renderer, so a mip-level blur can come back black.
const vec2 TAPS[12] = vec2[](
	vec2(-0.326, -0.406), vec2(-0.840, -0.074), vec2(-0.696, 0.457), vec2(-0.203, 0.621),
	vec2(0.962, -0.195), vec2(0.473, -0.480), vec2(0.519, 0.767), vec2(0.185, -0.893),
	vec2(0.507, 0.064), vec2(0.896, 0.412), vec2(-0.322, -0.933), vec2(-0.792, -0.598));

void fragment() {
	vec2 n = vec2(noise(UV * 90.0), noise(UV * 90.0 + 17.3)) - 0.5;
	vec2 suv = SCREEN_UV + n * frost;
	float r = blur * 0.006;
	vec2 aspect = vec2(VIEWPORT_SIZE.y / VIEWPORT_SIZE.x, 1.0);
	vec3 c = textureLod(screen_tex, suv, 0.0).rgb;
	for (int i = 0; i < 12; i++) {
		c += textureLod(screen_tex, suv + TAPS[i] * r * aspect, 0.0).rgb;
	}
	c /= 13.0;
	// Dirt collects toward the bottom of the pane and in blotches.
	float dirt = smoothstep(0.35, 0.0, UV.y) * 0.5 + noise(UV * 7.0) * 0.5;
	c *= mix(1.0, 0.55, dirt * grime);
	ALBEDO = c * tint + base_glow;
}
