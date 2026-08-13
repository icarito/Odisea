shader_type spatial;

// Overlay ligero: deja visible el diamond aluminium de la placa base y pinta
// únicamente las franjas de seguridad. No emite luz ni crea un coste dinámico.
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled, unshaded;

uniform vec4 stripe_color : hint_color = vec4(1.0, 0.72, 0.06, 1.0);
uniform float stripe_count = 7.0;
uniform float stripe_width = 0.52;

void fragment() {
	float diagonal = fract((UV.x + UV.y) * stripe_count);
	float stripe = step(diagonal, stripe_width);
	ALBEDO = stripe_color.rgb;
	ALPHA = stripe * stripe_color.a;
}
