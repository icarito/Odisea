shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : hint_albedo;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D roughness_texture : hint_white;
uniform sampler2D ao_texture : hint_white;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec4 base_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 frost_color : hint_color = vec4(0.62, 0.88, 1.0, 1.0);
uniform vec4 crack_color : hint_color = vec4(0.9, 0.98, 1.0, 1.0);
uniform float base_metallic : hint_range(0.0, 1.0) = 0.22;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float crack_density : hint_range(2.0, 32.0) = 11.0;
uniform float freeze_min_y : hint_range(-3.0, 3.0) = -1.05;
uniform float freeze_max_y : hint_range(-3.0, 3.0) = 1.25;
uniform float freeze_front_softness : hint_range(0.01, 0.5) = 0.14;
// Auto-iluminacion del traje: mantiene a Elias legible sin depender de las luces de la
// escena. Hace falta porque el presupuesto de luces de movil (MobileLightBudget) achica el
// alcance de todas, y en los tramos oscuros el personaje se perdia contra el fondo. Suma
// sobre el ALBEDO ya calculado, asi que respeta el tinte de escarcha y de dano.
uniform float self_illum : hint_range(0.0, 2.0) = 0.35;

varying vec3 world_position;
varying float local_y;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_y = VERTEX.y;
}

void fragment() {
	vec2 uv = UV * crack_density;
	float n0 = noise(uv + vec2(TIME * 0.1, -TIME * 0.06));
	float n1 = noise(uv * 1.93 + vec2(-4.2, 7.1));
	float crack_mask = smoothstep(0.68, 0.92, n0 * 0.62 + n1 * 0.38);
	float chip_mask = smoothstep(0.58, 0.9, noise(uv * 0.67 + vec2(12.0, -3.0)));
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.3);
	float vertical = clamp((local_y - freeze_min_y) / max(0.001, freeze_max_y - freeze_min_y), 0.0, 1.0);

	float active_damage = clamp(damage_amount, 0.0, 1.0);
	float freeze_band = 1.0 - smoothstep(active_damage - freeze_front_softness, active_damage + freeze_front_softness, vertical);
	float crack_intensity = crack_mask * freeze_band;
	float frost_intensity = chip_mask * freeze_band;
	float broad_frost = smoothstep(0.0, 1.0, freeze_band) * 0.88;
	float pulse_mix = mix(0.18, 0.7, pulse);
	vec3 frozen_tint = mix(frost_color.rgb, crack_color.rgb, pulse_mix);

	vec4 tex_albedo = texture(albedo_texture, UV);
	float tex_roughness = texture(roughness_texture, UV).r;
	float tex_ao = texture(ao_texture, UV).r;

	vec3 base = tex_albedo.rgb * base_color.rgb;
	vec3 damaged = mix(base, frozen_tint, crack_intensity * 0.9 + frost_intensity * 0.45);
	damaged = mix(damaged, frost_color.rgb, broad_frost);
	damaged = mix(damaged, vec3(1.0), broad_frost * 0.42);
	damaged = mix(damaged, crack_color.rgb, edge * freeze_band * 0.28);

	ALBEDO = damaged;
	METALLIC = base_metallic;
	ROUGHNESS = mix(base_roughness * tex_roughness, 1.0, freeze_band * 0.92);
	SPECULAR = mix(0.22, 0.6, freeze_band * 0.5);
	AO = tex_ao;
	AO_LIGHT_AFFECT = 0.0;
	NORMALMAP = texture(normal_texture, UV).rgb;
	NORMALMAP_DEPTH = normal_scale;
	EMISSION = damaged * self_illum
		+ frozen_tint * (crack_intensity * pulse_mix * 0.85 + edge * freeze_band * (0.16 + pulse_mix * 0.32));
}
