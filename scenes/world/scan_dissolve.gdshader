shader_type spatial;
// Scan surface that dissolves away from up to two points, with a glowing front
// (see scan_dissolve.gdshaderinc). Lighting matches the scan's
// StandardMaterial3D.
render_mode cull_disabled;

#include "res://scenes/world/scan_dissolve.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb;
	float roughness = front_roughness(world_position, TIME);
	float f = front(world_position, roughness);
	vec3 into = normalize(world_position - CAMERA_POSITION_WORLD);

	if (f < 0.0) {
		// Cut away, except where the tunnel's deeper rings show through.
		float glow = depth_rings(world_position, into, roughness);
		if (glow < 0.35) {
			discard;
		}
		ALBEDO = vec3(0.0);
		EMISSION = edge_color * edge_energy * glow;
	} else {
		float rim = 1.0 - smoothstep(0.0, edge_width, f);
		float glow = rim * rim;
		if (f < edge_width * 2.0) {
			glow += depth_rings(world_position, into, roughness) * 0.6;
		}
		// Surface chars just before it burns away.
		ALBEDO = albedo * (1.0 - 0.75 * rim);
		EMISSION = edge_color * edge_energy * glow;
	}
	ROUGHNESS = 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
