shader_type spatial;
// Transient water ripple drawn over the floor.
//
// The surface height is a sum of circular wave packets that follow the real
// capillary-gravity dispersion relation (w^2 = g*k + sigma/rho * k^3): long
// waves lead, short ones trail, and crests travel through each packet faster
// than the packet itself. The floor is seen through the water (refracted via
// the screen texture), with Schlick fresnel reflection, a specular glint,
// curvature-driven caustics and slight wet darkening. A flat surface renders
// exactly as the floor, so only the moving waves are visible.
//
// Organic ring wobble inspired by "Water Ripples" on godotshaders.com (CC0).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

// Seconds since the ripple spawned, and total lifetime, set per instance.
instance uniform float age = 0.0;
instance uniform float lifetime = 4.0;

group_uniforms waves;
// Multiplies physical time; 1.0 is real-world water speed.
uniform float time_scale : hint_range(0.1, 4.0) = 1.0;
// Overall wave height multiplier (base heights are in meters).
uniform float amplitude : hint_range(0.0, 4.0) = 1.0;
// Extra multiplier on surface slope for lighting and refraction.
uniform float slope_scale : hint_range(0.0, 4.0) = 1.0;
// How quickly the waves lose energy, per second.
uniform float damping : hint_range(0.0, 4.0) = 0.35;
// Radial wobble so rings are not perfect circles, in meters.
uniform float wobble : hint_range(0.0, 0.1) = 0.025;
uniform float wobble_scale : hint_range(0.5, 20.0) = 4.0;
// Radius where the effect has fully faded out (half the mesh size).
uniform float max_radius = 2.0;

group_uniforms look;
// Apparent water depth used to bend the floor seen through the waves, in meters.
uniform float refraction_depth : hint_range(0.0, 0.5) = 0.2;
// Fraction of fresnel reflection kept; water is 1.0.
uniform float reflectivity : hint_range(0.0, 1.0) = 1.0;
uniform vec3 reflection_horizon : source_color = vec3(0.62, 0.55, 0.45);
uniform vec3 reflection_zenith : source_color = vec3(0.22, 0.19, 0.16);
uniform vec3 light_direction = vec3(0.35, 1.0, 0.25);
uniform vec3 light_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float specular_power : hint_range(8.0, 2048.0) = 160.0;
uniform float specular_intensity : hint_range(0.0, 8.0) = 1.2;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.25;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.12;

group_uniforms rendering;
// Pulls the surface toward the camera so bumps in the scanned floor don't cut
// through it, while nearer objects (hands, pillars) still hide it. Meters.
uniform float depth_bias : hint_range(0.0, 0.3) = 0.08;

const float GRAVITY = 9.81;
// Surface tension over density for water, m^3/s^2.
const float SIGMA_RHO = 7.4e-5;

varying vec3 world_position;
varying vec2 local_position;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Circular wave packet of wavelength `lambda` at radius r and time t.
// Returns height in .x and envelope magnitude in .y.
vec2 packet(float r, float t, float lambda, float height, float width, float footprint) {
	float k = TAU / lambda;
	float omega = sqrt(GRAVITY * k + SIGMA_RHO * k * k * k);
	float group_speed = (GRAVITY + 3.0 * SIGMA_RHO * k * k) / (2.0 * omega);
	float front = group_speed * t;
	// Packets widen as they travel (dispersion within the band).
	float w = width + 0.3 * front;
	float d = (r - front) / w;
	float envelope = height * exp(-d * d);
	// Fade waves that are too fine for the pixel footprint to avoid VR shimmer.
	envelope *= 1.0 - smoothstep(0.3, 1.0, footprint * k / PI);
	return vec2(envelope * cos(k * r - omega * t), envelope);
}

// Surface height (x) and wave energy envelope (y) at radius r.
vec2 surface(float r, float t, float footprint) {
	vec2 s = packet(r, t, 0.70, 0.0120, 0.18, footprint);
	s += packet(r, t, 0.40, 0.0100, 0.12, footprint);
	s += packet(r, t, 0.23, 0.0070, 0.10, footprint);
	s += packet(r, t, 0.12, 0.0045, 0.08, footprint);
	s += packet(r, t, 0.06, 0.0020, 0.06, footprint);
	// Energy spreads over a growing circle: amplitude ~ 1/sqrt(r).
	s *= min(sqrt(0.3 / max(r, 0.02)), 2.0) * exp(-damping * t);
	// The initial impact: a central dip that rebounds and settles.
	float splash = exp(-(r * r) / (0.12 * 0.12)) * exp(-3.0 * t);
	s.x -= 0.012 * splash * cos(9.0 * t);
	s.y += 0.012 * splash;
	return s * amplitude;
}

void vertex() {
	local_position = VERTEX.xz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Slide along the view ray: same pixels on screen, just closer in depth.
	vec3 biased = world_position + normalize(CAMERA_POSITION_WORLD - world_position) * depth_bias;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(biased, 1.0)).xyz;
}

void fragment() {
	vec2 p = local_position;
	float r = length(p);
	vec2 dir = r > 1e-4 ? p / r : vec2(0.0);
	float t = age * time_scale;

	float footprint = fwidth(r);
	float rw = r + (value_noise(p * wobble_scale + t * 0.15) - 0.5) * wobble * smoothstep(0.0, 0.4, r);

	// Radial derivatives by central differences.
	const float STEP = 0.004;
	vec2 s0 = surface(max(rw - STEP, 0.0), t, footprint);
	vec2 s1 = surface(rw, t, footprint);
	vec2 s2 = surface(rw + STEP, t, footprint);
	float dh = (s2.x - s0.x) / (2.0 * STEP) * slope_scale;
	float d2h = (s2.x - 2.0 * s1.x + s0.x) / (STEP * STEP);
	float laplacian = d2h + dh / max(r, 0.02);

	vec3 up = normalize(mat3(MODEL_MATRIX) * vec3(0.0, 1.0, 0.0));
	vec3 n = normalize(mat3(MODEL_MATRIX) * vec3(-dh * dir.x, 1.0, -dh * dir.y));
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_position);
	float n_dot_v = clamp(dot(n, v), 0.0, 1.0);

	float fade = smoothstep(0.0, 0.05, age)
			* (1.0 - smoothstep(0.6 * lifetime, lifetime, age))
			* (1.0 - smoothstep(0.75 * max_radius, max_radius, r));
	// Water only exists where the waves carry energy.
	float mask = fade * smoothstep(0.0, 0.0008, s1.y);

	// Refraction: shift the floor lookup by the slope, projected to the screen.
	vec3 offset_view = (VIEW_MATRIX * vec4((n - up) * refraction_depth, 0.0)).xyz;
	vec4 clip_here = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip_there = PROJECTION_MATRIX * vec4(VERTEX + offset_view, 1.0);
	vec2 uv_here = clip_here.xy / clip_here.w * 0.5 + 0.5;
	vec2 uv_shift = (clip_there.xy / clip_there.w - clip_here.xy / clip_here.w) * 0.5;
	// Match SCREEN_UV's vertical orientation, whichever the backend uses.
	uv_shift.y *= abs(uv_here.y - SCREEN_UV.y) < abs(1.0 - uv_here.y - SCREEN_UV.y) ? 1.0 : -1.0;
	vec3 floor_color = texture(screen_texture, clamp(SCREEN_UV + uv_shift * mask, vec2(0.0), vec2(1.0))).rgb;

	// Crests (negative curvature) focus light onto the floor, troughs spread it.
	float caustic = clamp(-laplacian * caustic_strength * 0.01, -0.6, 1.0);
	floor_color *= 1.0 + caustic;
	floor_color *= 1.0 - wet_darkening * smoothstep(0.0, 0.006, s1.y);

	float fresnel = (0.02 + 0.98 * pow(1.0 - n_dot_v, 5.0)) * reflectivity;
	vec3 reflected = reflect(-v, n);
	vec3 environment = mix(reflection_horizon, reflection_zenith, smoothstep(0.0, 0.7, reflected.y));

	vec3 h = normalize(normalize(light_direction) + v);
	float specular = pow(max(dot(n, h), 0.0), specular_power) * specular_intensity;

	ALBEDO = mix(floor_color, environment, fresnel) + light_color * specular;
	ALPHA = mask;
}
