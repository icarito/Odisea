shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled;

// Conducción de plasma: volumen cian/violeta caliente contenido detrás de una carcasa.
// La oscilación longitudinal comunica flujo sin convertir la superficie en una
// textura orgánica de lava: el caño entero irradia y el núcleo blanquea al pasar.
uniform vec4 base_color : hint_color = vec4(0.008, 0.015, 0.055, 1.0);
uniform vec4 flow_color : hint_color = vec4(0.08, 0.48, 1.0, 1.0);
uniform vec4 core_color : hint_color = vec4(0.76, 0.16, 1.0, 1.0);
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
uniform float noise_scale = 3.2;
uniform float flow_phase = 0.0;
uniform float emission_strength = 1.6;
uniform float pipe_alpha = 1.0;
uniform float flow_contrast = 0.5;
uniform float metallic_amount = 0.65;
uniform float roughness_amount = 0.28;
// La textura de hielo se usa como patrón de craquelado térmico sobre la UV
// cilíndrica; no es un decal y por tanto funciona igual en GLES2.
uniform sampler2D damage_texture : hint_albedo;
uniform float damage_scale = 1.15;
uniform float damage_threshold = 0.52;
uniform float damage_strength = 0.36;
uniform float damage_center_x = 0.0;
uniform float damage_extent = 0.58;

varying vec3 world_position;

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float pulse = 0.5 + 0.5 * sin((UV.y * noise_scale - flow_phase) * 6.283185);
	float core = smoothstep(0.52, 0.94, pulse);
	vec3 plasma = mix(flow_color.rgb, core_color.rgb, core);
	vec3 damage_sample = texture(damage_texture, vec2(UV.y * damage_scale, UV.x * damage_scale)).rgb;
	float damage_luma = dot(damage_sample, vec3(0.299, 0.587, 0.114));
	float texture_fracture = smoothstep(damage_threshold, min(damage_threshold + 0.18, 1.0), damage_luma);
	float break_distance = abs(world_position.x - damage_center_x);
	float break_zone = 1.0 - smoothstep(0.06, damage_extent, break_distance);
	float fracture = texture_fracture * break_zone;
	vec3 crack_glow = flow_color.rgb * fracture * damage_strength;

	ALBEDO = mix(base_color.rgb, plasma * 0.08 + crack_glow * 0.12, 0.15 + core * 0.15);
	EMISSION = plasma * (0.03 + core * 0.15) * emission_strength + crack_glow * emission_strength;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
