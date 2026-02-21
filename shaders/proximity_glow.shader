shader_type spatial;
render_mode unshaded, cull_back, blend_add;

uniform vec4 glow_color : hint_color = vec4(0.0, 1.0, 1.0, 0.4);
uniform float rim_power : hint_range(0.1, 8.0) = 2.0;
uniform float scan_speed : hint_range(0.0, 10.0) = 4.0;
uniform float scan_density : hint_range(10.0, 200.0) = 60.0;
uniform float scan_intensity : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// Fresnel/Rim effect
	float ndotv = dot(NORMAL, VIEW);
	float rim = pow(1.0 - clamp(abs(ndotv), 0.0, 1.0), rim_power);
	
	// Soft scanlines (sine wave instead of hard step)
	float scan = (sin(UV.y * scan_density + TIME * scan_speed) + 1.0) * 0.5;
	
	// Combine rim with soft scanlines
	float alpha = rim * glow_color.a * (1.0 + scan * scan_intensity);
	
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
