shader_type spatial;
render_mode blend_add,depth_draw_opaque,cull_back,unshaded;

uniform vec4 hologram_color : hint_color = vec4(0.0, 1.0, 0.5, 1.0);
uniform float scanline_speed : hint_range(0.0, 10.0) = 2.0;
uniform float scanline_density : hint_range(1.0, 50.0) = 20.0;
uniform float flicker_speed : hint_range(0.0, 20.0) = 5.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	float fresnel = pow(1.0 - max(dot(NORMAL, normalize(VIEW)), 0.0), 2.0);
	
	float scanline = sin(UV.y * scanline_density + TIME * scanline_speed);
	scanline = smoothstep(0.3, 1.0, scanline);
	
	float flicker = 0.9 + 0.1 * sin(TIME * flicker_speed);
	
	ALBEDO = hologram_color.rgb;
	ALPHA = alpha * fresnel * scanline * flicker;
}
