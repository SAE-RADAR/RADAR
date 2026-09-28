shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.93, 0.95, 0.97, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.45;
uniform sampler2D wisps : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wisp_scale = 0.7;
uniform float wisp_speed = 0.02;
uniform float near_fade_start = 0.25;
uniform float near_fade_end = 1.0;

varying float seed;

void vertex() {
	mat4 billboard = mat4(
			normalize(INV_VIEW_MATRIX[0]),
			normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]),
			MODEL_MATRIX[3]);
	float angle = INSTANCE_CUSTOM.x;
	billboard *= mat4(
			vec4(cos(angle), -sin(angle), 0.0, 0.0),
			vec4(sin(angle), cos(angle), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = fract(float(INSTANCE_ID) * 0.6180339);
}

void fragment() {
	float blob = 1.0 - smoothstep(0.15, 1.0, length(UV - 0.5) * 2.0);
	vec2 drift = vec2(seed * 17.0, seed * 5.0 - TIME * wisp_speed);
	float wisp = smoothstep(0.2, 0.8, texture(wisps, UV * wisp_scale + drift).r);
	float near = smoothstep(near_fade_start, near_fade_end, length(VERTEX));
	ALBEDO = color.rgb * COLOR.rgb;
	ALPHA = blob * mix(0.3, 1.0, wisp) * density * COLOR.a * near;
}
