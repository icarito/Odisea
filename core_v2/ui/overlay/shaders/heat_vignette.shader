shader_type canvas_item;
render_mode unshaded, blend_mix;

// FD-051: viñeta roja de calor. Alpha es función solo del estado que le pasa el script
// (ratio de integridad del traje + pulso de contacto). No lee nada del mundo.

uniform vec4 heat_color : hint_color = vec4(0.85, 0.12, 0.03, 1.0);
// Intensidad global de la viñeta [0..1].
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// Radio donde arranca el degradado desde el centro.
uniform float inner_radius : hint_range(0.0, 1.2) = 0.35;
// Radio donde la viñeta llega a full.
uniform float outer_radius : hint_range(0.0, 1.6) = 0.95;
// Corrección de aspecto para que la viñeta sea elíptica, no circular deformada.
uniform float aspect = 1.7777;
// Empuje extra del color hacia el centro cuando el traje está por romperse.
uniform float creep : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(aspect, 1.0) * 2.0;
	float dist = length(centered) / max(aspect, 0.001);

	float inner = mix(inner_radius, inner_radius * 0.25, clamp(creep, 0.0, 1.0));
	float mask = smoothstep(inner, max(outer_radius, inner + 0.001), dist);

	float alpha = clamp(mask * intensity, 0.0, 1.0) * heat_color.a;
	COLOR = vec4(heat_color.rgb, alpha);
}
