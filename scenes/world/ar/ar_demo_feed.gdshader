shader_type canvas_item;
// AR demo: makes the "real" site look like a passthrough camera feed, a little
// washed out and grainy, darker at the edges.

uniform float desaturation : hint_range(0.0, 1.0) = 0.35;
uniform float grain : hint_range(0.0, 0.2) = 0.04;
uniform float vignette : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec3 color = COLOR.rgb;
	color = mix(color, vec3(dot(color, vec3(0.299, 0.587, 0.114))), desaturation);
	float noise = fract(sin(dot(FRAGCOORD.xy + fract(TIME) * 97.0, vec2(12.9898, 78.233))) * 43758.5453);
	color += (noise - 0.5) * grain;
	vec2 from_center = UV - 0.5;
	color *= 1.0 - vignette * dot(from_center, from_center) * 2.0;
	COLOR = vec4(color, 1.0);
}
