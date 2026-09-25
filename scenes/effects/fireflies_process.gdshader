shader_type particles;
// Fireflies drifting through a box, gathering around hands that grab them and
// scattering when released.
//
// Every particle steers its velocity toward a target with an exponential
// response, so the swarm stays stable however the hands move: a slow noise
// flow while wandering, an orbit on a shell around a grabbing hand, and a
// radial dash away from a hand that just let go.
//
// CUSTOM.x = per-particle random seed, CUSTOM.y = life phase (0 to 1),
// CUSTOM.z = how gathered the particle is (0 to 1), read by the draw shader.

group_uniforms volume;
// World-space box the fireflies spawn in and drift back to.
uniform vec3 volume_center = vec3(0.0, 1.5, 0.0);
uniform vec3 volume_extents = vec3(5.0, 1.2, 5.5);
uniform float scale_min : hint_range(0.1, 4.0) = 0.6;
uniform float scale_max : hint_range(0.1, 4.0) = 1.2;

group_uniforms wander;
uniform float wander_speed : hint_range(0.0, 2.0) = 0.25;
// Size of the drift currents; larger means tighter, twistier paths.
uniform float wander_scale : hint_range(0.05, 4.0) = 0.6;
// How quickly a firefly settles back into the drift, per second.
uniform float wander_response : hint_range(0.1, 10.0) = 0.8;

group_uniforms swarm;
// Hands: xyz = world position, w = grab strength (0 to 1). Set by script.
uniform vec4 hands[2];
// Distance from which a grabbing hand pulls fireflies in, in meters.
uniform float attract_radius : hint_range(0.1, 10.0) = 3.0;
// Radius of the swarm around the hand, in meters.
uniform float swarm_radius : hint_range(0.02, 1.0) = 0.18;
uniform float gather_speed : hint_range(0.0, 10.0) = 3.0;
uniform float max_gather_speed : hint_range(0.0, 10.0) = 2.5;
uniform float swirl_speed : hint_range(0.0, 5.0) = 0.9;
uniform float swarm_response : hint_range(0.1, 20.0) = 4.0;

group_uniforms burst;
// Bursts: xyz = world position of the release, w = strength (0 to 1). Set by script.
uniform vec4 bursts[2];
uniform float burst_radius : hint_range(0.05, 3.0) = 0.8;
uniform float burst_speed : hint_range(0.0, 10.0) = 3.0;
uniform float burst_response : hint_range(0.1, 40.0) = 20.0;

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

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x),
				mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
				mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y),
			u.z);
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	if (RESTART_ROT_SCALE) {
		float s = mix(scale_min, scale_max, rand(seed));
		TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
	if (RESTART_POSITION) {
		vec3 r = vec3(rand(seed), rand(seed), rand(seed)) * 2.0 - 1.0;
		TRANSFORM[3].xyz = volume_center + r * volume_extents;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0);
	}
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(rand(seed), 0.0, 0.0, 0.0);
	}
}

void process() {
	CUSTOM.y += DELTA / LIFETIME;
	vec3 pos = TRANSFORM[3].xyz;
	float seed = CUSTOM.x;

	// Drift along slowly changing noise currents, mostly horizontal.
	vec3 q = pos * wander_scale + vec3(seed * 17.0, TIME * 0.07, -TIME * 0.05);
	vec3 target = vec3(value_noise(q), value_noise(q + vec3(31.4, 0.0, 0.0)),
			value_noise(q + vec3(0.0, 47.2, 0.0))) * 2.0 - 1.0;
	target *= wander_speed * vec3(1.0, 0.5, 1.0);
	// Ease strays back into the volume.
	target -= (pos - clamp(pos, volume_center - volume_extents, volume_center + volume_extents)) * 0.8;
	float response = wander_response;
	float gathered = 0.0;

	for (int i = 0; i < 2; i++) {
		vec3 to = hands[i].xyz - pos;
		float d = length(to);
		vec3 dir = to / max(d, 0.001);
		float pull = hands[i].w * (1.0 - smoothstep(attract_radius * 0.6, attract_radius, d));
		if (pull > 0.0) {
			// Each firefly keeps its own orbit radius and tilt, so the swarm is a ball.
			float shell = swarm_radius * (0.35 + 0.65 * fract(seed * 7.13));
			vec3 axis = normalize(vec3(fract(seed * 3.1) - 0.5, 1.0, fract(seed * 5.7) - 0.5));
			vec3 tangent = cross(axis, dir);
			tangent /= max(length(tangent), 0.001);
			vec3 orbit = dir * clamp((d - shell) * gather_speed, -max_gather_speed, max_gather_speed)
					+ tangent * swirl_speed;
			target = mix(target, orbit, pull);
			response = mix(response, swarm_response, pull);
			gathered = max(gathered, pull * (1.0 - smoothstep(shell, shell + 0.4, d)));
		}

		vec3 away = pos - bursts[i].xyz;
		float db = length(away);
		if (bursts[i].w > 0.0 && db < burst_radius) {
			target = away / max(db, 0.001) * burst_speed * (0.6 + 0.4 * fract(seed * 11.3));
			response = burst_response * bursts[i].w;
		}
	}

	VELOCITY = mix(VELOCITY, target, 1.0 - exp(-response * DELTA));
	CUSTOM.z = mix(CUSTOM.z, gathered, 1.0 - exp(-4.0 * DELTA));
}
