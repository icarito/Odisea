shader_type canvas_item;
render_mode unshaded, blend_mix;

// Viñeta de escarcha: color frío y acumulación periférica. No refracta la pantalla.
uniform vec4 frost_color : hint_color = vec4(0.82, 0.94, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.2) = 0.3;
uniform float outer_radius : hint_range(0.0, 1.6) = 0.92;
uniform float aspect = 1.7777;
uniform float creep : hint_range(0.0, 1.0) = 0.0;
uniform vec2 damage_direction = vec2(0.0);
uniform float directionality : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(aspect, 1.0) * 2.0;
	float dist = length(centered) / max(aspect, 0.001);
	float inner = mix(inner_radius, inner_radius * 0.25, clamp(creep, 0.0, 1.0));
	float mask = smoothstep(inner, max(outer_radius, inner + 0.001), dist);
	vec2 direction = normalize(damage_direction + vec2(0.00001));
	float directional_mask = smoothstep(-0.35, 0.85, dot(normalize(centered + vec2(0.00001)), direction));
	mask *= mix(1.0, directional_mask, directionality * step(0.001, length(damage_direction)));
	float alpha = clamp(mask * intensity, 0.0, 1.0) * frost_color.a;
	COLOR = vec4(frost_color.rgb, alpha);
}
