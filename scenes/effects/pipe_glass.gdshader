shader_type spatial;
// Glass of a pipe, drawn on the outer tube pipe.gd builds along the route.
// UV.x runs along the pipe in meters, UV.y around it.
//
// Nearly clear where it faces the eye so the water shows, thicker toward the
// edges like real glass, with collars where the pipe's sections meet. Drawn
// after the water (render_priority 1 in pipe_glass_material.tres).
render_mode blend_mix, cull_back, shadows_disabled;

#include "res://scenes/effects/pipe_reveal.gdshaderinc"

uniform vec3 glass_color : source_color = vec3(0.85, 0.95, 1.0);
// Opacity where the glass faces the eye, and at its edges.
uniform float facing_opacity : hint_range(0.0, 1.0) = 0.05;
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.45;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.05;

group_uniforms joints;
// Distance between the collars and their width, in meters.
uniform float joint_spacing : hint_range(0.1, 10.0) = 1.0;
uniform float joint_width : hint_range(0.0, 0.2) = 0.025;
uniform vec3 joint_color : source_color = vec3(0.7, 0.74, 0.78);
uniform float joint_opacity : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float reveal = pipe_reveal(world_position);
	if (reveal <= 0.0) {
		discard;
	}

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);

	// Distance to the nearest collar.
	float to_joint = abs(mod(UV.x + joint_spacing * 0.5, joint_spacing) - joint_spacing * 0.5);
	float aa = max(fwidth(UV.x), 0.00001);
	float joint = 1.0 - smoothstep(joint_width * 0.5 - aa, joint_width * 0.5 + aa, to_joint);

	ALBEDO = mix(glass_color, joint_color, joint);
	ALPHA = mix(mix(facing_opacity, edge_opacity, fresnel), joint_opacity, joint) * reveal;
	ROUGHNESS = mix(glass_roughness, 0.4, joint);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
