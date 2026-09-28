shader_type spatial;
// Streak of falling water: a quad stretched along the particle's motion and
// turned around it to face the camera, as long and wide as the particle's
// transform says (see cascade_process.gdshader). The head is solid, the tail
// thins out, and threads run down its length.
//
// Lit by the scene like the rest of the waterfall, with light passing through
// it from behind. Faces the main camera rather than each eye, so both eyes see
// the same shape.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap;

// Brightness of the threads running down the streak, relative to its body.
uniform float thread_contrast : hint_range(0.0, 1.0) = 0.35;
// Share of the streak's width that is solid; the rest fades out.
uniform float core_width : hint_range(0.0, 1.0) = 0.3;
// Share of the light from behind that passes through.
uniform float translucency : hint_range(0.0, 1.0) = 0.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;

varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz - center;
	vec3 side = cross(axis, to_camera);
	float side_length = length(side);
	// Seen end-on, any side will do.
	side = side_length > 0.00001 ? side / side_length : MAIN_CAM_INV_VIEW_MATRIX[0].xyz;
	vec3 facing = normalize(cross(side, axis));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * width, 0.0), vec4(axis, 0.0), vec4(facing, 0.0), vec4(center, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(normalize(side), normalize(axis), facing);
}

void fragment() {
	// UV.y runs from the head (0) to the tail (1).
	float across = abs(UV.x * 2.0 - 1.0);
	float body = 1.0 - smoothstep(core_width, 1.0, across);
	float head = smoothstep(0.0, 0.12, UV.y);
	float tail = 1.0 - smoothstep(0.25, 1.0, UV.y);
	float threads = 1.0 - thread_contrast * (0.5 + 0.5 * sin(UV.x * 18.0 + seed * 60.0));
	ALBEDO = COLOR.rgb * mix(1.0, threads, 0.5);
	ALPHA = COLOR.a * body * head * tail * threads;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
	BACKLIGHT = COLOR.rgb * translucency;
}
