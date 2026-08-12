shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_alpha_prepass, diffuse_burley, specular_schlick_ggx;

// Superficie económica: una sola lectura de textura en coordenadas de mundo.
// El Fresnel es deliberadamente leve para que el dibujo no cambie con la cámara.
uniform vec4 albedo : hint_color = vec4(0.88, 0.95, 1.0, 0.62);
uniform vec4 deep_color : hint_color = vec4(0.14, 0.3, 0.46, 1.0);
uniform float crack_strength : hint_range(0.0, 1.0) = 0.36;
uniform float opacity : hint_range(0.0, 1.0) = 0.74;
uniform float freeze_progress : hint_range(0.0, 1.0) = 0.0;
uniform float emission_boost : hint_range(0.0, 6.0) = 1.0;
uniform sampler2D ice_texture : hint_albedo;
uniform sampler2D ice_normal : hint_normal;
uniform sampler2D ice_roughness;
uniform sampler2D ice_ao;
uniform float texture_scale : hint_range(0.01, 1.0) = 0.085;
uniform vec2 uv_offset = vec2(0.0);
uniform float surface_radius : hint_range(1.0, 100.0) = 29.7;
uniform bool low_end_mobile = false;
uniform bool mobile_color_pbr = true;
// --- Simplificacion por distancia ---
// Esta es la superficie que mas pantalla tapa del nivel: el disco entero del domo. Vista
// desde lo alto de la torre (el peor tramo del replay) se ve casi completa y en angulo
// rasante, que es el peor caso posible para una textura mosaico: el patron cae por debajo
// del pixel, cada lectura toca una zona distinta del atlas y la cache de textura falla en
// casi todos los accesos.
//
// `lod_strength` fuerza un nivel de mip segun la distancia. Ademas de matar el aliasing,
// es lo que vuelve barata la lectura justo donde duele, porque un mip grueso entra entero
// en cache. No es un branch: el costo se paga igual en todos lados y el resultado esta
// definido (textureLod no depende de derivadas).
uniform float lod_strength : hint_range(0.0, 2.0) = 0.35;
// A partir de aca se dejan de calcular las grietas: a esa distancia ya no se distinguen y
// son dos smoothstep por pixel.
uniform float detail_distance : hint_range(1.0, 200.0) = 22.0;
uniform float detail_fade : hint_range(0.1, 60.0) = 10.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (length(world_position.xz) > surface_radius) {
		discard;
	}
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	// El fract fuerza el mosaico aun si el importador o el driver ignoran Repeat.
	vec2 ice_uv = fract(world_position.xz * texture_scale + uv_offset);
	float cam_dist = distance(CAMERA_POSITION_WORLD, world_position);
	float mip = clamp(log2(1.0 + cam_dist * lod_strength), 0.0, 6.0);
	// 1 cerca, 0 lejos: apaga el detalle fino que a distancia no se resuelve.
	float detail = 1.0 - smoothstep(detail_distance, detail_distance + detail_fade, cam_dist);
	// Sin branch por distancia a proposito: se probo saltear el muestreo mas alla de 40 m
	// tomando un texel fijo del mip mas grueso, y MEDIDO empeoro 22% (28.51 -> 22.23 fps) y
	// subio las draw calls de 235 a 373. El sesgo de mip continuo alcanza y no tiene ese
	// costo. No reintentar sin medir.
	vec3 texel = textureLod(ice_texture, ice_uv, mip).rgb;
	vec3 normal_texel = vec3(0.5, 0.5, 1.0);
	float roughness_texel = 0.72;
	float ao_texel = 1.0;
	if (!low_end_mobile) {
		normal_texel = textureLod(ice_normal, ice_uv, mip).rgb;
		roughness_texel = textureLod(ice_roughness, ice_uv, mip).r;
		ao_texel = textureLod(ice_ao, ice_uv, mip).r;
	}
	float texture_detail = dot(texel, vec3(0.299, 0.587, 0.114));
	float cracks = smoothstep(0.66, 0.84, texture_detail) * crack_strength * detail;
	float frost_mask = smoothstep(mix(0.82, 0.28, freeze_progress), 0.92, texture_detail);
	// Conservar el color real del PBR: el contraste entre su azul superficial y el tono
	// profundo es lo que daba volumen antes de las compensaciones blancas.
	vec3 textured_ice = mix(deep_color.rgb, texel * albedo.rgb * 1.3, 0.82);
	// Fresnel desactivado temporalmente para aislar reflejos dependientes de la cámara.
	textured_ice = mix(textured_ice, vec3(0.9, 0.965, 1.0), frost_mask * freeze_progress * 0.55);
	textured_ice = mix(textured_ice, vec3(0.96, 0.985, 1.0), cracks * 0.16);

	if (low_end_mobile) {
		// Evita que varias OmniLight acumulen pases inestables sobre transparencia en GLES2.
		// La lectura de color permanece PBR, pero su iluminación es ambiental y constante.
		ALBEDO = vec3(0.0);
		NORMALMAP = vec3(0.5, 0.5, 1.0);
		NORMALMAP_DEPTH = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		AO = 1.0;
		EMISSION = textured_ice * 0.72 + vec3(0.55, 0.78, 1.0) * cracks * 0.003 * emission_boost;
	} else if (mobile_color_pbr) {
		// Paleta legible de Android, conservando el relieve y respuesta PBR de desktop.
		ALBEDO = textured_ice * 0.42;
		NORMALMAP = normal_texel;
		NORMALMAP_DEPTH = 0.34;
		ROUGHNESS = mix(roughness_texel, 0.86, freeze_progress);
		SPECULAR = mix(0.38, 0.26, freeze_progress);
		AO = mix(1.0, ao_texel, 0.55);
		EMISSION = textured_ice * 0.06 + vec3(0.55, 0.78, 1.0) * cracks * 0.004 * emission_boost;
	} else {
		ALBEDO = textured_ice;
		NORMALMAP = normal_texel;
		NORMALMAP_DEPTH = 0.34;
		ROUGHNESS = mix(roughness_texel, 0.86, freeze_progress);
		SPECULAR = mix(0.38, 0.26, freeze_progress);
		AO = mix(1.0, ao_texel, 0.55);
		EMISSION = vec3(0.55, 0.78, 1.0) * cracks * 0.004 * emission_boost;
	}
	float height_opacity = smoothstep(0.0, 1.0, freeze_progress);
	ALPHA = clamp(mix(opacity, 0.94, height_opacity) + frost_mask * height_opacity * 0.01, 0.68, 0.95);
}
