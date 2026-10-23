shader_type spatial;
// AR, first of the scan's three passes over passthrough: the scan as an
// invisible mask. This opaque pass writes the scan's depth, so virtual things
// behind the real walls (pipes, water) are hidden, and the water's depth
// texture sees the real floor. It draws black; scan_mask_clear, its next pass,
// then clears that black to transparent so passthrough shows.
//
// The dissolve holes are cut out of the mask, so what HandDissolve reveals
// shows through them.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

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
}
