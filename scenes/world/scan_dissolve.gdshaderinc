// Shared by the scan's shaders (scan_dissolve, and the scan_mask passes used
// in AR): the dissolve fronts HandDissolve opens in the scan.
//
// Each source is a sphere (xyz = origin, w = front radius) whose edge is
// roughened by noise. Inside the front the surface is cut away; around it a
// glowing rim burns. The rim is drawn as several ghost layers sampled deeper
// along the view ray, so the hole reads as a tunnel with depth rather than a
// flat cut-out.
//
// Layered-depth rings inspired by "Parallax Mapping" on godotshaders.com (CC0).

// Dissolve sources: xyz = origin, w = current front radius (<= 0 is inactive).
uniform vec4 sources[2];

group_uniforms edge;
uniform vec3 edge_color : source_color = vec3(0.25, 1.0, 0.65);
uniform float edge_energy : hint_range(0.0, 16.0) = 2.5;
// Width of the burning band on the solid side of the front, in meters.
uniform float edge_width : hint_range(0.0, 1.0) = 0.12;
// How ragged the front is.
uniform float noise_amount : hint_range(0.0, 2.0) = 0.35;
uniform float noise_scale : hint_range(0.1, 20.0) = 2.5;

group_uniforms depth_layers;
// Ghost rings sampled deeper into the surface; 0 disables the depth effect.
uniform int layers : hint_range(0, 16) = 6;
// Distance between layers along the view ray, in meters.
uniform float layer_depth : hint_range(0.0, 0.3) = 0.05;
// Thickness of each ring, in meters.
uniform float ring_width : hint_range(0.001, 0.2) = 0.02;
// Brightness kept from one layer to the next.
uniform float layer_fade : hint_range(0.0, 1.0) = 0.65;

group_uniforms;

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

// How far the front is pushed in or out at [p]: two octaves, slowly drifting,
// so the front flickers like it's burning.
float front_roughness(vec3 p, float time) {
	vec3 q = p * noise_scale + vec3(0.0, time * 0.15, 0.0);
	return (value_noise(q) * 0.7 + value_noise(q * 3.1) * 0.3 - 0.5) * noise_amount;
}

// Signed distance to the dissolve front: negative is dissolved.
float front(vec3 p, float roughness) {
	float f = 1e6;
	for (int i = 0; i < 2; i++) {
		if (sources[i].w > 0.0) {
			f = min(f, distance(p, sources[i].xyz) + roughness - sources[i].w);
		}
	}
	return f;
}

// Glow from rings where deeper layers along the view ray cross the front.
float depth_rings(vec3 p, vec3 into, float roughness) {
	float glow = 0.0;
	float weight = 1.0;
	for (int i = 1; i <= layers; i++) {
		weight *= layer_fade;
		float f = front(p + into * layer_depth * float(i), roughness);
		glow += weight * (1.0 - smoothstep(0.0, ring_width, abs(f)));
	}
	return glow;
}
