shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_back, unshaded, shadows_disabled;

uniform sampler2D albedo_texture : hint_albedo;
uniform vec4 base_color : hint_color = vec4(0.22, 0.86, 1.0, 1.0);
uniform float albedo_mix : hint_range(0.0, 1.0) = 0.0;
uniform float emission_energy : hint_range(0.0, 8.0) = 2.4;
uniform float alpha_scale : hint_range(0.0, 2.0) = 0.85;
uniform float min_alpha : hint_range(0.0, 1.0) = 0.02;

uniform float scanline_density : hint_range(10.0, 260.0) = 145.0;
uniform float scanline_speed : hint_range(0.0, 10.0) = 1.4;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.72;

uniform float flicker_speed : hint_range(0.0, 40.0) = 10.0;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.08;

uniform float edge_power : hint_range(0.1, 8.0) = 2.2;
uniform float edge_strength : hint_range(0.0, 4.0) = 1.7;

uniform float noise_scale : hint_range(0.1, 40.0) = 8.0;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.015;
uniform float chroma_shift : hint_range(0.0, 0.03) = 0.004;

uniform float glitch_strength : hint_range(0.0, 1.0) = 0.42;
uniform float glitch_density : hint_range(1.0, 120.0) = 46.0;
uniform float glitch_snap_rate : hint_range(1.0, 30.0) = 15.0;
uniform float background_mix : hint_range(0.0, 1.0) = 0.16;

varying vec3 v_world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	v_world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), edge_power) * edge_strength;

	vec2 noise_uv = v_world_pos.xz * noise_scale;
	float n1 = fbm(noise_uv + vec2(TIME * 0.9, TIME * 0.4));
	float n2 = fbm(v_world_pos.zy * noise_scale * 0.7 - vec2(TIME * 0.5, TIME * 0.8));
	vec2 noise_offset = (vec2(n1, n2) - vec2(0.5)) * distortion_strength;

	float time_snap = floor(TIME * glitch_snap_rate);
	float band_id = floor(v_world_pos.y * glitch_density);
	float glitch_chance = 0.98 - glitch_strength * 0.22;
	float glitch_gate = step(glitch_chance, hash(vec2(band_id, time_snap)));
	float glitch_shift = (hash(vec2(band_id, band_id + 19.0)) - 0.5) * glitch_strength * 0.06;
	glitch_shift += (hash(vec2(time_snap, band_id + 71.0)) - 0.5) * glitch_strength * 0.025;
	vec2 uv = UV + noise_offset + vec2(glitch_gate * glitch_shift, 0.0);

	float tex_a = texture(albedo_texture, uv).a;
	vec3 tex_rgb;
	tex_rgb.r = texture(albedo_texture, uv + vec2(chroma_shift, 0.0)).r;
	tex_rgb.g = texture(albedo_texture, uv).g;
	tex_rgb.b = texture(albedo_texture, uv - vec2(chroma_shift, 0.0)).b;

	vec3 body_color = mix(vec3(1.0), tex_rgb, albedo_mix) * base_color.rgb;
	float body_alpha = mix(1.0, tex_a, albedo_mix) * base_color.a * alpha_scale;

	float scanline = sin((v_world_pos.y + TIME * scanline_speed) * scanline_density) * 0.5 + 0.5;
	float scanline_mask = mix(1.0 - scanline_strength, 1.0, scanline);

	float flicker_snap = floor(TIME * flicker_speed);
	float flicker_rand = hash(vec2(flicker_snap, 31.0));
	float flicker_pulse = step(0.08, flicker_rand);
	float flicker_mask = mix(1.0 - flicker_strength, 1.0, flicker_pulse);

	float grain = (hash(v_world_pos.xz * 64.0 + vec2(TIME * 2.0)) - 0.5) * 0.20;
	float noise_mask = 1.0 + grain * glitch_strength;

	vec3 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV + noise_offset * 0.5).rgb;
	vec3 holo_color = mix(body_color, screen_color, background_mix);
	vec3 core_color = holo_color * scanline_mask * flicker_mask * noise_mask;
	vec3 edge_color = base_color.rgb * (1.2 + glitch_gate * 0.8);

	ALBEDO = core_color * (0.32 + fresnel * 0.22);
	EMISSION = core_color * emission_energy + edge_color * fresnel * (1.5 + glitch_gate);

	float alpha = body_alpha * scanline_mask;
	alpha *= 1.0 - glitch_gate * glitch_strength * 0.25;
	alpha *= 0.86 + 0.14 * flicker_mask;
	alpha += fresnel * 0.12;
	ALPHA = clamp(alpha, min_alpha, 1.0);
}
