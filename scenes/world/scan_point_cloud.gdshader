shader_type spatial;
// Point cloud drawn in place of a scan (see ScanPointCloud). Each vertex is one
// point, sized in meters so the cloud reads the same near and far, and colored
// by the scanner. Points inside HandDissolve's fronts are dropped, with the
// same glowing rim as scan_dissolve.gdshader just outside them.
render_mode unshaded, cull_disabled, shadows_disabled;

global uniform vec4 DISSOLVE_SOURCE_0;
global uniform vec4 DISSOLVE_SOURCE_1;

// Point diameter, in meters.
uniform float point_size : hint_range(0.001, 0.2) = 0.02;
// Caps how large a point gets right next to the eye, in pixels.
uniform float max_pixels : hint_range(1.0, 64.0) = 24.0;

group_uniforms edge;
uniform vec3 edge_color : source_color = vec3(0.25, 1.0, 0.65);
uniform float edge_energy : hint_range(0.0, 16.0) = 2.5;
// Width of the burning band outside the front, in meters.
uniform float edge_width : hint_range(0.0, 1.0) = 0.12;
group_uniforms;

// Animations, set from ScanPointCloud. Offsets are in meters, around the
// cloud's center in its own (Y-up) space.
group_uniforms animation;
uniform vec3 cloud_center;
uniform float speed = 1.0;
uniform float strength = 1.0;
uniform bool breathing = false;
uniform bool wave = false;
uniform bool dispersion = false;
uniform bool spiral = false;
uniform bool glitch = false;
uniform bool erosion = false;
group_uniforms;

varying vec3 color;
varying float rim;

float front(vec3 p, vec4 source) {
	return source.w > 0.0 ? distance(p, source.xyz) - source.w : 1e6;
}

// Stable random value in [0, 1] per point (PCG hash of its index).
float point_seed(int id) {
	uint h = uint(id) * 747796405u + 2891336453u;
	h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
	h = (h >> 22u) ^ h;
	return float(h) / 4294967295.0;
}

void vertex() {
	vec3 p = VERTEX - cloud_center;
	vec3 out_dir = normalize(p + vec3(0.001));
	float seed = point_seed(VERTEX_ID);
	float t = TIME * speed;
	bool eroded = false;

	if (breathing) {
		p += out_dir * (sin(t * 1.5) * 0.5 + 0.5) * strength * 0.3;
	}
	if (wave) {
		p.y += sin(p.x * 0.5 + t * 2.0) * strength * 0.5;
	}
	if (dispersion) {
		p += out_dir * sin(t + seed * 10.0) * strength * 0.5;
	}
	if (spiral) {
		float angle = t * 0.5 + seed * 6.283;
		float radius = length(p.xz);
		p.xz += vec2(sin(angle), cos(angle)) * radius * 0.1 * strength;
	}
	if (glitch) {
		float jump = step(0.96, fract(sin(seed * 123.4 + floor(t * 10.0)) * 43758.5));
		p.xz += jump * vec2(sin(t * 30.0), cos(t * 25.0)) * strength;
	}
	if (erosion) {
		eroded = sin((VERTEX.x - cloud_center.x) * 10.0 + t) > 0.8;
		p += out_dir * sin(t * 2.0 + seed * 50.0) * strength * 0.2;
	}
	VERTEX = p + cloud_center;

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float f = min(front(world, DISSOLVE_SOURCE_0), front(world, DISSOLVE_SOURCE_1));
	rim = 1.0 - smoothstep(0.0, edge_width, f);

	// Scanner colors are sRGB; shading is linear.
	vec3 c = COLOR.rgb;
	color = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));

	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float depth = max(-view.z, 0.05);
	POINT_SIZE = clamp(point_size * PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5 / depth,
			1.0, max_pixels);
	// Dissolved: outside the clip volume, so the point isn't drawn at all.
	POSITION = f < 0.0 || eroded ? vec4(2.0, 2.0, 2.0, 1.0) : PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = mix(color, edge_color * edge_energy, rim);
}
