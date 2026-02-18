shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled;

// Border Highlight Shader for Window Resizing
// Inspired by Horizon OS 2.1 resize handles

uniform vec4 border_color : source_color = vec4(0.4, 0.6, 1.0, 0.3);
uniform vec4 corner_highlight_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);

uniform float border_width = 0.02;      // Width of the border line (UV space, approx)
uniform float corner_radius = 0.05;     // Radius of the rounded corners
uniform float corner_arc_length = 0.15; // Length of the thicker corner anchors
uniform float aspect_ratio = 1.6;       // Width / Height to correct UV distortion

uniform int active_corner = -1;         // 0=TL, 1=TR, 2=BR, 3=BL, -1=None
uniform float hover_amount = 0.0;       // 0.0 to 1.0, controls overall visibility
uniform float resize_progress = 0.0;    // 0.0 to 1.0, pulsing effect during resize

varying vec2 v_uv;

// Signed Distance Field for a rounded box
float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    vec2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

void vertex() {
    v_uv = UV;
}

void fragment() {
    // 1. Correct UVs for aspect ratio to get uniform border width
    vec2 uv = v_uv;
    vec2 pos = (uv - 0.5) * vec2(aspect_ratio, 1.0) * 2.0; // Map to -aspect..aspect, -1..1
    
    // Panel dimensions in this space
    vec2 half_size = vec2(aspect_ratio, 1.0) - vec2(border_width * 2.0); 
    
    // 2. Calculate Distance Field for the Border
    // We want a border that sits exactly on the edge of the quad
    // The quad itself is the canvas.
    
    // External box (outer edge of border)
    // We use a slightly smaller box than the full quad to avoid texture clamping artifacts at edges
    vec2 box_size = vec2(aspect_ratio, 1.0) - vec2(border_width);
    
    // Distance from the rounded edge
    // r = vector of corner radii. All same here.
    float dist = sdRoundedBox(pos, box_size, vec4(corner_radius));
    
    // Visual width of the border logic
    // dist <= 0 means inside the box. dist > 0 is outside.
    // We want a stroke AROUND the edge.
    // Actually, distinct approach:
    // 1. mask = 1.0 if abs(dist) < border_width/2
    
    // Let's rely on a simple approach: brightness increases as we get closer to the edge line
    // The "edge line" is at dist = 0.
    float border_mask = 1.0 - smoothstep(0.0, border_width, abs(dist));
    
    // discard inner content to keep it transparent
    if (dist < -border_width) {
       discard; // optimization
    }
    
    // 3. Corner Detection
    // Determine which corner we are nearest to
    // UV space: TL=(0,0), TR=(1,0), BR=(1,1), BL=(0,1)
    // But we are in centered pos space: TL=(-aspect, -1), TR=(aspect, -1), ...
    // Note: Godot UV (0,0) is Top-Left usually.
    // Let's stick to UV for sector checking to be safe.
    
    int corner_index = -1;
    if (uv.x < 0.5 && uv.y < 0.5) corner_index = 0; // TL
    else if (uv.x >= 0.5 && uv.y < 0.5) corner_index = 1; // TR
    else if (uv.x >= 0.5 && uv.y >= 0.5) corner_index = 2; // BR
    else if (uv.x < 0.5 && uv.y >= 0.5) corner_index = 3; // BL
    
    // Calculate distance from the actual corner point (for arc length limiting)
    // We want the highlight to extend 'corner_arc_length' along the perimeter
    // Doing this exactly with SDF is tricky, but we can approximate by distance from corner
    vec2 corner_pos = vec2(0.0);
    if (corner_index == 0) corner_pos = vec2(-aspect_ratio, -1.0) + border_width;
    if (corner_index == 1) corner_pos = vec2(aspect_ratio, -1.0) + border_width;
    if (corner_index == 2) corner_pos = vec2(aspect_ratio, 1.0) - border_width;
    if (corner_index == 3) corner_pos = vec2(-aspect_ratio, 1.0) - border_width;
    
    // Distance from the corner point along the edge
    // Simple Euclidean distance is okay for the gradient falloff
    float dist_from_corner = length(max(abs(pos) - (vec2(aspect_ratio, 1.0) - vec2(corner_arc_length)), 0.0));
    // Actually, simpler: check if we are within 'corner_arc_length' of the corner in EITHER x or y
    // boolean in_corner_zone = (abs(pos.x) > aspect_ratio - corner_arc_length) || (abs(pos.y) > 1.0 - corner_arc_length);
    
    // Let's produce a "corner strength" value
    // It should be 1.0 at the corner, falling off to 0.0 at arc_length
    // This is a bit complex to get perfectly "L" shaped with rounded corners but let's approximate
    // A radial gradients from corners works well enough for the "glow"
    vec2 corner_uv_center = vec2(0.0);
    if (corner_index == 0) corner_uv_center = vec2(0.0, 0.0);
    if (corner_index == 1) corner_uv_center = vec2(1.0, 0.0);
    if (corner_index == 2) corner_uv_center = vec2(1.0, 1.0);
    if (corner_index == 3) corner_uv_center = vec2(0.0, 1.0);
    
    // Normalized distance in UV space (corrected for aspect)
    vec2 vec_to_corner = (uv - corner_uv_center) * vec2(aspect_ratio, 1.0);
    float dist_to_corner = length(vec_to_corner);
    
    float corner_intensity = 1.0 - smoothstep(corner_arc_length * 0.5, corner_arc_length, dist_to_corner);
    
    // 4. Combine Colors
    vec4 final_color = border_color;
    
    // Start with base border
    float alpha = border_mask * border_color.a;
    
    // Apply Highlight to Active/Hovered Corner
    bool is_active_corner = (corner_index == active_corner);
    
    if (is_active_corner) {
        // Boost alpha and color for the highlighted corner
        final_color = mix(final_color, corner_highlight_color, 0.8);
        alpha += corner_intensity * 0.6; // Make corner glow
        
        // Add pulse if resizing
        if (resize_progress > 0.0) {
             alpha += sin(TIME * 10.0) * 0.2 * resize_progress;
        }
    }
    
    // Overall fade
    alpha *= hover_amount;
    
    ALBEDO = final_color.rgb;
    ALPHA = clamp(alpha, 0.0, 1.0);
}
