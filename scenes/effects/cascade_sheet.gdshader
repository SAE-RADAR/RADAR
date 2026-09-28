shader_type spatial;
// Sheet of water pouring over the lip, drawn on the ribbon mesh cascade.gd
// builds along the path the water follows. UV.x runs across the lip, UV.y
// along the fall, in equal steps of time (0 at the lip, 1 at the landing).
//
// Textures are sampled by where the water is across the lip and when it left
// it, so every ripple falls with the water and stretches as it speeds up. The
// sheet leaves the lip clear and glassy, then takes in air: it whitens, frays
// at the edges and tears into streaks, which the particles take over from.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap;

// Set by cascade.gd.
instance uniform float sheet_width = 1.5;
instance uniform float fall_time = 0.78;
instance uniform vec4 water_color : source_color = vec4(0.6, 0.78, 0.8, 0.35);
instance uniform vec4 foam_color : source_color = vec4(0.93, 0.96, 1.0, 0.85);

group_uniforms textures;
// Smooth noise, stretched down the sheet into streaks.
uniform sampler2D streak_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms air;
// Share of the fall after which the water is fully white.
uniform float aeration_length : hint_range(0.05, 1.0) = 0.6;
// Share of the fall after which the sheet has torn as far as it goes.
uniform float breakup : hint_range(0.1, 1.0) = 0.95;
// How much of the sheet tears away by then.
uniform float tear_amount : hint_range(0.0, 1.0) = 0.4;
// How far the edges fray in by the bottom, in meters.
uniform float edge_fray : hint_range(0.0, 1.0) = 0.25;

group_uniforms surface;
// Texture repeats per meter across, and per second of flow down.
uniform vec2 streak_scale = vec2(0.45, 0.3);
uniform vec2 ripple_scale = vec2(0.8, 0.6);
uniform float normal_strength : hint_range(0.0, 4.0) = 1.2;
// How far the sheet sways at the bottom, in meters.
uniform float wobble : hint_range(0.0, 0.3) = 0.04;
// Share of the light from behind that passes through the white water.
uniform float translucency : hint_range(0.0, 1.0) = 0.5;

varying float fall;

// Across the lip in meters, and when the water here left the lip in seconds.
vec2 flow_coords(vec2 uv) {
	return vec2((uv.x - 0.5) * sheet_width, uv.y * fall_time - TIME);
}

void vertex() {
	fall = UV.y;
	vec2 flow = flow_coords(UV);
	float sway = textureLod(streak_noise, flow * vec2(0.3, 0.25), 0.0).r - 0.5;
	VERTEX += NORMAL * sway * 2.0 * wobble * fall;
}

void fragment() {
	vec2 flow = flow_coords(UV);
	float big = texture(streak_noise, flow * streak_scale).r;
	float fine = texture(streak_noise, flow * streak_scale * vec2(4.2, 3.7) + vec2(0.37, 0.61)).r;
	float streaks = big * 0.6 + fine * 0.4;

	// Air taken in: clear at the lip, white further down, first in streaks.
	float aeration = clamp(smoothstep(0.0, aeration_length, fall) * (0.5 + streaks), 0.0, 1.0);
	// Holes open between the streaks.
	float tear = smoothstep(0.3, breakup, fall) * tear_amount;
	float body = smoothstep(tear - 0.15, tear + 0.15, streaks);
	// Frayed edges, more so lower down.
	float edge = min(UV.x, 1.0 - UV.x) * sheet_width;
	float fray = 0.01 + fall * edge_fray * (0.3 + fine);
	float edges = smoothstep(0.0, 1.0, edge / fray);
	// The particles and spray take over at the bottom.
	float end = 1.0 - smoothstep(0.8, 1.0, fall);
	float lip = smoothstep(0.0, 0.02, fall);

	ALBEDO = mix(water_color.rgb, foam_color.rgb, aeration);
	ALPHA = mix(water_color.a, foam_color.a, aeration) * body * edges * end * lip;
	ROUGHNESS = mix(0.05, 0.5, aeration);
	SPECULAR = 0.5;
	NORMAL_MAP = texture(ripple_normal, flow * ripple_scale).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - 0.5 * aeration);
	BACKLIGHT = foam_color.rgb * translucency * aeration;
}
