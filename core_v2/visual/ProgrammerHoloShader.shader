shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform vec4 holo_color : hint_color = vec4(0.06, 0.95, 0.9, 0.28);
uniform float emission_energy : hint_range(0.0, 6.0) = 1.35;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

uniform float scanline_density : hint_range(1.0, 220.0) = 72.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.72;
uniform float fresnel_power : hint_range(0.1, 10.0) = 2.2;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 1.1;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.28;
uniform float glitch_line_density : hint_range(1.0, 80.0) = 30.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.18;
uniform float alpha_floor : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float triplanar_scanline(vec2 p, float density) {
	float line_main = abs(fract(p.x * density) - 0.5);
	float line_sub = abs(fract((p.y * 0.63 + p.x * 0.17) * density * 0.6) - 0.5);
	float thin_main = 1.0 - smoothstep(0.08, 0.32, line_main);
	float thin_sub = 1.0 - smoothstep(0.18, 0.46, line_sub);
	return clamp(thin_main + thin_sub * 0.55, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fresnel = pow(1.0 - max(dot(n, v), 0.0), fresnel_power) * fresnel_strength;
	float normal_lobe = 0.5 + 0.5 * n.y;

	vec3 world_n = normalize(v_world_normal);
	vec3 blend = pow(abs(world_n), vec3(2.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);

	float tri_density = scanline_density * 0.12;
	float line_x = triplanar_scanline(v_world_pos.yz, tri_density);
	float line_y = triplanar_scanline(v_world_pos.xz, tri_density);
	float line_z = triplanar_scanline(v_world_pos.xy, tri_density);
	float line_mask = line_x * blend.x + line_y * blend.y + line_z * blend.z;

	float scanline_dark = mix(1.0, 0.10, scanline_strength);
	float scanline_light = mix(1.0, 1.45, scanline_strength);
	float scanline_alpha = mix(scanline_dark, 1.0, line_mask);
	float scanline_emission = mix(0.72, scanline_light, line_mask);

	float band = floor((v_world_pos.y + v_world_pos.x * 0.22) * glitch_line_density * 0.45);
	float block = floor(v_world_pos.z * 52.0);
	float glitch_seed = hash(vec2(band, block));
	float glitch_band = step(1.0 - glitch_intensity * 0.75, glitch_seed);
	float glitch_noise = (hash(vec2(block + 11.0, band + 3.0)) - 0.5) * 2.0;
	float glitch_color = 1.0 + glitch_band * (0.55 + 0.45 * glitch_noise) * glitch_intensity;
	float glitch_alpha = 1.0 - glitch_band * glitch_intensity * 0.22;
	float static_noise = (hash(v_world_pos.xz * 64.0) - 0.5) * 2.0;
	float noise_mod = 1.0 + static_noise * (noise_strength * 0.35);

	float body_alpha = holo_color.a * opacity * (0.08 + 0.28 * fresnel + 0.20 * normal_lobe);
	body_alpha *= scanline_alpha * glitch_alpha;
	body_alpha = clamp(body_alpha, alpha_floor, 1.0);

	vec3 holo = holo_color.rgb * emission_energy;
	vec3 lit_holo = holo * (0.35 + 0.25 * normal_lobe + fresnel * 0.85);
	ALBEDO = lit_holo * scanline_emission * glitch_color * noise_mod;
	ALPHA = body_alpha;
}
