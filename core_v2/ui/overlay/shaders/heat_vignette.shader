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
// Una sola muestra desplazada de pantalla: onda de calor barata, sin blur ni noise texture.
uniform float distortion : hint_range(0.0, 0.02) = 0.0;
// Dirección del daño en pantalla (-1..1). Cero conserva la viñeta radial clásica.
uniform vec2 damage_direction = vec2(0.0);
uniform float directionality : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float wave_x = sin(UV.y * 68.0 + UV.x * 6.0 + TIME * 4.2);
	float wave_y = sin(UV.x * 47.0 - UV.y * 5.0 - TIME * 3.1) * 0.32;
	vec2 heat_uv = clamp(SCREEN_UV + vec2(wave_x, wave_y) * distortion, vec2(0.001), vec2(0.999));
	vec3 screen_color = texture(SCREEN_TEXTURE, heat_uv).rgb;
	vec2 centered = (UV - vec2(0.5)) * vec2(aspect, 1.0) * 2.0;
	float dist = length(centered) / max(aspect, 0.001);

	float inner = mix(inner_radius, inner_radius * 0.25, clamp(creep, 0.0, 1.0));
	float mask = smoothstep(inner, max(outer_radius, inner + 0.001), dist);
	vec2 direction = normalize(damage_direction + vec2(0.00001));
	float directional_mask = smoothstep(-0.35, 0.85, dot(normalize(centered + vec2(0.00001)), direction));
	mask *= mix(1.0, directional_mask, directionality * step(0.001, length(damage_direction)));

	float alpha = clamp(mask * intensity, 0.0, 1.0) * heat_color.a;
	vec3 final_color = mix(screen_color, heat_color.rgb, alpha);
	float effect_alpha = max(alpha, smoothstep(0.0, 0.0005, distortion));
	COLOR = vec4(final_color, effect_alpha);
}
