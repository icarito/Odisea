shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass;

// Flujo de criocoolant con el look del agua anime (voronoi + fbm, MIT @arlez80):
// celdas de piscina y bordes de espuma. El muestreo es posicional en mundo, no por
// UV, para que el patron no se parta en las uniones de los cilindros.
// Conserva los parametros dinamicos (fase, intensidad, emision, fisura, LOD, tapas)
// que manejan PipeCoolantRun.gd, PipeRun.gd y LeakFissureVisual.gd.

uniform vec4 base_color : hint_color = vec4(0.01, 0.15, 0.35, 1.0);
uniform vec4 flow_edge_color : hint_color = vec4(0.01, 0.587, 1.0, 1.0);
uniform vec4 flow_color : hint_color = vec4(0.7, 0.95, 1.0, 1.0);
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
uniform bool use_local_axis = true;
uniform bool use_baked_axis = false;

uniform float flow_phase = 0.0;
uniform float emission_strength = 1.0;
uniform float flow_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float pipe_alpha = 0.88;
uniform float metallic_amount = 0.5;
uniform float roughness_amount = 0.35;
uniform float flow_noise_amount : hint_range(0.0, 0.4) = 0.12;

uniform float noise_scale = 1.6;
uniform bool hide_caps = true;
uniform float base_glow = 0.035;

uniform vec3 fissure_center = vec3(0.0);
uniform float fissure_radius = 0.35;
uniform float fissure_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float crack_scale = 2.5;

// Superficie tipo agua. voronoi_scale alto = celdas chicas (18 en el original 2D).
uniform float voronoi_scale = 14.0;
uniform float water_noise_scale = 0.21;
uniform float water_speed = 0.7;
uniform float axial_stretch = 0.55;

varying vec3 pipe_axis;

const float LOD_NEAR = 9.0;
const float LOD_FAR = 28.0;


vec2 random2(vec2 pos) {
	return fract(sin(vec2(dot(pos, vec2(12.9898, 78.233)), dot(pos, vec2(-148.998, -65.233)))) * 43758.5453);
}

float value_noise2(vec2 pos) {
	vec2 p = floor(pos);
	vec2 f = fract(pos);
	float v00 = random2(p).x;
	float v10 = random2(p + vec2(1.0, 0.0)).x;
	float v01 = random2(p + vec2(0.0, 1.0)).x;
	float v11 = random2(p + vec2(1.0, 1.0)).x;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(v00, v10, u.x), mix(v01, v11, u.x), u.y);
}

float voronoi2(vec2 v) {
	vec2 v_floor = floor(v);
	vec2 v_fract = fract(v);
	float min_dist = 2.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 p = random2(v_floor + n);
			min_dist = min(min_dist, distance(v_fract, p + n));
		}
	}
	return min_dist;
}

void vertex() {
	if (use_baked_axis) {
		pipe_axis = normalize(COLOR.rgb * 2.0 - 1.0);
	} else {
		pipe_axis = normalize((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}

void fragment() {
	float distance_to_camera = length(VERTEX);
	vec3 world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = use_local_axis ? pipe_axis : normalize(flow_dir);
	float far_lod = smoothstep(LOD_NEAR, LOD_FAR, distance_to_camera);

	vec3 world_normal = normalize((CAMERA_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (hide_caps && abs(dot(world_normal, axis)) > 0.8) {
		discard;
	}

	float phase = flow_phase;
	if (phase == 0.0) {
		phase = TIME * water_speed;
	}

	// Plano 2D continuo en mundo: eje del cano x una tangente estable. No usa UV, asi
	// que no se parte en cada union; el look es el del agua 2D original.
	float along = dot(world_pos, axis);
	vec3 ref = vec3(0.0042, 1.0, 0.0071);
	vec3 tangent = cross(axis, ref);
	if (dot(tangent, tangent) < 0.001) {
		tangent = cross(axis, vec3(1.0, 0.0, 0.0));
	}
	tangent = normalize(tangent);
	vec2 uv = vec2(dot(world_pos, tangent), along * axial_stretch) * noise_scale;
	// El shader viejo restaba axis * flow_phase: el patron corre HACIA flow_dir
	// (en los risers, hacia arriba). Sumar phase invertia el caudal.
	float scroll = phase * 2.2;
	vec2 noise_uv = uv - vec2(0.0, scroll) * 0.1;

	// Distorsion fbm de 8 octavas: es lo que retuerce las celdas y les da el aspecto
	// organico. De lejos se cortan las 4 mas finas (no se leen y cuestan).
	float warp = value_noise2(noise_uv * 5.45432) * 0.5
		+ value_noise2(noise_uv * 15.754824) * 0.25
		+ value_noise2(noise_uv * 35.4274729) * 0.125
		+ value_noise2(noise_uv * 95.65347829) * 0.0625;
	if (far_lod < 0.99) {
		warp += value_noise2(noise_uv * 285.528934) * 0.03125
			+ value_noise2(noise_uv * 585.495328) * 0.015625
			+ value_noise2(noise_uv * 880.553426553) * 0.0078125
			+ value_noise2(noise_uv * 2080.5483905843) * 0.00390625;
	}
	uv.x += warp * (water_noise_scale + flow_noise_amount);

	vec2 v1 = uv * voronoi_scale + vec2(100.0, 0.0) - vec2(0.0, scroll);
	float f = voronoi2(v1) * 1.1;
	if (far_lod < 0.85) {
		vec2 v2 = uv * voronoi_scale + vec2(-100.0, 0.0) - vec2(0.0, scroll * 0.83);
		float pulse = sin(scroll * 0.758) * 0.5 + 0.5;
		f = mix(f, voronoi2(v2) * 1.1, pulse);
	}

	// Paleta anime: espuma casi blanca, piscina azul electrico. 1-f^3.
	float water = clamp(1.0 - f * f * f, 0.0, 1.0);
	float foam = 1.0 - water;

	float active = clamp(flow_intensity, 0.0, 1.0);
	vec3 idle_albedo = base_color.rgb * 0.34;
	vec3 foam_color = mix(vec3(1.0), flow_color.rgb, 0.15);
	vec3 water_color = flow_edge_color.rgb;
	vec3 flowing_albedo = mix(foam_color, water_color, water);
	vec3 current_albedo = mix(idle_albedo, flowing_albedo, active);
	float far_readability = mix(0.9, 1.15, far_lod);
	vec3 current_emission = mix(foam_color, water_color, water)
		* active * (base_glow + foam * emission_strength * far_readability);

	if (fissure_intensity > 0.001) {
		float fissure_distance = distance(world_pos, fissure_center);
		float fissure_mask = (1.0 - smoothstep(fissure_radius * 0.45, fissure_radius, fissure_distance)) * fissure_intensity;
		current_albedo = mix(current_albedo, vec3(0.01, 0.04, 0.08), fissure_mask);
		current_emission *= 1.0 - fissure_mask * 0.9;
	}

	ALBEDO = current_albedo;
	EMISSION = current_emission;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
