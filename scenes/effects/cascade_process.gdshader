shader_type particles;
// Particles thrown out of an emitter box and pulled down by gravity, shared by
// the layers of a waterfall (see cascade.gd): the streaks the sheet tears
// into, the spray where it lands, the mist rising from it and the foam
// spreading on the water.
//
// Each particle leaves in a random direction within a cone around
// emission_direction, slows with damping, wanders with turbulence, grows,
// changes color and fades over its life, and can die once it has dropped a set
// distance below the emitter. Its transform is laid out for the draw shaders:
// Y along its motion (as long as the streak it leaves), X across it (its
// width).
//
// CUSTOM.x = per-particle random seed, CUSTOM.y = life phase (0 to 1),
// CUSTOM.z = random share of the scale taken off.
//
// Adapted from "Blood Spray Particles" on godotshaders.com.

group_uniforms emission;
// Half size of the box particles spawn in, in the emitter's space.
uniform vec3 emission_extents = vec3(0.5, 0.0, 0.0);
// Launch direction, in the emitter's space; forward is -Z.
uniform vec3 emission_direction = vec3(0.0, 0.0, -1.0);
// Angle of the launch cone around the direction, in radians.
uniform float spread : hint_range(0.0, 3.14159) = 0.1;
uniform float initial_velocity = 1.5;
// Share of the launch speed picked at random.
uniform float velocity_random : hint_range(0.0, 1.0) = 0.1;
// Multiplies the launch velocity per world axis; (1, 0, 1) keeps particles
// on the ground.
uniform vec3 velocity_mask = vec3(1.0);

group_uniforms motion;
// World-space acceleration.
uniform vec3 grav = vec3(0.0, -9.8, 0.0);
// Share of the velocity lost per second.
uniform float vel_damping : hint_range(0.0, 10.0) = 0.0;
// Sideways push that sends each particle wandering its own way, in m/s².
uniform float turbulence : hint_range(0.0, 10.0) = 0.0;
// Particles die once this far below the emitter, in meters; never when negative.
uniform float kill_depth = -1.0;

group_uniforms look;
// Color at birth, and at the end of the life.
uniform vec4 color : source_color = vec4(1.0);
uniform vec4 color_end : source_color = vec4(1.0);
uniform float scale_initial = 0.05;
// Scale added (or removed) over the particle's life.
uniform float scale_add = 0.0;
// Share of the scale picked at random.
uniform float scale_random : hint_range(0.0, 1.0) = 0.3;
// Streak length per meter per second of speed; 0 keeps particles round.
uniform float stretch : hint_range(0.0, 0.5) = 0.0;
// Share of the life spent fading in, and fading out.
uniform float fade_in : hint_range(0.0, 1.0) = 0.05;
uniform float fade_out : hint_range(0.0, 1.0) = 0.3;

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float rand(inout uint seed) {
	seed = hash(seed);
	return float(seed % uint(65536)) / 65535.0;
}

// Any unit vector perpendicular to the unit vector n.
vec3 perpendicular(vec3 n) {
	vec3 ref = abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	return normalize(cross(ref, n));
}

float drop_below_emitter(vec3 pos, mat4 emitter) {
	return dot(emitter[3].xyz - pos, normalize(emitter[1].xyz));
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(rand(seed), 0.0, rand(seed), 0.0);
	}
	if (RESTART_POSITION) {
		vec3 r = vec3(rand(seed), rand(seed), rand(seed)) * 2.0 - 1.0;
		TRANSFORM = mat4(1.0);
		TRANSFORM[3] = EMISSION_TRANSFORM * vec4(r * emission_extents, 1.0);
	}
	if (RESTART_VELOCITY) {
		// Uniform over the cone's cap.
		vec3 axis = normalize(mat3(EMISSION_TRANSFORM) * emission_direction);
		vec3 side = perpendicular(axis);
		vec3 other = cross(axis, side);
		float cos_theta = mix(1.0, cos(spread), rand(seed));
		float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
		float phi = rand(seed) * TAU;
		vec3 dir = axis * cos_theta + (side * cos(phi) + other * sin(phi)) * sin_theta;
		VELOCITY = dir * velocity_mask * initial_velocity * (1.0 - velocity_random * rand(seed));
	}
	if (RESTART_COLOR) {
		COLOR = vec4(color.rgb, 0.0);
	}
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	float t = clamp(CUSTOM.y, 0.0, 1.0);
	float seed = CUSTOM.x * 100.0;

	VELOCITY += grav * DELTA;
	if (turbulence > 0.0) {
		vec3 pos = TRANSFORM[3].xyz;
		vec3 push = vec3(sin(pos.y * 3.1 + seed + TIME * 2.3), 0.0, cos(pos.y * 2.7 + seed * 1.7 + TIME * 1.9));
		VELOCITY += push * turbulence * DELTA;
	}
	VELOCITY *= max(1.0 - vel_damping * DELTA, 0.0);

	if (kill_depth >= 0.0 && drop_below_emitter(TRANSFORM[3].xyz, EMISSION_TRANSFORM) > kill_depth) {
		ACTIVE = false;
	}

	// Y along the motion, stretched by speed; X and Z across it.
	float speed = length(VELOCITY);
	vec3 along = speed > 0.0001 ? VELOCITY / speed : vec3(0.0, -1.0, 0.0);
	vec3 across = perpendicular(along);
	float scl = max(scale_initial + t * scale_add, 0.0) * (1.0 - scale_random * CUSTOM.z);
	float len = scl + speed * stretch;
	TRANSFORM[0].xyz = across * scl;
	TRANSFORM[1].xyz = along * len;
	TRANSFORM[2].xyz = cross(across, along) * scl;

	COLOR = mix(color, color_end, t);
	COLOR.a *= smoothstep(0.0, max(fade_in, 0.0001), t)
			* (1.0 - smoothstep(min(1.0 - fade_out, 0.9999), 1.0, t));
}
