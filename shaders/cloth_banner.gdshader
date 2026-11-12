shader_type spatial;
// A bedsheet banner hung by its top corners: sags in the middle, ripples in
// the wind more toward the bottom edge, ragged where the alpha is cut away.
render_mode cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float wind = 1.0;
uniform float sag = 0.16;

void vertex() {
	float hang = UV.y;                       // 0 at the top edge, 1 at the bottom
	float pinned = sin(UV.x * PI);           // corners are tied, the middle sags
	VERTEX.y -= sag * pinned * (0.4 + 0.6 * hang);
	float ripple = sin(TIME * 1.6 + UV.x * 7.0) * 0.05 + sin(TIME * 2.9 + UV.x * 13.0 + UV.y * 3.0) * 0.025;
	VERTEX.z += ripple * wind * (0.25 + hang) * (0.3 + 0.7 * pinned);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * (FRONT_FACING ? 1.0 : 0.55);
	ROUGHNESS = 0.92;
	// Soaked cloth: a little sheen near the bottom where the rain runs down.
	SPECULAR = 0.3 + 0.2 * UV.y;
	BACKLIGHT = vec3(0.25);
}
