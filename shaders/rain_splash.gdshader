shader_type spatial;
// A raindrop hitting the ground: a small crown of droplets thrown up and out,
// plus a flattened ring spreading at its base. Drawn on a camera-facing quad
// whose bottom edge sits on the ground; INSTANCE_CUSTOM.y is the splash's age.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.75, 0.8, 0.9);
uniform float opacity = 0.55;
uniform float glow = 0.05;

varying float age;
varying float fade;
varying float seed;

void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, vec4(0.0, s, 0.0, 0.0), INV_VIEW_MATRIX[2] * s, vec4(pos, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	age = INSTANCE_CUSTOM.y;
	seed = fract(sin(dot(pos.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float d = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	fade = smoothstep(0.8, 2.2, d) * (1.0 - smoothstep(12.0, 18.0, d));
}

void fragment() {
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);   // y up, -1 at the ground
	float a = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ang = mix(-1.15, 1.15, fi / 4.0) + (seed - 0.5) * 0.5;
		vec2 dir = vec2(sin(ang), cos(ang) * (0.8 + 0.4 * fract(seed * 7.0 + fi * 0.37)));
		vec2 p = vec2(0.0, -0.9) + dir * age * 1.5 + vec2(0.0, -2.2 * age * age);
		a += smoothstep(0.11, 0.02, length(uv - p)) * step(-0.95, p.y);
	}
	float ring = smoothstep(0.07, 0.0, abs(length(vec2(uv.x * 0.55, (uv.y + 0.9) * 3.0)) - age * 0.55));
	a = max(a, ring * 0.6);
	ALBEDO = tint;
	ROUGHNESS = 0.1;
	SPECULAR = 1.0;
	EMISSION = tint * glow;
	ALPHA = clamp(a, 0.0, 1.0) * opacity * (1.0 - age) * fade;
}
