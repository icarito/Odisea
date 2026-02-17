shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform vec4 glow_color : hint_color = vec4(0.8, 1.0, 1.0, 1.0);
uniform float line_speed : hint_range(0.1, 2.0) = 0.7;
uniform float line_density : hint_range(10.0, 80.0) = 40.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;

void fragment() {
	// Fresnel/rim effect for edge glow
	float ndotv = dot(NORMAL, VIEW);
	float rim = pow(1.0 - abs(ndotv), rim_power);
	
	// Horizontal scanning lines (from glow_lines concept)
	float lines = abs(sin(UV.y * line_density + TIME * line_speed));
	
	// Combine effects
	float glow = mix(rim, lines, 0.3) * intensity;
	
	ALBEDO = glow_color.rgb;
	ALPHA = glow * glow_color.a;
}
