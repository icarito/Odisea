shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

// Simple Holographic Scanline Overlay
// Renders transparent bands scrolling over the object surface

uniform vec4 highlight_color : hint_color = vec4(1.0, 0.4, 0.0, 1.0); // Orange default
uniform float pulse_speed : hint_range(0.0, 20.0) = 4.0;
uniform float scanline_count : hint_range(0.0, 200.0) = 150.0; // Increased count for finer lines
uniform float opacity : hint_range(0.0, 1.0) = 0.5; // Slightly more visible

void vertex() {
	// Slight expansion to avoid Z-fighting with the original mesh
	VERTEX += NORMAL * 0.005;
}

float random(vec2 uv) {
    return fract(sin(dot(uv.xy,
        vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
	// Simple scrolling stripes along UV.y
	// Increased speed feeling by using time with a larger factor or noise.
	
	// Create a more erratic pulse
	float erratic_time = TIME * pulse_speed + sin(TIME * 10.0) * 0.2;
	
	float scanline = sin(UV.y * scanline_count - erratic_time);
	
	// Sharpens the lines significantly to make them "smaller" / thinner
	// Adjusting smoothstep range: closer values = sharper, harder edge.
	scanline = smoothstep(0.8, 0.9, scanline);
	
	// Pulsating alpha with noise for erratic feel
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float noise = random(vec2(TIME * 0.1, 0.0));
	float glitch = step(0.9, noise) * 0.3; // Occasional brightness spike
	
	float final_alpha = opacity * scanline * (0.5 + 0.5 * pulse) + glitch;
	
	ALBEDO = highlight_color.rgb;
	ALPHA = highlight_color.a * final_alpha;
}
