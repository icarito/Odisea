shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, ambient_light_disabled;

// FD-051: reemplazo del plano rojo plano de debug. La idea es que este plano pueda quedar
// SIEMPRE visible (no solo para calibrar) sin desentonar: en vez de un disco sólido, un
// ruido animado sutil que lee como "membrana de calor" sobre la línea real de fire_height.
// Sigue siendo puramente cosmético — la Y del plano es la única verdad, esto solo decora
// cómo se ve esa Y.

uniform vec4 base_color : hint_color = vec4(1.0, 0.15, 0.05, 0.35);
uniform float noise_scale = 0.35;
uniform float noise_speed = 0.35;
uniform float alpha_min = 0.08;
uniform float alpha_max = 0.55;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 p = UV * (1.0 / max(noise_scale, 0.001));
	vec2 drift = vec2(TIME * noise_speed, TIME * noise_speed * 0.6);

	// Una sola octava: estos planos cubren 60x60 m y suelen ocupar toda la
	// pantalla, asi que el fragment corre sobre muchisimos pixeles. La segunda
	// octava costaba otros 4 hash() por pixel y a esta escala casi no se nota.
	float n = value_noise(p + drift);

	ALBEDO = base_color.rgb;
	EMISSION = base_color.rgb * (0.4 + n * 0.6);
	ALPHA = base_color.a * mix(alpha_min, alpha_max, n);
}
