shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled, unshaded, shadows_disabled;

uniform vec4 frost_color : hint_color = vec4(0.82, 0.94, 1.0, 0.56);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float pattern_seed = 0.0;
uniform float ice_height_world = 0.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.34;
uniform float tendril_mode : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32 + pattern_seed);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), local.x), local.y);
}

void fragment() {
	if (world_position.y <= ice_height_world + 0.025) {
		discard;
	}
	vec2 centered = UV * 2.0 - 1.0;
	float irregular = noise(UV * 5.0 + pattern_seed) * 0.34 + noise(UV * 11.0 - pattern_seed) * 0.16;
	float edge = 1.0 - smoothstep(0.48 + irregular, 0.92 + irregular, length(centered));
	if (tendril_mode > 0.5) {
		float bend = sin(centered.y * 3.2 + pattern_seed * 1.7) * 0.12;
		bend += sin(centered.y * 7.1 - pattern_seed) * 0.045;
		float width = 0.105 + noise(vec2(centered.y * 3.0, pattern_seed)) * 0.085;
		float trunk = 1.0 - smoothstep(width, width + 0.065, abs(centered.x - bend));
		float branch_a_line = abs(centered.x - bend - (centered.y + 0.18) * 0.62);
		float branch_b_line = abs(centered.x - bend + (centered.y - 0.22) * 0.74);
		float branch_a_gate = smoothstep(-0.72, -0.38, centered.y) * (1.0 - smoothstep(0.18, 0.52, centered.y));
		float branch_b_gate = smoothstep(-0.42, -0.08, centered.y) * (1.0 - smoothstep(0.48, 0.78, centered.y));
		float branch_a = (1.0 - smoothstep(0.055, 0.13, branch_a_line)) * branch_a_gate;
		float branch_b = (1.0 - smoothstep(0.05, 0.12, branch_b_line)) * branch_b_gate;
		float vascular = max(trunk, max(branch_a, branch_b));
		edge = vascular * (0.72 + irregular * 0.42);
	}
	float veins = smoothstep(0.68, 0.9, noise(UV * 14.0 + vec2(pattern_seed, -pattern_seed)));
	ALBEDO = mix(frost_color.rgb * 0.72, vec3(0.94, 0.985, 1.0), veins * 0.55);
	EMISSION = frost_color.rgb * veins * 0.025;
	ALPHA = edge * frost_color.a * opacity;
	ALPHA_SCISSOR = alpha_scissor_threshold;
}
