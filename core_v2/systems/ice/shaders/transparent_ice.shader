shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

// Lámina de hielo translúcido. El desplazamiento de tres capas en función del ángulo de
// vista produce profundidad aparente (parallax) sin alterar la geometría lógica.
uniform vec4 albedo : hint_color = vec4(0.42, 0.78, 1.0, 0.48);
uniform vec4 deep_color : hint_color = vec4(0.03, 0.19, 0.42, 1.0);
uniform float ice_scale : hint_range(0.05, 3.0) = 0.32;
uniform float parallax_depth : hint_range(0.0, 1.0) = 0.42;
uniform float refraction : hint_range(0.0, 0.05) = 0.012;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.36;
uniform float opacity : hint_range(0.0, 1.0) = 0.46;
uniform float freeze_progress : hint_range(0.0, 1.0) = 0.0;
uniform float layer_separation : hint_range(0.0, 2.0) = 0.75;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float ice_detail(vec2 p) {
	float broad = value_noise(p);
	float medium = value_noise(p * 2.13 + 8.7) * 0.5;
	float fine = value_noise(p * 5.31 - 3.2) * 0.25;
	return (broad + medium + fine) / 1.75;
}

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	// Igual que CriopodParallax: proyectar la dirección sobre el plano y dividir por el
	// eje perpendicular. El clamp evita explosiones a ángulos rasantes en GLES2.
	float perpendicular = dot(view_direction, normalize(world_normal));
	float safe_perpendicular = (perpendicular < 0.0 ? -1.0 : 1.0) * max(abs(perpendicular), 0.12);
	vec2 grazing = view_direction.xz / safe_perpendicular;
	vec2 base_uv = world_position.xz * ice_scale;

	float top_layer = ice_detail(base_uv);
	float middle_layer = ice_detail(base_uv * 1.37 + grazing * parallax_depth * 0.7 + vec2(5.1));
	float deep_layer = ice_detail(base_uv * 0.72 + grazing * parallax_depth * 1.55 + vec2(-7.3, 2.8));
	float depth_pattern = top_layer * 0.36 + middle_layer * 0.34 + deep_layer * 0.3;

	// Vetillas finas: aparecen en las fronteras estrechas del ruido, no como manchas.
	float ridge = 1.0 - abs(middle_layer * 2.0 - 1.0);
	float deep_ridge = 1.0 - abs(deep_layer * 2.0 - 1.0);
	float cracks = max(smoothstep(0.9, 0.98, ridge), smoothstep(0.94, 0.99, deep_ridge) * 0.7) * crack_strength;
	vec2 distortion = vec2(top_layer - middle_layer, middle_layer - deep_layer) * refraction * (1.0 - freeze_progress * 0.88);
	vec3 behind_ice = texture(SCREEN_TEXTURE, clamp(SCREEN_UV + distortion, vec2(0.002), vec2(0.998))).rgb;

	float facing = clamp(abs(dot(normalize(world_normal), view_direction)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 2.0);
	// Las tres capas conservan colores distintos: al moverse la cámara, sus contornos se
	// desplazan a velocidades diferentes como las tarjetas internas del CriopodParallax.
	vec3 deep_layer_color = deep_color.rgb * (0.62 + deep_layer * 0.38);
	vec3 middle_layer_color = mix(deep_layer_color, albedo.rgb, 0.34 + middle_layer * 0.3);
	vec3 top_layer_color = mix(middle_layer_color, vec3(0.9, 0.97, 1.0), top_layer * 0.28);
	vec3 layered_ice = mix(deep_layer_color, middle_layer_color, layer_separation * 0.45);
	layered_ice = mix(layered_ice, top_layer_color, layer_separation * 0.35);
	vec3 refracted = mix(behind_ice, layered_ice, 0.46 + freeze_progress * 0.42);
	refracted += vec3(0.7, 0.9, 1.0) * cracks * 0.42;
	// Reflejo falso de cielo/horizonte, visible incluso sin reflection probe en GLES2.
	vec3 sky_reflection = mix(vec3(0.16, 0.34, 0.55), vec3(0.82, 0.95, 1.0), clamp(view_direction.y * 0.5 + 0.5, 0.0, 1.0));
	refracted = mix(refracted, sky_reflection, (0.1 + fresnel * 0.42) * (1.0 - freeze_progress * 0.6));

	// La escarcha conquista primero las zonas altas del ruido y luego cierra los huecos.
	float frost_threshold = mix(0.92, 0.22, freeze_progress);
	float frost_mask = smoothstep(frost_threshold - 0.13, frost_threshold + 0.08, depth_pattern);
	float fine_frost = smoothstep(0.54, 0.78, ice_detail(base_uv * 4.7 + vec2(13.0))) * freeze_progress;
	frost_mask = clamp(frost_mask + fine_frost * 0.42, 0.0, 1.0);
	vec3 frost_color = vec3(0.9, 0.965, 1.0);
	refracted = mix(refracted, frost_color, frost_mask * mix(0.18, 0.82, freeze_progress));

	ALBEDO = refracted;
	ROUGHNESS = mix(0.12, 0.88, freeze_progress * (0.55 + frost_mask * 0.45));
	SPECULAR = mix(1.0, 0.35, freeze_progress);
	METALLIC = 0.05;
	EMISSION = albedo.rgb * cracks * 0.06;
	float frozen_opacity = mix(opacity, 0.94, freeze_progress);
	ALPHA = clamp(frozen_opacity + frost_mask * 0.12 + fresnel * 0.08, 0.42, 0.96);
}
