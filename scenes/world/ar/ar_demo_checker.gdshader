shader_type canvas_item;
// AR demo: checkerboard behind the AR layer alone, showing where it is
// transparent (where passthrough would show).

uniform float square_size = 24.0;
uniform vec3 light : source_color = vec3(0.42);
uniform vec3 dark : source_color = vec3(0.3);

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / square_size);
	COLOR = vec4(mod(cell.x + cell.y, 2.0) < 1.0 ? light : dark, 1.0);
}
