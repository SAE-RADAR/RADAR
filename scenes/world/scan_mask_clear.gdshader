shader_type spatial;
// AR, second of the scan's passes (see scan_mask): turns the black the opaque
// pass drew back into transparent, so passthrough shows where the real walls
// are. Multiplying by 0 sets both color and alpha to 0; it runs first in the
// transparent pass (lowest render_priority, set by HandDissolve), and only
// where the scan is still the nearest thing drawn, so virtual things in front
// of the walls stay.
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://scenes/world/scan_dissolve.gdshaderinc"

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (front(world_position, front_roughness(world_position, TIME)) < 0.0) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
