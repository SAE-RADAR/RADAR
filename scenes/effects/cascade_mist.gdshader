shader_type spatial;
// Mist puff: a camera-facing soft blob, lumpy and slowly turning, as wide as
// the particle's transform says (see cascade_process.gdshader).
//
// Lit by the scene, and glowing when the light comes from behind it. Faces the
// main camera rather than each eye, so both eyes see the same shape.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled;

// How lumpy the puff's outline is.
uniform float lumpiness : hint_range(0.0, 1.0) = 0.5;
// Turns per second, at most; each puff turns its own way.
uniform float spin : hint_range(0.0, 1.0) = 0.05;
// Share of the light from behind that passes through.
uniform float translucency : hint_range(0.0, 1.0) = 0.8;

varying float seed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0] * s, MAIN_CAM_INV_VIEW_MATRIX[1] * s,
			MAIN_CAM_INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(MAIN_CAM_INV_VIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = seed * TAU + TIME * spin * TAU * (seed * 2.0 - 1.0);
	p = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p;
	float n = value_noise(p * 2.5 + seed * 91.0) * 0.65 + value_noise(p * 5.0 - seed * 37.0) * 0.35;
	float d = length(p) * (1.0 + lumpiness * (n - 0.5));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * exp(-d * d * 4.0) * (1.0 - smoothstep(0.7, 1.0, d));
	ROUGHNESS = 1.0;
	BACKLIGHT = COLOR.rgb * translucency;
}
