shader_type spatial;
render_mode cull_front, unshaded;

// GLES2 Compatible Inverted Hull Outline Shader
// This shader renders the back faces of the mesh, expanded along their normals,
// to create an outline effect around the original object.

// Color of the outline (and glow)
uniform vec4 highlight_color : hint_color = vec4(1.0, 0.0, 1.0, 1.0); // Default Magenta
uniform float outline_width : hint_range(0.0, 10.0) = 2.0;

// Emission / Glow Settings
uniform float emission_strength : hint_range(0.0, 10.0) = 1.0;

// Pulsating Effect Settings
uniform bool pulse_enabled = true;
uniform float pulse_speed : hint_range(0.1, 10.0) = 2.0;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.5;
uniform float pulse_max : hint_range(0.0, 2.0) = 1.5;

void vertex() {
	// Expand the vertices along their normals
	// The 0.01 factor scales the width to a reasonable range for the slider
	VERTEX += NORMAL * outline_width * 0.01;
}

void fragment() {
	vec3 base_color = highlight_color.rgb;
	float alpha = highlight_color.a;
	
	// Apply Pulsating Effect
	float pulse = 1.0;
	if (pulse_enabled) {
		// Create a smooth sine wave oscillating between pulse_min and pulse_max
		// (sin(TIME) is -1 to 1, map to 0 to 1 -> *0.5 + 0.5)
		float wave = sin(TIME * pulse_speed) * 0.5 + 0.5;
		pulse = mix(pulse_min, pulse_max, wave);
	}
	
	// Final Output
	// Multiply by emission_strength and pulse for intensity
    // Since we are unshaded, ALBEDO takes the raw color.
    // Values > 1.0 will trigger Glow if the Environment has it enabled.
	ALBEDO = base_color * emission_strength * pulse;
	ALPHA = alpha;
}
