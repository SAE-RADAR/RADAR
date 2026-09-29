shader_type spatial;
// Patch of foam floating on the water: a quad laid flat and turned at random,
// as wide as the particle's transform says (see cascade_process.gdshader).
//
// Fresh foam is thick and white; as it ages bubbles pop open in it, until
// only ragged strands are left.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap;

// Bubbles across the patch.
uniform float bubble_count : hint_range(1.0, 20.0) = 7.0;
// Size of the popped bubbles in old foam, relative to the space between them.
uniform float hole_size : hint_range(0.0, 1.0) = 0.55;
// How ragged the patch's outline is.
uniform float raggedness : hint_range(0.0, 1.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

varying float seed;
varying float age;

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

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Distance to the nearest bubble center, and that bubble's own size (0 to 1).
vec2 bubbles(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 nearest = vec2(8.0, 0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 h = hash22(cell + offset);
			float d = length(offset + h - f);
			if (d < nearest.x) {
				nearest = vec2(d, fract(h.x * 7.3 + h.y * 3.1));
			}
		}
	}
	return nearest;
}

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	age = INSTANCE_CUSTOM.y;
	float s = length(MODEL_MATRIX[0].xyz);
	float a = seed * TAU;
	vec3 x = vec3(cos(a), 0.0, sin(a));
	vec3 y = vec3(sin(a), 0.0, -cos(a));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * s, 0.0), vec4(y * s, 0.0), vec4(0.0, s, 0.0, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(x, y, vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float lumps = value_noise(UV * 3.0 + seed * 23.0);
	float d = length(p) * (1.0 + raggedness * (lumps - 0.5));
	// Big bubbles and small ones, each popping at its own time.
	vec2 big = bubbles(UV * bubble_count + seed * 17.0);
	vec2 small = bubbles(UV * bubble_count * 2.7 - seed * 11.0);
	float popped = smoothstep(0.1, 0.8, age);
	float big_hole = max(hole_size * popped * step(big.y, popped), 0.001);
	float small_hole = max(hole_size * popped * step(small.y, popped * 1.5), 0.001);
	float lace = smoothstep(big_hole * 0.7, big_hole, big.x) * smoothstep(small_hole * 0.7, small_hole, small.x);
	float shape = exp(-d * d * 2.5) * (1.0 - smoothstep(0.7, 1.0, d));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * shape * mix(0.15, 1.0, lace) * mix(1.0, 0.6 + 0.4 * lumps, popped);
	ROUGHNESS = roughness;
}
