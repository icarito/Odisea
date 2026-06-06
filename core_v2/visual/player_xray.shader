shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disable, cull_disabled, unshaded;

uniform vec4 xray_color : hint_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float pulse_speed : hint_range(0.5, 6.0) = 2.5;
uniform float alpha_base : hint_range(0.0, 1.0) = 0.25;
uniform float alpha_pulse : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	// Rim glow — brightest at silhouette edge
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float alpha = (alpha_base + pulse * alpha_pulse) * mix(0.4, 1.0, rim);
	ALBEDO = xray_color.rgb;
	ALPHA = alpha * xray_color.a;
}
