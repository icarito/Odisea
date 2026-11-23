shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// FD-324 — sombra falsa radial del Ark-Run. Disco oscuro con aro cian fino para
// que se lea nítidamente sobre pisos oscuros. La opacidad global la baja el
// controlador con la altura a la que cae la sombra.

uniform vec4 core_color : hint_color = vec4(0.01, 0.02, 0.04, 0.58);
uniform vec4 ring_color : hint_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform float ring_radius = 0.82;
uniform float ring_width = 0.06;
uniform float opacity = 1.0;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float r = length(centered);
	float body = smoothstep(1.0, 0.7, r);
	float ring = smoothstep(ring_width, 0.0, abs(r - ring_radius));

	vec3 color = mix(core_color.rgb, ring_color.rgb, ring);
	float alpha = core_color.a * body * 0.9 + ring_color.a * ring;

	ALBEDO = color;
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
