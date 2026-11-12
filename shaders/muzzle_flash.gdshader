shader_type spatial;
// Muzzle flash: a hot core with a few uneven flame petals, additive, always
// facing the camera. Shown for a couple of frames per shot.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 hot = vec3(1.0, 0.92, 0.7);
uniform vec3 warm = vec3(1.0, 0.45, 0.12);

void vertex() {
	// Billboard, keeping the node's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float petals = 0.55 + 0.45 * pow(abs(cos(a * 2.5 + 0.7)), 3.0) + 0.15 * sin(a * 7.0);
	float shape = smoothstep(petals, petals * 0.25, r);
	float core = smoothstep(0.35, 0.0, r);
	vec3 col = mix(warm, hot, core) * (shape * 1.6 + core * 2.5);
	ALBEDO = col;
	ALPHA = clamp(shape + core, 0.0, 1.0);
}
