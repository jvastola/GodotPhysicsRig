shader_type spatial;
render_mode unshaded;

uniform sampler2D noise1 : repeat_enable;
uniform sampler2D noise2 : repeat_enable;
uniform vec3 color1 : source_color = vec3(1.0, 0.0, 0.5);
uniform vec3 color2 : source_color = vec3(0.0, 0.5, 1.0);
uniform vec3 color3 : source_color = vec3(0.5, 1.0, 0.0);

uniform float warping_intensity : hint_range(0.0, 0.5) = 0.05;
uniform float warping_speed : hint_range(0.0, 5.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

const float SCROLL_SPEED = 0.04;

// Triplanar sampling helper
vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
	samp += texture(p_sampler, p_triplanar_pos.zy) * p_weights.x;
	return samp;
}

void vertex() {
	world_pos = VERTEX;
	world_normal = abs(NORMAL);
	world_normal /= (world_normal.x + world_normal.y + world_normal.z); // Normalize weights
	
	// Triplanar noise sampling for displacement
	vec3 tri_pos = VERTEX + TIME * SCROLL_SPEED * warping_speed;
	float noise_val = triplanar_texture(noise1, world_normal, tri_pos).r;
	float noise_val2 = triplanar_texture(noise2, world_normal, VERTEX * 2.0 - TIME * SCROLL_SPEED).r;
	
	float displacement = (noise_val + noise_val2 * 0.5) * warping_intensity;
	
	// DISPLACE along the vector from center to vertex to ensure seamless edges on a cube
	VERTEX += normalize(VERTEX) * displacement;
}

void fragment() {
	// Sample based on world_pos passed from vertex
	vec3 tri_pos = world_pos + TIME * SCROLL_SPEED;
	float noise_scale = 1.0;
	
	vec4 noise_sample = triplanar_texture(noise1, world_normal, tri_pos);
	float noise_value = noise_sample.r;
	
	vec3 distorted_tri_pos = world_pos * 4.0 - (triplanar_texture(noise1, world_normal, tri_pos * 0.3).xyz * 0.015) * TIME * 2.0;
	float noise2_value = triplanar_texture(noise2, world_normal, distorted_tri_pos).r;
	
	// Mix colors based on noise
	vec3 color = mix(color1, color2, noise_value);
	color = mix(color, color3, noise2_value * 0.3);
	
	ALBEDO = color;
	EMISSION = color * 1.5;
}
