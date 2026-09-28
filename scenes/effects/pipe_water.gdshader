shader_type spatial;
// Water inside a pipe, drawn on the inner tube pipe.gd builds along the
// route. UV.x runs along the pipe in meters (0 at the inlet), UV.y around it.
//
// The water takes the color of its temperature, which goes from the inlet's to
// the outlet's along the pipe, with streaks of current drifting downstream.
// Arrows of the same color travel with the flow. They are painted facing the
// eye: seen from anywhere, a point on the tube is sin(angle between its normal
// and the view) * radius away from the axis, so shapes drawn over (along the
// pipe, that distance) look flat and upright from any side.
//
// Unshaded so the temperatures read the same in the dark as in the light.
render_mode blend_mix, cull_back, shadows_disabled, unshaded;

#include "res://scenes/effects/pipe_reveal.gdshaderinc"

// Set by pipe.gd.
instance uniform float pipe_length = 1.0;
instance uniform float water_radius = 0.035;
instance uniform float inlet_temperature = 40.0;
instance uniform float outlet_temperature = 38.0;
instance uniform float flow_speed = 0.4;
// How far the water has flowed, in meters, wrapping now and then.
instance uniform float flow_offset = 0.0;

group_uniforms temperature;
// Color scale shared by every pipe: four stops, coldest first, at the
// temperatures in stop_temperatures (°C); beyond the ends, the end colors.
// Defaults live here rather than in a texture so the scale survives the
// material losing its parameters.
uniform vec4 stop_temperatures = vec4(10.0, 22.0, 33.0, 45.0);
uniform vec3 cold_color : source_color = vec3(0.1, 0.35, 1.0);
uniform vec3 cool_color : source_color = vec3(0.1, 0.85, 0.95);
uniform vec3 warm_color : source_color = vec3(1.0, 0.8, 0.15);
uniform vec3 hot_color : source_color = vec3(1.0, 0.12, 0.08);

group_uniforms water;
uniform float water_opacity : hint_range(0.0, 1.0) = 0.65;
// Brightness of the water next to the arrows.
uniform float water_brightness : hint_range(0.0, 2.0) = 0.55;
// How much the streaks of current stand out.
uniform float current_amount : hint_range(0.0, 1.0) = 0.6;
// Length of a streak, in meters, and how many fit around the pipe.
uniform float current_length : hint_range(0.02, 2.0) = 0.25;
uniform int current_bands : hint_range(1, 16) = 5;

group_uniforms arrows;
// Distance between arrows, and their length, in meters.
uniform float arrow_spacing : hint_range(0.05, 2.0) = 0.4;
uniform float arrow_length : hint_range(0.02, 1.0) = 0.14;
// Share of the arrow's length taken by its head.
uniform float head_ratio : hint_range(0.1, 1.0) = 0.5;
// Half widths of the head and the shaft, as shares of the water's radius.
uniform float head_width : hint_range(0.1, 1.0) = 0.9;
uniform float shaft_width : hint_range(0.05, 1.0) = 0.35;
uniform float arrow_brightness : hint_range(0.0, 4.0) = 1.4;
// Dark line around the arrows so they read over water of the same color, in meters.
uniform float outline_width : hint_range(0.0, 0.02) = 0.004;
// Below this speed the water counts as still and shows no arrows, in m/s.
uniform float still_speed : hint_range(0.0, 0.5) = 0.02;

varying vec3 world_position;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise repeating every [period] cells along y, so it meets itself
// around the pipe.
float wrapped_noise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float y0 = mod(i.y, period);
	float y1 = mod(i.y + 1.0, period);
	return mix(
			mix(hash12(vec2(i.x, y0)), hash12(vec2(i.x + 1.0, y0)), u.x),
			mix(hash12(vec2(i.x, y1)), hash12(vec2(i.x + 1.0, y1)), u.x),
			u.y);
}

vec3 temperature_color(float along) {
	float temperature = mix(inlet_temperature, outlet_temperature, clamp(along / max(pipe_length, 0.0001), 0.0, 1.0));
	vec4 t = stop_temperatures;
	vec3 color = mix(cold_color, cool_color, clamp((temperature - t.x) / max(t.y - t.x, 0.0001), 0.0, 1.0));
	color = mix(color, warm_color, clamp((temperature - t.y) / max(t.z - t.y, 0.0001), 0.0, 1.0));
	return mix(color, hot_color, clamp((temperature - t.z) / max(t.w - t.z, 0.0001), 0.0, 1.0));
}

// Signed distance to an arrow pointing toward +x, centered on the origin:
// [x] along the pipe, [y] away from its axis, in meters.
float arrow_distance(float x, float y) {
	float half_length = arrow_length * 0.5;
	float head = arrow_length * head_ratio;
	float head_half = head_width * water_radius;
	float shaft_half = shaft_width * water_radius;
	float base = half_length - head;
	float slant = (y * head + (x - half_length) * head_half) / length(vec2(head, head_half));
	float head_distance = max(base - x, slant);
	float shaft_distance = max(max(-half_length - x, x - base), y - shaft_half);
	return min(head_distance, shaft_distance);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float reveal = pipe_reveal(world_position);
	if (reveal <= 0.0) {
		discard;
	}

	float along = UV.x;
	float moved = along - flow_offset;
	vec3 color = temperature_color(along);

	float bands = float(current_bands);
	float current = wrapped_noise(vec2(moved / current_length, UV.y * bands), bands);
	current = smoothstep(0.4, 0.9, current) * current_amount;
	vec3 water = color * water_brightness * (0.75 + current);
	float water_alpha = water_opacity * (0.8 + 0.4 * current);

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float y = sqrt(1.0 - facing * facing) * water_radius;
	float x = mod(moved, arrow_spacing) - arrow_spacing * 0.5;
	float d = arrow_distance(x, y);
	float aa = max(fwidth(d), 0.00001);
	float flowing = smoothstep(still_speed, still_speed * 2.0 + 0.001, flow_speed);
	float arrow = clamp(0.5 - d / aa, 0.0, 1.0) * flowing;
	float outline = clamp(0.5 - (d - outline_width) / aa, 0.0, 1.0) * flowing;

	vec3 arrow_color = color * arrow_brightness;
	ALBEDO = mix(water * (1.0 - 0.8 * outline), arrow_color, arrow);
	ALPHA = max(water_alpha, max(arrow, outline * 0.7)) * reveal;
}
