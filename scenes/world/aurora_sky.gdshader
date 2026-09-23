shader_type sky;
// Night sky with an animated aurora and a twinkling starfield.
//
// Aurora curtains are a ridged, domain-warped noise pattern projected onto a
// stack of horizontal layers along each view ray, which turns the pattern's
// thin lines into hanging sheets. Each sheet has a sharp lower edge that fades
// with altitude, and is colored like real emissions: a violet nitrogen fringe
// at the bottom, oxygen green (557.7 nm) in the body, oxygen red (630 nm) on top.
//
// Inspired by "Aurora Sky Shader" on godotshaders.com (CC0).
render_mode use_debanding;

group_uniforms sky;
uniform vec3 zenith_color : source_color = vec3(0.004, 0.007, 0.022);
uniform vec3 horizon_color : source_color = vec3(0.018, 0.03, 0.06);
uniform vec3 ground_color : source_color = vec3(0.004, 0.005, 0.008);

group_uniforms aurora;
uniform vec3 color_bottom : source_color = vec3(0.6, 0.25, 0.9);
uniform vec3 color_main : source_color = vec3(0.12, 1.0, 0.42);
uniform vec3 color_top : source_color = vec3(0.75, 0.1, 0.35);
uniform float brightness : hint_range(0.0, 8.0) = 1.3;
// Drift speed of the curtains.
uniform float speed : hint_range(0.0, 1.0) = 0.06;
// Size of the curtain folds; larger means more, smaller folds.
uniform float scale : hint_range(0.05, 8.0) = 2.2;
// Height of the lower edge and vertical extent of the curtains (arbitrary units).
uniform float altitude : hint_range(0.1, 4.0) = 1.0;
uniform float thickness : hint_range(0.1, 4.0) = 1.0;
// How thin the curtain sheets are.
uniform float sharpness : hint_range(1.0, 32.0) = 12.0;
// Width of the aurora band across the sky.
uniform float coverage : hint_range(0.05, 1.5) = 0.5;
// Where the band crosses the sky: -1 south horizon, 0 overhead, 1 north horizon.
uniform float band_position : hint_range(-1.0, 1.0) = 0.25;

group_uniforms stars;
uniform float star_density : hint_range(0.0, 1.0) = 0.22;
uniform float star_brightness : hint_range(0.0, 8.0) = 2.0;
uniform float star_twinkle : hint_range(0.0, 1.0) = 0.5;
uniform float star_scale : hint_range(20.0, 600.0) = 160.0;

// Curtain samples per ray; lower is cheaper, higher is smoother.
const int LAYERS = 48;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	const mat2 ROTATE = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.5 * value_noise(p);
	v += 0.25 * value_noise(ROTATE * p * 2.03);
	v += 0.125 * value_noise(ROTATE * ROTATE * p * 4.01);
	return v / 0.875;
}

vec3 sky_gradient(vec3 dir) {
	vec3 sky = mix(horizon_color, zenith_color, sqrt(max(dir.y, 0.0)));
	return mix(ground_color, sky, smoothstep(-0.04, 0.02, dir.y));
}

vec3 aurora(vec3 dir, float t) {
	// Band of activity across the sky, gently meandering.
	float band_offset = dir.z - band_position + 0.18 * sin(dir.x * 2.7 + t * 0.4);
	float band = exp(-band_offset * band_offset / (coverage * coverage));
	// Atmospheric extinction near the horizon.
	float horizon = smoothstep(0.06, 0.4, dir.y);
	if (band * horizon < 0.002) {
		return vec3(0.0);
	}

	vec2 plane = dir.xz / (dir.y + 0.05) * scale;
	// Slow large-scale folding, shared by every layer so sheets stay coherent.
	vec2 warp = vec2(fbm(plane * altitude * 0.18 + t * 0.35),
			fbm(plane * altitude * 0.18 + vec2(5.2, 1.3) - t * 0.3)) - 0.5;
	// Distant curtains look diffuse; softer ridges there also avoid aliasing.
	float edge = mix(5.0, sharpness, smoothstep(0.1, 0.55, dir.y));

	// Vertical rays: a vertical line keeps the same azimuth at every height,
	// so streaks vary with azimuth and converge overhead into a corona.
	float azimuth = atan(dir.x, dir.z);
	float rays = 0.3 + 0.7 * pow(value_noise(vec2(azimuth * 70.0 - t * 1.5, length(plane) * 0.25)), 1.5);

	vec3 glow = vec3(0.0);
	for (int i = 0; i < LAYERS; i++) {
		float f = (float(i) + 0.5) / float(LAYERS);
		vec2 q = plane * (altitude + f * thickness) + warp * 2.2;
		// Curtains run mostly east-west: stretch the pattern along x.
		float ridge = 1.0 - abs(2.0 * value_noise(vec2(q.x * 0.3, q.y * 1.6) + vec2(t * 0.2, 0.0)) - 1.0);
		float sheet = pow(ridge, edge);
		// Sharp lower edge, exponential fade with altitude.
		float profile = smoothstep(0.0, 0.06, f) * exp(-3.2 * f);
		vec3 color = f < 0.1
				? mix(color_bottom, color_main, f / 0.1)
				: mix(color_main, color_top * 0.6, smoothstep(0.45, 1.0, f));
		glow += color * sheet * profile;
	}
	glow *= rays * brightness * band * horizon * (6.0 / float(LAYERS));
	// Soft highlight rolloff keeps bright folds from flattening into blobs.
	return 1.0 - exp(-glow);
}

vec3 stars(vec3 dir, float dimming) {
	vec3 p = dir * star_scale;
	vec3 cell = floor(p);
	vec3 r = hash33(cell);
	if (r.x > star_density) {
		return vec3(0.0);
	}
	vec3 center = 0.2 + 0.6 * hash33(cell + 17.0);
	float d = length(fract(p) - center);
	// Most stars are faint, a few are bright.
	float magnitude = pow(r.y, 5.0) * 0.9 + 0.1;
	float twinkle = 1.0 - star_twinkle * (0.5 + 0.5 * sin(TIME * (1.5 + 4.0 * r.z) + r.x * 60.0));
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.88, 0.72), r.z);
	float point = smoothstep(0.14, 0.0, d);
	return tint * point * magnitude * twinkle * star_brightness
			* smoothstep(0.0, 0.15, dir.y) * dimming;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 color = sky_gradient(dir);

	// Keep the reflection/ambient cubemap cheap: it would otherwise re-render
	// the full aurora into six faces every frame.
	if (AT_CUBEMAP_PASS) {
		COLOR = color;
	} else {
		float t = TIME * speed;
		vec3 light = aurora(dir, t);
		// Faint airglow and aurora light scattered near the horizon.
		color += color_main * 0.012 * exp(-abs(dir.y) * 14.0) * smoothstep(-0.02, 0.01, dir.y);
		float dimming = 1.0 - clamp(dot(light, vec3(0.3, 0.6, 0.1)) * 3.0, 0.0, 0.85);
		COLOR = color + light + stars(dir, dimming);
	}
}
