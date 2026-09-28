// Shared by the pipe shaders: pipes are hidden in the walls and only show
// through the holes HandDissolve burns in the scan.
//
// HandDissolve publishes its two dissolve fronts as global uniforms (xyz =
// origin, w = front radius, <= 0 when that hand isn't through). A pipe shows
// inside those spheres, a little past them since the scan's burning edge is
// ragged; the scan still hides it wherever the hole hasn't reached. Masking
// rather than relying on the scan alone keeps pipes out of sight through the
// gaps real scans have.

global uniform vec4 DISSOLVE_SOURCE_0;
global uniform vec4 DISSOLVE_SOURCE_1;

// Set by pipe.gd: shows the pipe everywhere (in the editor, or for debugging).
instance uniform bool always_visible = false;

// How far past a dissolve front the pipe still shows, and over how much of
// that it fades out, in meters.
const float REVEAL_MARGIN = 0.2;
const float REVEAL_FEATHER = 0.1;

float source_reveal(vec4 source, vec3 point) {
	if (source.w <= 0.0) {
		return 0.0;
	}
	float edge = source.w + REVEAL_MARGIN;
	return 1.0 - smoothstep(edge - REVEAL_FEATHER, edge, distance(point, source.xyz));
}

// How much of the pipe shows at [point], in world space: 0 hidden, 1 shown.
float pipe_reveal(vec3 point) {
	if (always_visible) {
		return 1.0;
	}
	return max(source_reveal(DISSOLVE_SOURCE_0, point), source_reveal(DISSOLVE_SOURCE_1, point));
}
