shader_type spatial;
render_mode unshaded;

uniform float value : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color_empty = vec3(0.2, 0.2, 0.2);
uniform vec3 color_full = vec3(0.0, 1.0, 0.0);

void fragment() {
	// Simple vertical bar implementation
	// UV.y goes from 0 to 1
	float mask = step(1.0 - value, 1.0 - UV.y);
	ALBEDO = mix(color_empty, color_full, mask);
}
