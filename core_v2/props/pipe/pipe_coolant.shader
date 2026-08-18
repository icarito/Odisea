shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass;

// Conducción con criocoolant circulando (FD-255 / FD-256 / FD-268).
//
// Derivado del shader de la pluma (CryoVent_A) pero con dos diferencias que importan
// para un tubo:
//   1. Es OPACO y con luz: el caño sigue siendo un caño azul, no un velo aditivo.
//      El flujo va por EMISSION, no por ALPHA.
//   2. El ruido se muestrea en COORDENADAS DE MUNDO, no en UV. Cada tramo de tubería
//      es una malla propia con su UV de 0 a 1: con UV, el patrón se reinicia en cada
//      tramo y las uniones se cantan. En mundo, el flujo atraviesa los tramos sin costura.

uniform vec4 base_color : hint_color = vec4(0.06, 0.22, 0.35, 1.0);
uniform vec4 flow_color : hint_color = vec4(0.35, 0.92, 0.98, 1.0);
// Eje de la conducción. Con use_local_axis (por defecto) se deduce del propio tramo, así
// un codo o un ramal rotado llevan el fluido a lo largo de SU caño y no hacia un punto
// cardinal del mundo. flow_dir queda como override para casos raros.
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
uniform bool use_local_axis = true;
uniform bool hide_caps = true;

// Eje del tramo, calculado una vez por vértice.
varying vec3 pipe_axis;
varying vec3 local_pos;

uniform float noise_scale = 1.6;
// Fase del recorrido, en metros. La acumula PipeCoolantRun (fase += delta * velocidad)
// en vez de multiplicar TIME por la velocidad acá: así frenar no produce un salto del
// patrón, porque la fase es continua aunque la velocidad cambie.
uniform float flow_phase = 0.0;
uniform float emission_strength = 1.4;
// Brillo propio del caño donde NO hay veta. Sin esto el fondo del patrón cae a negro.
uniform float base_glow = 0.45;
uniform float pipe_alpha = 0.88;
uniform float flow_contrast = 0.55; // 0 = brillo parejo, 1 = vetas marcadas
uniform float metallic_amount = 0.5;
uniform float roughness_amount = 0.35;

// --- Uniforms de Fisura / Grieta (FD-268) ---
// El centro está en espacio LOCAL de la malla del tramo para mantenerse fijo si el tramo
// o la tubería se mueven en la escena.
uniform vec3 fissure_center = vec3(0.0);
uniform float fissure_radius = 0.35;
uniform float fissure_intensity : hint_range(0.0, 1.0) = 0.0;

// ponytail: un solo centro de grieta por material (una fisura activa por corrida).
// Para soportar múltiples fisuras simultáneas sobre la misma corrida, este parámetro
// se ampliaría a un array de centros/radios o a una textura de máscara de daño.

float hash(vec3 p) {
	p = fract(p * 0.3183099 + .1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm_lod(vec3 p, float dist) {
	float v = 0.6 * noise(p);
	if (dist < 15.0) {
		p *= 2.0;
		v += 0.4 * noise(p);
	}
	return v;
}

// Receta hash-free para grietas (GLES2 / mediump compatible):
// Usa abs(sin(...)) para crestas angulares en V, warping anguloso con abs(sin(...))
// y enmascarado por smoothstep para fraccionar las líneas en segmentos de rotura.
float calculate_crack_pattern(vec3 p) {
	// 1. Domain warping anguloso con abs(sin(...)) para que las líneas quiebren en ángulo
	vec3 warp = vec3(
		abs(sin(dot(p, vec3(12.3, 7.1, 3.4)))),
		abs(sin(dot(p, vec3(4.5, 15.2, 8.7)))),
		abs(sin(dot(p, vec3(9.1, 2.8, 14.6))))
	);
	vec3 wp = p + (warp - 0.5) * 0.45;

	// 2. Crestas angulares intersecting
	float c1 = abs(sin(dot(wp, vec3(22.0, 14.0, 8.0))));
	float c2 = abs(sin(dot(wp, vec3(-15.0, 25.0, 11.0))));
	float c3 = abs(sin(dot(wp, vec3(10.0, -18.0, 24.0))));
	float crests = min(min(c1, c2), c3);

	// Invertir para que los valles/cruces por cero queden como líneas duras
	float line_pattern = 1.0 - smoothstep(0.0, 0.12, crests);

	// 3. Cobertura angosta para fragmentar líneas continuas en segmentos de grieta
	float coverage = smoothstep(0.35, 0.75, abs(sin(dot(p, vec3(7.3, 11.1, 5.9)))));

	return line_pattern * coverage;
}

void vertex() {
	// El largo del cilindro es su Y local; llevado a mundo da el eje real de ESTE tramo.
	pipe_axis = normalize((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	local_pos = VERTEX;
}

void fragment() {
	// Tapas del cilindro fuera: con el caño translúcido se ven como discos por dentro. En
	// un caño opaco no molestan y encima son la cara del extremo, así que es opcional.
	if (hide_caps) {
		vec3 world_normal = normalize((CAMERA_MATRIX * vec4(NORMAL, 0.0)).xyz);
		if (abs(dot(world_normal, pipe_axis)) > 0.8) {
			discard;
		}
	}
	// VERTEX llega en espacio de vista; CAMERA_MATRIX lo lleva a mundo.
	vec3 world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = use_local_axis ? pipe_axis : flow_dir;
	float dist = length(VERTEX);
	float phase = (flow_phase != 0.0) ? flow_phase : (TIME * 0.7);
	vec3 coord = world_pos * noise_scale - axis * phase;
	float n = fbm_lod(coord, dist);
	float flow = smoothstep(0.5 - flow_contrast * 0.5, 0.5 + flow_contrast * 0.5, n);

	vec3 current_albedo = mix(base_color.rgb, flow_color.rgb * 0.5, flow * 0.4);
	vec3 current_emission = flow_color.rgb * (base_glow + flow * emission_strength);

	// Aplica efecto visual de fisura/grieta si hay intensidad activa (FD-268)
	if (fissure_intensity > 0.001) {
		float dist_to_fissure = distance(local_pos, fissure_center);
		if (dist_to_fissure < fissure_radius) {
			float mask = (1.0 - smoothstep(fissure_radius * 0.4, fissure_radius, dist_to_fissure)) * fissure_intensity;
			float crack_pattern = calculate_crack_pattern(local_pos * 18.0);

			// La grieta se ve como fisuras de cristal/metal oscuro con bordes helados superbrillantes
			vec3 crack_dark = vec3(0.01, 0.04, 0.08);
			vec3 crack_glow = flow_color.rgb * 3.5;

			// En la fisura se pierde refrigerante por fuga: la emisión normal cae hacia la rotura
			current_emission = mix(current_emission, current_emission * 0.2, mask);

			// Dibujar grieta en albedo y emisión
			current_albedo = mix(current_albedo, crack_dark, mask * crack_pattern);
			current_emission = mix(current_emission, crack_glow, mask * crack_pattern * 0.95);
		}
	}

	ALBEDO = current_albedo;
	EMISSION = current_emission;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
