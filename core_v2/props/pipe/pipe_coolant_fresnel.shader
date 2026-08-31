shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Variante fresnel del coolant. Sale de un shader de Godot 4 (source_color,
// NORMAL_MAP + normal map scrolleado); aca esta traducido a Godot 3.6 / GLES2:
//
//  - source_color            -> hint_color
//  - literales int (= 5)     -> float (= 5.0)
//  - NORMAL_MAP              -> NO se usa. Las mallas horneadas de pipe no traen
//    tangentes (bake_pipe_network.gd solo llama generate_normals()), y NORMAL_MAP
//    transforma desde espacio tangente: sin tangentes el relieve sale indefinido.
//    En su lugar se perturba NORMAL directo, en un marco construido sobre el eje
//    del cano, que es estable tramo a tramo y no depende de UV ni de atributos.
//  - la textura de normales   -> gradiente del ruido ya horneado (pipe_flow_noise).
//    Sin hash con sin(): en Adreno/GLES2 eso aliasa a gris (ver
//    reference_gles2_adreno_shader_noise).

uniform vec4 base_color : hint_color = vec4(0.01, 0.15, 0.35, 1.0);
uniform vec4 fresnel_color : hint_color = vec4(0.01, 0.587, 1.0, 1.0);
uniform bool invert_fresnel = false;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform float fresnel_gain : hint_range(0.0, 8.0) = 4.5;
uniform float pipe_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float pipe_metallic : hint_range(0.0, 1.0) = 0.3;

uniform sampler2D flow_noise : hint_black;
// Relieve del fluido. Equivale al normalMapStrngth del original.
uniform float relief : hint_range(0.0, 2.0) = 0.4;
// Celdas de ruido por metro, a lo largo y alrededor del cano (scaleX / scaleY).
uniform float scale_around : hint_range(0.05, 4.0) = 0.9;
uniform float scale_along : hint_range(0.05, 4.0) = 0.5;
uniform float flow_speed : hint_range(0.0, 4.0) = 0.7;

uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
uniform bool use_local_axis = true;
// Eje horneado por vertice. bake_pipe_network.gd fusiona todos los tramos de un
// grupo en UN MeshInstance, asi que WORLD_MATRIX pasa a ser uno solo para un cano
// que curva y el eje calculado sale constante: el patron corre en una direccion
// fija a lo largo de la curva y se ve como bandas. Por eso el baker guarda el eje
// de cada tramo en COLOR y PipeCoolantRun prende esto cuando hay CombinedMesh.
uniform bool use_baked_axis = false;
uniform float flow_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.4;

// Misma marca direccional que en pipe_coolant.shader: el ruido es simetrico y por
// si solo no dice hacia donde corre el caudal.
uniform float direction_marks : hint_range(0.0, 1.0) = 0.35;
uniform float direction_marks_scale : hint_range(0.05, 3.0) = 0.45;
uniform float direction_marks_sharpness : hint_range(1.0, 8.0) = 3.0;

varying vec3 pipe_axis;

float n2(vec2 p) {
	return texture(flow_noise, p * 0.015625).r;
}

void vertex() {
	if (use_baked_axis) {
		pipe_axis = normalize(COLOR.rgb * 2.0 - 1.0);
	} else {
		pipe_axis = normalize((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}

void fragment() {
	vec3 world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = use_local_axis ? normalize(pipe_axis) : normalize(flow_dir);

	// Marco estable alrededor del eje. El `ref` inclinado evita el caso degenerado
	// de un cano vertical (cross con UP daria cero).
	vec3 ref = vec3(0.0042, 1.0, 0.0071);
	vec3 tang = normalize(cross(axis, ref));
	vec3 bitan = normalize(cross(axis, tang));

	// Marco CILINDRICO GLOBAL, no el eje de cada tramo. Con el eje local las
	// coordenadas del ruido saltan en cada union (un anillo rota 15 grados por
	// pieza) y el cano sale con bandas duras alternadas. Aca todo sale de la
	// posicion y la normal en mundo, que son continuas de punta a punta.
	vec3 radial = normalize(vec3(world_pos.x, 0.0, world_pos.z) + vec3(0.0001, 0.0, 0.0));
	float ring_r = length(vec2(world_pos.x, world_pos.z));
	// A lo largo: LONGITUD DE ARCO para los anillos, altura para los verticales.
	//
	// No sirve dot(world_pos, axis), que es lo natural y lo que hace el shader
	// viejo: en un anillo el eje es tangente y la posicion radial, asi que el
	// producto punto da 0 en toda la vuelta. Con `along` constante el patron solo
	// varia alrededor del tubo y se ve como anillos concentricos — el tejido.
	float along = mix(atan(world_pos.z, world_pos.x) * ring_r, world_pos.y,
		clamp(abs(axis.y), 0.0, 1.0));
	// alrededor del tubo: angulo de la normal en el plano radial-vertical
	vec3 world_normal = normalize((CAMERA_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float around = atan(world_normal.y, dot(world_normal, radial)) * 0.5;

	float scroll = TIME * flow_speed;
	vec2 uv = vec2(around * scale_around, along * scale_along) - vec2(0.0, scroll);

	// Gradiente del ruido por diferencias finitas -> relieve, sin normal map.
	float e = 0.6;
	float h = n2(uv);
	float dh_around = n2(uv + vec2(e, 0.0)) - h;
	float dh_along = n2(uv + vec2(0.0, e)) - h;

	// NORMAL vive en espacio de vista dentro de fragment(); el marco es de mundo,
	// asi que hay que llevarlo a vista antes de sumarlo.
	vec3 tang_v = normalize((INV_CAMERA_MATRIX * vec4(bitan, 0.0)).xyz);
	vec3 axis_v = normalize((INV_CAMERA_MATRIX * vec4(axis, 0.0)).xyz);
	NORMAL = normalize(NORMAL - (tang_v * dh_around + axis_v * dh_along) * relief * 8.0);

	float f_dot = 1.0 - dot(normalize(NORMAL), normalize(VIEW));
	float fresnel_factor = pow(max(f_dot, 0.0), fresnel_power);

	float head = 0.0;
	if (direction_marks > 0.001) {
		float saw = fract(along * direction_marks_scale - scroll * 0.5);
		head = pow(1.0 - saw, direction_marks_sharpness) * direction_marks;
	}

	float active = clamp(flow_intensity, 0.0, 1.0);
	vec3 albedo;
	if (invert_fresnel) {
		albedo = mix(base_color.rgb, fresnel_color.rgb,
			clamp(fresnel_factor * fresnel_gain, 0.0, 1.0));
	} else {
		albedo = base_color.rgb + fresnel_factor * fresnel_color.rgb * fresnel_gain;
	}
	ALBEDO = mix(base_color.rgb * 0.34, albedo, active);
	ROUGHNESS = pipe_roughness;
	METALLIC = pipe_metallic;
	EMISSION = fresnel_color.rgb * active
		* (fresnel_factor * fresnel_gain * 0.25 + head) * emission_strength;
}
