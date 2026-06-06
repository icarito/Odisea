shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 highlight_color : hint_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float pulse_speed : hint_range(0.5, 6.0) = 3.0;

void fragment() {
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	ALBEDO = highlight_color.rgb * (0.3 + pulse * 0.4);
	ALPHA = highlight_color.a * (0.15 + pulse * 0.2);
}
