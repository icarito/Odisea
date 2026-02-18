shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform vec4 outline_color : hint_color = vec4(0.8, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	// Simple fresnel/rim effect for outline
	float ndotv = dot(NORMAL, VIEW);
	float rim = pow(1.0 - abs(ndotv), rim_power);
	
	// Apply intensity
	float alpha = rim * rim_intensity;
	
	ALBEDO = outline_color.rgb;
	ALPHA = alpha * outline_color.a;
}
