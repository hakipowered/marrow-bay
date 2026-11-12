// A quad stretched along the node's (or the particle's) Y axis and turned to
// face the camera around that axis, so it reads from any angle: bullet
// tracers, sparks, blood drops, a muzzle blast along the barrel, a blood
// spray along the shot. Particles: turn on particle_flag_align_y so Y follows
// the velocity. The quad's own height is the streak length (QuadMesh.size.y);
// its width comes from `width`, in metres, times the particle's scale.

uniform float width = 0.02;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
// 0: a soft streak, bright at the head (+Y), fading to the tail.
// 1: a texture from a 2x2 atlas, u along the axis (0 at the tail end).
uniform int mode = 0;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
// First atlas cell to use and how many in a row (cells are picked by the
// particle's animation offset).
uniform int first_frame = 0;
uniform int frame_count = 1;
uniform float tail_fade = 1.5;

varying flat int frame;

void vertex() {
	vec3 axis = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float scale = length((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 dir = normalize(axis + vec3(0.0, 1e-6, 0.0));
	vec3 side = cross(dir, normalize(cam - center));
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 world = center + axis * VERTEX.y + side * VERTEX.x * width * scale;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	frame = first_frame + clamp(int(floor(INSTANCE_CUSTOM.z * float(frame_count))), 0, frame_count - 1);
}

void fragment() {
	vec4 c = tint * COLOR;
	if (mode == 0) {
		float across = 1.0 - abs(UV.x * 2.0 - 1.0);
		float head = smoothstep(0.0, 0.12, UV.y);          // rounded front
		float tail = pow(clamp(1.0 - UV.y, 0.0, 1.0), tail_fade);
		ALBEDO = c.rgb * energy;
		ALPHA = clamp(c.a * smoothstep(0.0, 0.9, across) * head * tail, 0.0, 1.0);
	} else {
		vec2 cell = vec2(float(frame % 2), float(frame / 2)) * 0.5;
		vec2 uv = cell + vec2(1.0 - UV.y, UV.x) * 0.5;
		vec4 t = texture(atlas, uv);
		ALBEDO = t.rgb * c.rgb * energy;
		ALPHA = clamp(t.a * c.a, 0.0, 1.0);
	}
}
