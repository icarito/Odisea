shader_type spatial;
// Variante de FlatFake con LINTERNA, para el prototipo de "luces apagadas".
//
// FlatFake da volumen con un headlight falso en espacio de camara y nunca corre
// el light loop. Eso es justo lo que hace viable el perfil bajo — y tambien la
// razon por la que una SpotLight real no ilumina nada ahi. Asi que la linterna
// se calcula aca, analiticamente, y cuesta unas pocas ALU sobre un fragment que
// igual se estaba pagando: sin pases nuevos, sin sombras, sin luces.
//
// El cono NO puede colgarse del eje de la camara: seria un headlight de primera
// persona, y la camara de Odisea va en tercera. La linterna es un prop del casco
// de Elias que apunta hacia donde mira EL, no hacia donde mira la camara, y puede
// estar apagada. Asi que la posicion, la direccion y el encendido entran por
// uniform en espacio de MUNDO, y el fragmento se lleva ahi con CAMERA_MATRIX
// (view -> mundo en Godot 3). GLES3VendorGate los sincroniza cada tick desde la
// SpotLight real.
render_mode unshaded, cull_back, depth_draw_opaque, specular_disabled;

uniform vec3 albedo = vec3(0.7, 0.72, 0.76);
uniform vec3 light_dir_view = vec3(0.35, 0.55, 0.75);
uniform float ambient = 0.14;
uniform float vertical_ao = 0.35;
uniform float exposure = 0.88;
uniform float glow = 0.0;
// Lightmap horneado opcional (IOSLightmapFallback setea lightmap_mix=1).
uniform sampler2D lightmap_tex;
uniform float lightmap_energy = 1.0;
uniform float lightmap_mix = 0.0;

// --- Linterna ---------------------------------------------------------------
uniform float flashlight_range = 14.0;
uniform float cone_cos_inner = 0.94;
uniform float cone_cos_outer = 0.80;
uniform vec3 flashlight_color = vec3(1.0, 0.96, 0.86);
uniform float flashlight_energy = 1.6;
// Espacio de MUNDO, sincronizados desde la SpotLight del casco.
uniform vec3 flashlight_pos = vec3(0.0, 0.0, 0.0);
uniform vec3 flashlight_dir = vec3(0.0, 0.0, -1.0);
// 0 = apagada: queda solo world_light. Sigue el `enabled` del prop y su bateria.
uniform float flashlight_on = 0.0;
// Cuanta luz hay FUERA del cono. 0.0 = apagon total, 1.0 = como sin linterna.
// Esta es la perilla de "oscurecer / aclarar la escena".
uniform float world_light = 0.05;
// Piso del glow cuando world_light llega a 0. Las barandas del bake estan
// marcadas con emision igual que las lamparas, asi que con glow puro quedaban
// inmunes a la oscuridad: por mas que se apague todo seguian a pleno amarillo.
// Con esto el glow se atenua junto con la escena, pero no del todo: las
// lamparas y el vidrio siguen insinuandose, que es la guia visual del nivel.
uniform float glow_floor = 0.35;

varying float v_world_y;

void vertex() {
	v_world_y = (WORLD_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Shading base, igual que FlatFake.
	vec3 l = normalize(light_dir_view);
	float ndl = clamp(dot(normalize(NORMAL), l) * 0.5 + 0.5, 0.0, 1.0);
	ndl = pow(ndl, 1.4);
	float ao = 1.0 - vertical_ao * clamp(0.5 - v_world_y * 0.04, 0.0, 1.0);
	vec3 shaded = albedo * (ambient + (1.0 - ambient) * ndl) * ao * exposure;

	// El fragmento a espacio de mundo, que es donde vive la linterna.
	vec3 world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_frag = world_pos - flashlight_pos;
	float dist = length(to_frag);
	// Cono contra el eje REAL de la linterna, no contra el de la camara.
	float axis = dot(to_frag / max(dist, 0.001), normalize(flashlight_dir));
	float cone = smoothstep(cone_cos_outer, cone_cos_inner, axis);
	float falloff = clamp(1.0 - dist / max(flashlight_range, 0.001), 0.0, 1.0);
	falloff *= falloff;

	// Fuera del cono queda world_light; dentro sube hasta flashlight_energy.
	float beam = cone * falloff * flashlight_energy * clamp(flashlight_on, 0.0, 1.0);
	float lit = world_light + beam;

	vec3 tinted = mix(vec3(1.0), flashlight_color, clamp(beam, 0.0, 1.0));
	vec3 world = shaded * lit * tinted;

	// El glow se atenua con la escena pero nunca baja del piso: una lampara
	// encendida tiene que seguir leyendose con todo apagado.
	float glow_mix = glow * mix(glow_floor, 1.0, clamp(world_light, 0.0, 1.0));
		vec3 lm_mul = vec3(1.0);
	if (lightmap_mix > 0.001) { lm_mul = mix(vec3(1.0), texture(lightmap_tex, UV2).rgb * lightmap_energy, lightmap_mix); }
ALBEDO = mix(world, albedo * max(glow_mix, world_light), glow_mix) * lm_mul;
}
