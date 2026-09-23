shader_type spatial;
// Scan surface that dissolves away from up to two points, with a glowing front.
//
// Each source is a sphere (xyz = origin, w = front radius) whose edge is
// roughened by noise. Inside the front the surface is cut away; around it a
// glowing rim burns. The rim is drawn as several ghost layers sampled deeper
// along the view ray, so the hole reads as a tunnel with depth rather than a
// flat cut-out. Lighting matches the scan's StandardMaterial3D.
//
// Layered-depth rings inspired by "Parallax Mapping" on godotshaders.com (CC0).
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
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

varying vec3 world_position;

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

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb;
	// Two octaves, slowly drifting, so the front flickers like it's burning.
	vec3 q = world_position * noise_scale + vec3(0.0, TIME * 0.15, 0.0);
	float roughness = (value_noise(q) * 0.7 + value_noise(q * 3.1) * 0.3 - 0.5) * noise_amount;
	float f = front(world_position, roughness);
	vec3 into = normalize(world_position - CAMERA_POSITION_WORLD);

	if (f < 0.0) {
		// Cut away, except where the tunnel's deeper rings show through.
		float glow = depth_rings(world_position, into, roughness);
		if (glow < 0.35) {
			discard;
		}
		ALBEDO = vec3(0.0);
		EMISSION = edge_color * edge_energy * glow;
	} else {
		float rim = 1.0 - smoothstep(0.0, edge_width, f);
		float glow = rim * rim;
		if (f < edge_width * 2.0) {
			glow += depth_rings(world_position, into, roughness) * 0.6;
		}
		// Surface chars just before it burns away.
		ALBEDO = albedo * (1.0 - 0.75 * rim);
		EMISSION = edge_color * edge_energy * glow;
	}
	ROUGHNESS = 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
