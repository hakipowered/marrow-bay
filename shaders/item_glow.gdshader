shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
// Soft halo around a pickup that pulses on and off every few seconds
// (a short shimmer, then darkness), so items read from across a room.
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float period = 2.6;
uniform float phase = 0.0;
uniform float strength = 1.4;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float halo = pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	float t = mod(TIME + phase, period) / period;
	// quick rise, slow fade, then off for the rest of the cycle
	float pulse = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.08, 0.45, t));
	float star = pow(max(0.0, 1.0 - abs(uv.x) * 6.0) * max(0.0, 1.0 - abs(uv.y) * 1.2), 2.0)
	           + pow(max(0.0, 1.0 - abs(uv.y) * 6.0) * max(0.0, 1.0 - abs(uv.x) * 1.2), 2.0);
	vec3 c = glow_color.rgb * (halo * 0.55 + star * 0.9) * (0.12 + pulse * strength);
	ALBEDO = c;
	ALPHA = clamp(halo + star, 0.0, 1.0);
}
