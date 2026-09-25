shader_type spatial;
// Firefly: a camera-facing glowing dot that flashes now and then.
//
// Each firefly blinks on its own rhythm with a dim glow in between, fades in
// and out over its life, and glows steadily while gathered in a swarm
// (CUSTOM data from fireflies_process.gdshader).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_warm : source_color = vec3(0.75, 1.0, 0.2);
uniform vec3 color_cool : source_color = vec3(0.2, 1.0, 0.55);
uniform float energy : hint_range(0.0, 8.0) = 1.4;
// Flashes per second, on average.
uniform float blink_rate : hint_range(0.0, 2.0) = 0.35;
// Brightness between flashes.
uniform float idle_glow : hint_range(0.0, 1.0) = 0.12;

varying vec3 tint;

void vertex() {
	// Face the camera, keeping the particle's scale.
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0] * s, MAIN_CAM_INV_VIEW_MATRIX[1] * s,
			MAIN_CAM_INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	float seed = INSTANCE_CUSTOM.x;
	float life = INSTANCE_CUSTOM.y;
	float gathered = INSTANCE_CUSTOM.z;
	float fade = smoothstep(0.0, 0.08, life) * (1.0 - smoothstep(0.85, 1.0, life));
	// A short flash once per cycle; each firefly has its own rate and phase.
	float phase = fract(TIME * blink_rate * (0.6 + 0.8 * fract(seed * 13.7)) + seed);
	float flash = exp(-pow((phase - 0.5) * 9.0, 2.0));
	float glow = mix(idle_glow + (1.0 - idle_glow) * flash, 1.0, gathered);
	tint = mix(color_warm, color_cool, fract(seed * 5.3)) * glow * fade * energy;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float core = exp(-d * d * 20.0);
	float halo = exp(-d * d * 4.0) * 0.3;
	ALBEDO = tint * (core * 2.0 + halo) * (1.0 - smoothstep(0.8, 1.0, d));
}
