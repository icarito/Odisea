shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass;

// Flujo de criocoolant legible: ruido de valor simple, continuo entre tramos.
// Lejos se quita solo el microdetalle, nunca el patron completo.

uniform vec4 base_color : hint_color = vec4(0.06, 0.22, 0.35, 1.0);
uniform vec4 flow_edge_color : hint_color = vec4(0.08, 0.45, 0.62, 1.0);
uniform vec4 flow_color : hint_color = vec4(0.35, 0.92, 0.98, 1.0);
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

// Escala del patron de ruido en metros.
uniform float noise_scale = 1.6;
uniform bool hide_caps = true;
uniform float base_glow = 0.035;

// La fisura sigue siendo una zona oscura sin el coste del patron procedural anterior.
uniform vec3 fissure_center = vec3(0.0);
uniform float fissure_radius = 0.35;
uniform float fissure_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float crack_scale = 2.5;

varying vec3 pipe_axis;

const float LOD_NEAR = 9.0;
const float LOD_FAR = 28.0;


float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}


float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(cell + vec3(0.0, 0.0, 0.0)), hash(cell + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash(cell + vec3(0.0, 1.0, 0.0)), hash(cell + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash(cell + vec3(0.0, 0.0, 1.0)), hash(cell + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash(cell + vec3(0.0, 1.0, 1.0)), hash(cell + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
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
	vec3 flow_coord = world_pos * noise_scale - axis * flow_phase;
	float broad_noise = value_noise(flow_coord);
	float detail_noise = value_noise(flow_coord * 2.1 + vec3(7.0, 3.0, 11.0));
	float flow_noise = mix(broad_noise, mix(broad_noise, detail_noise, flow_noise_amount), 1.0 - far_lod);
	float flow_band = smoothstep(0.38, 0.72, flow_noise);

	float active = clamp(flow_intensity, 0.0, 1.0);
	vec3 idle_albedo = base_color.rgb * 0.34;
	// El borde azul profundo y el nucleo cian claro dan volumen a cada veta.
	vec3 flowing_albedo = mix(flow_edge_color.rgb, flow_color.rgb, flow_band) * (0.62 + flow_band * 0.2);
	vec3 current_albedo = mix(idle_albedo, flowing_albedo, active);
	float far_readability = mix(0.9, 1.15, far_lod);
	vec3 flow_emission_color = mix(flow_edge_color.rgb, flow_color.rgb, flow_band);
	vec3 current_emission = flow_emission_color * active * (base_glow + flow_band * emission_strength * far_readability);

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
