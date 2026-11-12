shader_type spatial;
// One falling raindrop: a thin streak stretched along its velocity, turned to
// face the camera around that axis. Lit (not unshaded), so drops only show
// where a lamp, sign or fire catches them, like real rain at night. Drops
// right in front of the lens and far away fade out.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.72, 0.78, 0.88);
uniform float opacity = 0.55;
uniform float glow = 0.12;
uniform float near_fade = 1.6;
uniform float far_fade = 30.0;

varying float fade;

void vertex() {
	vec3 axis = MODEL_MATRIX[1].xyz;
	float len = length(axis);
	axis = axis / max(len, 1e-4);
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - pos);
	vec3 right = normalize(cross(axis, to_cam));
	vec3 fwd = cross(right, axis);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(axis * len, 0.0), vec4(fwd, 0.0), vec4(pos, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float d = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	fade = smoothstep(near_fade * 0.5, near_fade * 2.0, d) * (1.0 - smoothstep(far_fade * 0.7, far_fade, d));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.45, UV.y) * smoothstep(1.0, 0.8, UV.y);
	ALBEDO = tint;
	ROUGHNESS = 0.08;
	SPECULAR = 1.0;
	EMISSION = tint * glow;
	ALPHA = opacity * across * across * along * fade;
}
