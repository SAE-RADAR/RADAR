shader_type spatial;
// Water surface seen into and through: the scene below is refracted and tinted
// by how far light travels in the water, the scene around is reflected, and the
// shallows turn to foam. Seen from below, the surface shows Snell's window:
// clear straight up, a mirror past the critical angle.
//
// Refraction and reflection are screen-space, each Simple (one offset sample)
// or Traced (ray marched through the depth buffer, much heavier). Waves are two
// scrolling normal and height maps, sampled in world space so neighbouring
// volumes line up.
//
// Adapted from "Realistic Water with Traced and Simple Reflection and
// Refraction (V2)" by smallcableboi on godotshaders.com (CC0).
render_mode world_vertex_coords, cull_disabled, depth_draw_always, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

group_uniforms water;
// Share of light kept per meter travelled through the water, per channel.
uniform vec3 absorption_color : source_color = vec3(0.45, 0.78, 0.8);
// Multiplies the distance used for absorption; higher is murkier.
uniform float absorption_strength : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float air_ior = 1.0;
uniform float water_ior = 1.33;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.05;

group_uniforms waves;
// Texture repeats per meter.
uniform vec2 wave_scale = vec2(0.1);
// Scroll speeds of the two wave layers, in texture repeats per second.
uniform vec2 wave_a_speed = vec2(0.02, 0.0);
uniform vec2 wave_b_speed = vec2(0.0, 0.02);
uniform float wave_mix : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform sampler2D height_a : filter_linear_mipmap;
uniform sampler2D height_b : filter_linear_mipmap;
// Wave height in meters; the mesh must be subdivided for it to show.
uniform float height_strength : hint_range(0.0, 1.0, 0.005) = 0.05;

group_uniforms refraction;
uniform int refraction_mode : hint_enum("None", "Simple", "Traced") = 1;
uniform float refraction_amount : hint_range(0.0, 1.0, 0.01) = 0.1;
// How far a traced ray looks, in meters, and in how many steps.
uniform float traced_refraction_distance = 20.0;
uniform int traced_refraction_steps : hint_range(8, 512, 8) = 64;

group_uniforms reflection;
uniform int reflection_mode : hint_enum("None", "Simple", "Traced") = 1;
uniform float traced_reflection_distance = 20.0;
uniform int traced_reflection_steps : hint_range(8, 512, 8) = 64;
// Width of the screen border over which reflections fade out.
uniform float reflection_screen_fade : hint_range(0.01, 0.5, 0.01) = 0.05;

group_uniforms shore;
// Foam or transparency where the water is shallow.
uniform int shore_mode : hint_enum("Foam", "Fade", "None") = 0;
// Water depth below which the shore effect shows, in meters.
uniform float shore_depth : hint_range(0.01, 1.0, 0.01) = 0.1;
uniform vec3 foam_color : source_color = vec3(1.0);
uniform sampler2D foam_a : filter_linear_mipmap;
uniform sampler2D foam_b : filter_linear_mipmap;

// Keeps absorption finite where the depth buffer holds the sky.
const float MAX_WATER_DISTANCE = 1000.0;

varying vec3 world_position;


void vertex() {
	UV = VERTEX.xz * wave_scale + wave_a_speed * TIME;
	UV2 = VERTEX.xz * wave_scale + wave_b_speed * TIME;
	float height = mix(texture(height_a, UV).r, texture(height_b, UV2).r, wave_mix);
	VERTEX.y += (height - 0.5) * height_strength;
	world_position = VERTEX;
}


// View-space position of the opaque scene at a screen UV.
vec3 scene_position(vec2 uv, mat4 inv_projection) {
	float raw_depth = texture(depth_texture, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
#endif
	vec4 position = inv_projection * vec4(ndc, 1.0);
	return position.xyz / position.w;
}


vec2 view_to_uv(vec3 position, mat4 projection) {
	vec4 clip = projection * vec4(position, 1.0);
	return clip.xy / clip.w * 0.5 + 0.5;
}


bool on_screen(vec2 uv) {
	return all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)));
}


// 1 in the middle of the screen, falling to 0 at its edges.
float edge_fade(vec2 uv, float size) {
	vec2 fade = smoothstep(vec2(0.0), vec2(size), uv) * smoothstep(vec2(0.0), vec2(size), 1.0 - uv);
	return fade.x * fade.y;
}


// Share of light reflected at the surface, for a ray at cos_theta to the
// normal on the air side.
float fresnel(float cos_theta) {
	float f0 = (water_ior - air_ior) / (water_ior + air_ior);
	f0 *= f0;
	return f0 + (1.0 - f0) * pow(1.0 - clamp(cos_theta, 0.0, 1.0), 5.0);
}


// Marches a view-space ray until it passes behind the depth buffer. Steps grow
// quadratically: fine near the start, coarse far away. Returns the distance
// travelled to the hit, or -1 if the ray left the screen or hit nothing.
float trace(vec3 origin, vec3 direction, float max_distance, int steps, mat4 projection, mat4 inv_projection, out vec2 hit_uv) {
	hit_uv = vec2(0.0);
	float previous = 0.0;
	for (int i = 1; i <= steps; i++) {
		float t = float(i) / float(steps);
		float travelled = t * t * max_distance;
		vec3 position = origin + direction * travelled;
		if (position.z >= 0.0) {
			break;
		}
		vec2 uv = view_to_uv(position, projection);
		if (!on_screen(uv)) {
			break;
		}
		float behind = scene_position(uv, inv_projection).z - position.z;
		if (behind > 0.0) {
			// Far behind the scene means the ray went behind an occluder
			// rather than into it.
			if (behind <= travelled - previous + 0.05) {
				hit_uv = uv;
				return travelled;
			}
			break;
		}
		previous = travelled;
	}
	return -1.0;
}


// What is seen through the surface.
vec3 refracted_color(vec3 vertex, vec3 normal, vec3 flat_normal, vec2 screen_uv, vec2 viewport_size, bool from_below, mat4 projection, mat4 inv_projection) {
	vec3 scene = scene_position(screen_uv, inv_projection);
	float water_distance = distance(scene, vertex);
	vec2 uv = screen_uv;

	if (refraction_mode == 2) {
		vec3 view_ray = normalize(vertex);
		vec3 ray = from_below
				? refract(view_ray, normal, water_ior / air_ior)
				: refract(view_ray, normal, air_ior / water_ior);
		vec2 hit_uv;
		float travelled = trace(vertex, ray, traced_refraction_distance, traced_refraction_steps, projection, inv_projection, hit_uv);
		if (travelled >= 0.0) {
			uv = hit_uv;
			water_distance = travelled;
		}
	} else if (refraction_mode == 1) {
		vec2 offset = (normal - flat_normal).xy * refraction_amount;
		offset.x *= viewport_size.y / viewport_size.x;
		// Deeper water bends the view more.
		offset *= water_distance / max(-scene.z, 0.001);
		vec2 bent_uv = screen_uv + offset;
		vec3 bent_scene = scene_position(bent_uv, inv_projection);
		// Skip offsets landing on things in front of the water.
		if (on_screen(bent_uv) && bent_scene.z < vertex.z) {
			uv = bent_uv;
			water_distance = distance(bent_scene, vertex);
		}
	}

	vec3 color = texture(screen_texture, uv).rgb;
	if (!from_below) {
		water_distance = min(water_distance, MAX_WATER_DISTANCE);
		color *= pow(absorption_color, vec3(water_distance * absorption_strength));
	}
	return color;
}


// Screen-space reflection. [found] is how much of it was on screen, to blend
// with the engine's own sky and light reflections.
vec3 reflected_color(vec3 vertex, vec3 normal, mat4 projection, mat4 inv_projection, out float found) {
	found = 0.0;
	vec3 ray = reflect(normalize(vertex), normal);
	vec2 uv;
	if (reflection_mode == 2) {
		if (trace(vertex, ray, traced_reflection_distance, traced_reflection_steps, projection, inv_projection, uv) < 0.0) {
			return vec3(0.0);
		}
	} else if (reflection_mode == 1) {
		// Treat what is reflected as far away: project the direction alone.
		if (ray.z >= 0.0) {
			return vec3(0.0);
		}
		uv = view_to_uv(ray, projection);
		if (!on_screen(uv)) {
			return vec3(0.0);
		}
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		// Nothing drawn there but sky, which the engine reflects better.
		if (texture(depth_texture, uv).r <= 0.0) {
			return vec3(0.0);
		}
#endif
	} else {
		return vec3(0.0);
	}
	found = edge_fade(uv, reflection_screen_fade);
	return texture(screen_texture, uv).rgb;
}


void fragment() {
	vec3 flat_normal = NORMAL;
	// Back faces get a flipped normal but not flipped tangents.
	float side = FRONT_FACING ? 1.0 : -1.0;
	vec2 bump = mix(texture(normal_a, UV).xy, texture(normal_b, UV2).xy, wave_mix) - 0.5;
	NORMAL = normalize(NORMAL + side * (TANGENT * bump.x + BINORMAL * bump.y) * normal_strength);

	ALBEDO = vec3(0.0);
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	ALPHA = 1.0;
	float found;

	if (FRONT_FACING) {
		float reflectance = fresnel(dot(NORMAL, VIEW));
		EMISSION = refracted_color(VERTEX, NORMAL, flat_normal, SCREEN_UV, VIEWPORT_SIZE, false, PROJECTION_MATRIX, INV_PROJECTION_MATRIX) * (1.0 - reflectance);
		vec3 reflection = reflected_color(VERTEX, NORMAL, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, found);
		EMISSION += reflection * reflectance * found;
		// The engine's reflections fill in where the screen has nothing.
		SPECULAR = 0.5 * (1.0 - found);

		if (shore_mode != 2) {
			vec3 scene = scene_position(SCREEN_UV, INV_PROJECTION_MATRIX);
			float scene_height = (INV_VIEW_MATRIX * vec4(scene, 1.0)).y;
			float shallowness = clamp((world_position.y - scene_height) / shore_depth, 0.0, 1.0);
			if (shore_mode == 1) {
				ALPHA = shallowness;
			} else {
				float foam = mix(texture(foam_a, UV).r, texture(foam_b, UV2).r, wave_mix);
				if (foam > shallowness) {
					ALBEDO = foam_color;
					ROUGHNESS = 1.0;
					SPECULAR = 0.5;
					EMISSION = vec3(0.0);
					NORMAL = flat_normal;
				}
			}
		}
	} else {
		// From below, light out of the water bends away from the normal; past
		// the critical angle there is none and the surface is a mirror.
		vec3 transmitted = refract(normalize(VERTEX), NORMAL, water_ior / air_ior);
		float transmission = 0.0;
		if (dot(transmitted, transmitted) > 0.0) {
			transmission = 1.0 - fresnel(dot(transmitted, -NORMAL));
			EMISSION = refracted_color(VERTEX, NORMAL, flat_normal, SCREEN_UV, VIEWPORT_SIZE, true, PROJECTION_MATRIX, INV_PROJECTION_MATRIX) * transmission;
		}
		vec3 reflection = reflected_color(VERTEX, NORMAL, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, found);
		EMISSION += reflection * found * (1.0 - transmission);
		// The engine would reflect the sky, which can't be seen from below.
		SPECULAR = 0.0;
	}
}
