shader_type spatial;
render_mode blend_add,depth_draw_opaque,cull_back,unshaded;

uniform vec4 glow_color : hint_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float intensity : hint_range(0.1, 10.0) = 3.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	float fresnel = pow(0.2 + max(dot(NORMAL, normalize(VIEW)), 0.0), 2.5);
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	
	float center_glow = 1.0 - fresnel;
	vec3 center_color = glow_color.rgb * 1.5;
	vec3 edge_color = glow_color.rgb * intensity * pulse;
	
	ALBEDO = mix(center_color, edge_color, fresnel);
	ALPHA = 0.9 * center_glow + fresnel;
}
