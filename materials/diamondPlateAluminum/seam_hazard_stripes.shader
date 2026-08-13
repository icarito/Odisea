shader_type spatial;

// Overlay ligero de seguridad. Se ilumina con el lightmap como cualquier deck:
// no es un letrero autoemisivo ni crea un coste de iluminación dinámica.
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled;

uniform vec4 stripe_color : hint_color = vec4(1.0, 0.72, 0.06, 1.0);
uniform float stripe_count = 7.0;
uniform float stripe_width = 0.52;

void fragment() {
	// Bandas verticales en el espacio UV local de cada arista. Cada strip recibe
	// U a lo ancho de la unión, así que no se inclina al recorrer el anillo.
	float stripe_position = fract(UV.x * stripe_count);
	float stripe = step(stripe_position, stripe_width);
	ALBEDO = stripe_color.rgb;
	ALPHA = stripe * stripe_color.a;
}
