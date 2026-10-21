shader_type spatial;
// AR, last of the scan's passes (see scan_mask): what is still drawn of the
// scan over passthrough. The dissolve's glowing rim and tunnel rings, as in
// VR, and the scan itself at [member preview_opacity], to check how it lines
// up with the real walls. HandDissolve only adds this pass while there is
// something to draw.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://scenes/world/scan_dissolve.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float preview_opacity : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float roughness = front_roughness(world_position, TIME);
	float f = front(world_position, roughness);
	vec3 into = normalize(world_position - CAMERA_POSITION_WORLD);

	float glow;
	float opacity = 0.0;
	if (f < 0.0) {
		glow = depth_rings(world_position, into, roughness);
		if (glow < 0.35) {
			discard;
		}
	} else {
		float rim = 1.0 - smoothstep(0.0, edge_width, f);
		glow = rim * rim;
		if (f < edge_width * 2.0) {
			glow += depth_rings(world_position, into, roughness) * 0.6;
		}
		opacity = preview_opacity;
	}
	vec3 glow_color = edge_color * edge_energy * glow;
	float glow_alpha = clamp(glow, 0.0, 1.0);
	ALPHA = max(opacity, glow_alpha);
	if (ALPHA <= 0.0) {
		discard;
	}
	vec3 albedo = texture(albedo_texture, UV).rgb;
	ALBEDO = mix(albedo, glow_color, glow_alpha);
}
