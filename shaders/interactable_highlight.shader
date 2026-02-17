shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform float line_speed : hint_range(0.1, 2.0) = 0.7;
uniform vec4 glow_color : hint_color = vec4(0.8, 1.0, 1.0, 1.0);

void fragment() {
	// Use UV.y for horizontal scanning lines (from glow_lines concept)
	float lines = abs(sin(UV.y * 40.0 + TIME * line_speed));
	
	// Add rim/fresnel effect for edge glow
	float ndotv = dot(NORMAL, VIEW);
	float rim = pow(1.0 - abs(ndotv), 2.0);
	
	// Combine rim and lines for the glow effect
	float glow = mix(rim * 0.5, lines, 0.5);
	
	ALBEDO = glow_color.rgb;
	ALPHA = glow * glow_color.a;
}
