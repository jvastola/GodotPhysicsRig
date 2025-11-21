shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// Player tracking
uniform vec3 player_position = vec3(0.0, 0.0, 0.0);

// Zone distances
uniform float zone1_distance = 5.0;  // Lines match terrain
uniform float zone2_distance = 7.0;  // Lines transition to 1m above
uniform float line_height_offset = 1.0;  // Height above terrain in zone 2

// Line appearance
uniform vec4 line_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform float line_width = 0.02;

varying float vertex_distance;
varying float vertex_alpha;

void vertex() {
	// Calculate distance from vertex to player (XZ plane only)
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 player_xz = vec2(player_position.x, player_position.z);
	vec2 vertex_xz = vec2(world_pos.x, world_pos.z);
	vertex_distance = distance(vertex_xz, player_xz);
	
	// Store original terrain height
	float terrain_height = world_pos.y;
	
	// Calculate target height based on distance zones
	float target_height = terrain_height;
	vertex_alpha = 1.0;
	
	if (vertex_distance < zone1_distance) {
		// Zone 1: Lines follow terrain
		target_height = terrain_height;
		vertex_alpha = 1.0;
	} else if (vertex_distance < zone2_distance) {
		// Zone 2: Transition from terrain to 1m above
		float transition = (vertex_distance - zone1_distance) / (zone2_distance - zone1_distance);
		target_height = mix(terrain_height, terrain_height + line_height_offset, transition);
		vertex_alpha = 1.0 - transition;  // Fade out during transition
	} else {
		// Zone 3: Invisible
		target_height = terrain_height + line_height_offset;
		vertex_alpha = 0.0;
	}
	
	// Apply the calculated height
	vec3 adjusted_pos = world_pos;
	adjusted_pos.y = target_height;
	
	// Transform back to local space
	VERTEX = (inverse(MODEL_MATRIX) * vec4(adjusted_pos, 1.0)).xyz;
}

void fragment() {
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * vertex_alpha;
}
