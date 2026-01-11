shader_type 3d;
render_mode unshaded, cull_disabled;

uniform vec3 tip_pos;
uniform float max_radius = 0.15;
uniform float min_size = 0.0;
uniform float max_size = 5.0; // Scale multiplier for 1mm base mesh

varying vec4 instance_color;
varying float v_proximity;

void vertex() {
	instance_color = INSTANCE_CUSTOM;
	
	// Get world position of the instance origin
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = distance(world_pos, tip_pos);
	
	// Calculate normalized proximity [0, 1]
	float t = clamp(1.0 - (dist / max_radius), 0.0, 1.0);
	v_proximity = t;
	
	// Quadratic-Cubic blend for a focused "pop"
	float s = mix(min_size, max_size, t * t * t);
	
	// Manual Bilboarding to ensure consistent behavior
	// Extract scale from MODEL_MATRIX if any, but we prefer to let 's' handle it
	vec3 base_pos = world_pos;
	vec3 view_pos = (VIEW_MATRIX * vec4(base_pos, 1.0)).xyz;
	
	// Billboard offset: VERTEX is local position (-1 to 1 in a 1mm mesh)
	// We apply the scale 's' here
	vec2 billboard_offset = VERTEX.xy * s;
	
	// Move the vertex in view space
	vec3 final_view_pos = view_pos + vec3(billboard_offset, 0.0);
	
	// Final transform to clip space
	POSITION = PROJECTION_MATRIX * vec4(final_view_pos, 1.0);
}

void fragment() {
	// Circular shape
	vec2 uv = UV * 2.0 - 1.0;
	if (dot(uv, uv) > 1.0) discard;
	
	ALBEDO = mix(instance_color.rgb, vec3(1.0), v_proximity * 0.4);
	ALPHA = instance_color.a;
}
