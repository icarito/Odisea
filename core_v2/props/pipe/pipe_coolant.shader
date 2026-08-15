shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass;

// Conducción con criocoolant circulando (FD-255 / FD-256).
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
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0); // eje de la conducción, en mundo
uniform float noise_scale = 1.6;
// Fase del recorrido, en metros. La acumula PipeCoolantRun (fase += delta * velocidad)
// en vez de multiplicar TIME por la velocidad acá: así frenar no produce un salto del
// patrón, porque la fase es continua aunque la velocidad cambie.
uniform float flow_phase = 0.0;
uniform float emission_strength = 1.4;
uniform float pipe_alpha = 0.88;
uniform float flow_contrast = 0.55; // 0 = brillo parejo, 1 = vetas marcadas
uniform float metallic_amount = 0.5;
uniform float roughness_amount = 0.35;

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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// VERTEX llega en espacio de vista; CAMERA_MATRIX lo lleva a mundo.
	vec3 world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 coord = world_pos * noise_scale - flow_dir * flow_phase;
	float n = fbm(coord);
	float flow = smoothstep(0.5 - flow_contrast * 0.5, 0.5 + flow_contrast * 0.5, n);

	ALBEDO = mix(base_color.rgb, flow_color.rgb * 0.5, flow * 0.4);
	EMISSION = flow_color.rgb * flow * emission_strength;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
