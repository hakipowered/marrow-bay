shader_type canvas_item;
// Behind the bag: the game, blurred and pushed into shadow, with a red-black
// vignette and a little film grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 3.2;
uniform float darken = 0.42;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur * fade).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l) * vec3(1.0, 0.92, 0.86), 0.55 * fade);
	vec2 d = UV - 0.5;
	float v = smoothstep(0.85, 0.2, length(d * vec2(1.25, 1.0)));
	c *= mix(1.0, darken * mix(0.55, 1.0, v), fade);
	c += vec3(0.05, 0.0, 0.0) * (1.0 - v) * fade;
	c += (hash(UV * 913.0 + TIME) - 0.5) * 0.025 * fade;
	COLOR = vec4(c, 1.0);
}
