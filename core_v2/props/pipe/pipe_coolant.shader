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
// Un MeshInstance horneado fusiona varios tramos con distinta rotación original en una
// sola malla: WORLD_MATRIX pasa a ser una única matriz para TODO el mesh combinado, así
// que ya no sirve para recuperar el eje de CADA tramo (ver bake_pipe_network.gd). Con
// use_baked_axis, el eje se lee de COLOR, horneado por-vértice en bake-time con el
// transform real de cada tramo, antes de fusionar.
uniform bool use_baked_axis = false;

// Eje del tramo, calculado una vez por vértice.
varying vec3 pipe_axis;

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
// El centro va en COORDENADAS DE MUNDO, igual que el ruido del flujo. En espacio local
// hay que acertarle al espacio de la MALLA (lo que ve VERTEX), no al del nodo que gobierna
// la corrida: en una corrida cuyo mesh esta rotado respecto del nodo, el centro caia a
// varios metros del cano y la grieta no se dibujaba en ningun lado. El componente reescribe
// el uniform cada tick, asi que un tramo que se mueva igual lo sigue.
uniform vec3 fissure_center = vec3(0.0);
uniform float fissure_radius = 0.35;
uniform float fissure_intensity : hint_range(0.0, 1.0) = 0.0;
// Escala del patron de grieta, en rasgos por metro. Baja = pocas lineas largas y legibles;
// alta = moteado fino que se lee como CORROSION, no como una rotura. Un cano de 0.32 de
// diametro necesita valores chicos: a 18 los rasgos quedaban de milimetros y el cano
// parecia oxidado en vez de partido.
uniform float crack_scale = 2.5;

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

// LOD_NEAR: por debajo de esto, ruido de 2 octavas (detalle fino visible de cerca).
// LOD_FAR: por encima de esto, nada de ruido — el caño es un tubo liso con la emision
// base. El jugador nota el flujo a metros, no a decenas de metros; en un domo abierto sin
// oclusion la mayoria de los ~114 meshes del riser estan siempre en pantalla, asi que
// pagar noise()/discard/grieta por fragmento en el 90% que rara vez se mira de cerca es
// el costo que mas duele en GLES2/Adreno.
const float LOD_NEAR = 10.0;
const float LOD_FAR = 20.0;

// El caller ya filtra dist > LOD_FAR antes de llamar esto (fragment() ni siquiera arma
// world_pos/coord en ese caso), asi que solo queda decidir 1 vs 2 octavas.
float fbm_lod(vec3 p, float dist) {
	float v = 0.6 * noise(p);
	if (dist < LOD_NEAR) {
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
	float line_pattern = 1.0 - smoothstep(0.0, 0.35, crests);

	// 3. Cobertura angosta para fragmentar líneas continuas en segmentos de grieta
	float coverage = smoothstep(0.15, 0.55, abs(sin(dot(p, vec3(0.9, 1.4, 0.7)))));

	return line_pattern * coverage;
}

void vertex() {
	if (use_baked_axis) {
		// COLOR.rgb trae el eje ya calculado en bake-time con el transform real de CADA
		// tramo original (bake_pipe_network.gd), remapeado de [-1,1] a [0,1] para caber en
		// un atributo de color (COLOR.a queda libre, en 1.0).
		pipe_axis = normalize(COLOR.rgb * 2.0 - 1.0);
	} else {
		// El largo del cilindro es su Y local; llevado a mundo da el eje real de ESTE tramo.
		pipe_axis = normalize((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}

void fragment() {
	// VERTEX llega en espacio de vista: su largo YA es la distancia real al ojo, sin
	// ninguna transformacion extra. Calcularla primero deja gatear TODO lo caro del
	// fragmento (discard de tapas, ruido, grieta) por LOD, en vez de solo el ruido.
	float dist = length(VERTEX);

	// Tapas del cilindro fuera: con el caño translúcido se ven como discos por dentro. En
	// un caño opaco no molestan y encima son la cara del extremo, así que es opcional.
	// Lejos (> LOD_FAR) ni se calcula: una tapa visible a 20+ metros es imperceptible, y
	// el discard + el producto punto que lo decide no valen su costo ahi.
	if (hide_caps && dist < LOD_FAR) {
		vec3 world_normal = normalize((CAMERA_MATRIX * vec4(NORMAL, 0.0)).xyz);
		if (abs(dot(world_normal, pipe_axis)) > 0.8) {
			discard;
		}
	}
	// Lejos, fbm_lod() ya devuelve un valor fijo (0.5) sin tocar noise(): world_pos/coord
	// solo alimentan ese calculo (y fissure_center mas abajo, ya gateado por LOD_FAR
	// tambien), asi que calcular la matriz de camara completa ahi es puro desperdicio.
	vec3 world_pos = vec3(0.0);
	float n = 0.5;
	if (dist < LOD_FAR) {
		// VERTEX llega en espacio de vista; CAMERA_MATRIX lo lleva a mundo.
		world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 axis = use_local_axis ? pipe_axis : flow_dir;
		float phase = (flow_phase != 0.0) ? flow_phase : (TIME * 0.7);
		vec3 coord = world_pos * noise_scale - axis * phase;
		n = fbm_lod(coord, dist);
	}
	float flow = smoothstep(0.5 - flow_contrast * 0.5, 0.5 + flow_contrast * 0.5, n);

	vec3 current_albedo = mix(base_color.rgb, flow_color.rgb * 0.5, flow * 0.4);
	vec3 current_emission = flow_color.rgb * (base_glow + flow * emission_strength);

	// La grieta tampoco se calcula lejos: a mas de LOD_FAR el patron fragmentado de
	// calculate_crack_pattern (3 dot+sin con domain warping) es indistinguible de una
	// mancha, y sigue viendose la fuga por el jet de particulas (LeakFissureVisual), no
	// por el detalle del cano.
	if (fissure_intensity > 0.001 && dist < LOD_FAR) {
		float dist_to_fissure = distance(world_pos, fissure_center);
		if (dist_to_fissure < fissure_radius) {
			float mask = (1.0 - smoothstep(fissure_radius * 0.4, fissure_radius, dist_to_fissure)) * fissure_intensity;
			float crack_pattern = calculate_crack_pattern(world_pos * crack_scale);

			vec3 crack_dark = vec3(0.01, 0.04, 0.08);
			vec3 crack_glow = flow_color.rgb * 3.5;

			// En la fisura se pierde refrigerante: la emision normal cae hacia la rotura.
			current_emission = mix(current_emission, current_emission * 0.2, mask);

			// Una grieta es un HUECO: el trazo va oscuro y apaga la emision. Antes el brillo
			// se pintaba sobre todo el trazo a 3.5x y tapaba el albedo oscuro, asi que la
			// rotura se leia como una mancha palida — corrosion o escarcha, no una partidura.
			current_albedo = mix(current_albedo, crack_dark, mask * crack_pattern);
			current_emission = mix(current_emission, current_emission * 0.05, mask * crack_pattern);

			// El brillo queda solo en el FILO (banda angosta del patron): es el refrigerante
			// helado escapando por el borde, y es lo que le da profundidad al hueco.
			float rim = smoothstep(0.20, 0.45, crack_pattern) * (1.0 - smoothstep(0.45, 0.75, crack_pattern));
			current_emission += crack_glow * mask * rim * 0.7;
		}
	}

	ALBEDO = current_albedo;
	EMISSION = current_emission;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
