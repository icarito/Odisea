shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// FD-324 — pluma del propulsor. Aditiva/emisiva: nucleo blanco-cian brillante,
// gradiente calido/azul en el borde (fresnel) y pulso por TIME. La malla es un
// cono orientado con +Y en la direccion de escape (-thrust_dir), asi que la pluma
// sale exactamente por la espalda de Elias.

uniform vec4 core_color : hint_color = vec4(0.85, 0.98, 1.0, 1.0);
uniform vec4 warm_color : hint_color = vec4(1.0, 0.55, 0.18, 1.0);
uniform vec4 rim_color : hint_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform float pulse_speed = 22.0;
uniform float intensity = 1.15;

void fragment() {
	float pulse = 0.82 + 0.18 * sin(TIME * pulse_speed);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float along = clamp(UV.y, 0.0, 1.0);
	// Nucleo brillante junto a la tobera y cola mas azul.
	float core = smoothstep(0.0, 0.45, 1.0 - along);

	vec3 color = mix(rim_color.rgb, core_color.rgb, core);
	color = mix(color, warm_color.rgb, fresnel * 0.5);

	ALBEDO = color * intensity * (0.9 + 0.5 * pulse);
	ALPHA = clamp(0.35 + 0.55 * fresnel + 0.15 * core, 0.0, 1.0) * (0.8 + 0.2 * pulse);
}
