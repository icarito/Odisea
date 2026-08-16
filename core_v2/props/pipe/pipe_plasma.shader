shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Conducción de plasma: volumen cian/violeta caliente contenido detrás de una carcasa.
// La oscilación longitudinal comunica flujo sin convertir la superficie en una
// textura orgánica de lava: el caño entero irradia y el núcleo blanquea al pasar.
uniform vec4 base_color : hint_color = vec4(0.008, 0.015, 0.055, 1.0);
uniform vec4 flow_color : hint_color = vec4(0.08, 0.48, 1.0, 1.0);
uniform vec4 core_color : hint_color = vec4(0.76, 0.16, 1.0, 1.0);
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
// Cuánto se estira el ruido a lo largo del caño. Más bajo = filamentos más largos.
uniform float axial_stretch = 0.22;
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

// Ruido de valor, para romper la regularidad. Un sin() puro a lo largo del tubo da
// bandas perfectamente parejas: se lee como pintura industrial, no como energía.
float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i + vec3(0,0,0)), hash13(i + vec3(1,0,0)), f.x),
				   mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
				   mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

// Eje del tramo (largo local del cilindro) llevado a mundo.
varying vec3 pipe_axis;

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pipe_axis = normalize((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	// Las tapas circulares del cilindro son geometría real, y con el tubo translúcido se
	// ven como discos flotando dentro del caño. Su normal es paralela al eje: se descartan.
	vec3 world_normal = normalize((CAMERA_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (abs(dot(world_normal, pipe_axis)) > 0.8) {
		discard;
	}
	// Dos capas de ruido afinadas a cresta: filamentos finos que corren por el tubo, no
	// bandas. La primera es el hilo principal; la segunda, chispazos sueltos más rápidos.
	//
	// El muestreo es POSICIONAL, sin UV. La UV va de 0 a 1 en cada tramo y en cada anillo,
	// así que partía el dibujo en cada unión: eso eran las costuras. Acá el ruido se toma
	// en coordenadas de mundo, que son continuas de un tramo al siguiente. Para que salgan
	// filamentos y no manchas, el espacio se COMPRIME a lo largo del eje del caño
	// (axial_stretch): el mismo ruido, estirado en la dirección del caudal.
	float along = dot(world_position, pipe_axis);
	vec3 lateral = world_position - pipe_axis * along;
	vec3 coord = lateral * noise_scale
		+ pipe_axis * (along * noise_scale * axial_stretch - flow_phase);
	float n1 = fbm3(coord);
	float n2 = fbm3(coord * 2.3 + vec3(11.0, 5.0, 3.0) - pipe_axis * flow_phase * 0.7);
	float filament = pow(1.0 - abs(n1 * 2.0 - 1.0), 5.0);
	float spark = pow(1.0 - abs(n2 * 2.0 - 1.0), 14.0);
	// Latido irregular: la energía no pulsa a compás.
	float flicker = 0.7 + 0.3 * sin(flow_phase * 7.0 + n1 * 11.0);
	float core = clamp(filament * 1.15 + spark * 2.0, 0.0, 1.0) * flicker;
	core = mix(core, smoothstep(0.35, 0.95, core), flow_contrast);
	vec3 plasma = mix(flow_color.rgb, core_color.rgb, core);
	vec3 damage_sample = texture(damage_texture, vec2(UV.y * damage_scale, UV.x * damage_scale)).rgb;
	float damage_luma = dot(damage_sample, vec3(0.299, 0.587, 0.114));
	float texture_fracture = smoothstep(damage_threshold, min(damage_threshold + 0.18, 1.0), damage_luma);
	float break_distance = abs(world_position.x - damage_center_x);
	float break_zone = 1.0 - smoothstep(0.06, damage_extent, break_distance);
	float fracture = texture_fracture * break_zone;
	vec3 crack_glow = flow_color.rgb * fracture * damage_strength;

	ALBEDO = mix(base_color.rgb, plasma * 0.08 + crack_glow * 0.12, 0.15 + core * 0.15);
	EMISSION = plasma * (0.03 + core * 0.55) * emission_strength + crack_glow * emission_strength;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
