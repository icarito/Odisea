shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 color_active : hint_color = vec4(0.0, 1.0, 0.8, 1.0);
uniform vec4 color_inactive : hint_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float activation_level : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 3.0;
uniform float pulse_density = 5.0; // How many pulses along the cable

varying float v_progress; // Progress along the cable (0 to 1)

void vertex() {
	v_progress = UV.y;
}

void fragment() {
	// Base color mix
	vec3 albedo = mix(color_inactive.rgb, color_active.rgb, activation_level);

	// Pulse effect
	float t = TIME * pulse_speed - v_progress * pulse_density;
	float pulse = 0.5 + 0.5 * sin(t);

	// Sharpen pulse
	pulse = pow(pulse, 3.0);

	// Emission
	vec3 emission = albedo * (0.2 + 0.8 * pulse * activation_level);

	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = 0.5;
	ROUGHNESS = 0.5;
}
