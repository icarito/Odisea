shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// Sci-Fi Airlock Hull Panels (GLES2 compatible)
// Procedural paneled metal with glowing seams, rivets, and depth illusion

uniform vec4 panel_color : hint_color = vec4(0.22, 0.25, 0.28, 1.0);
uniform vec4 seam_color : hint_color = vec4(0.15, 0.55, 0.85, 1.0);
uniform float panel_scale : hint_range(1.0, 20.0) = 4.0;
uniform float seam_width : hint_range(0.005, 0.08) = 0.025;
uniform float seam_emission : hint_range(0.0, 5.0) = 1.2;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.75;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.35;
uniform float rivet_radius : hint_range(0.0, 0.06) = 0.025;
uniform float rivet_spacing : hint_range(0.05, 0.3) = 0.12;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.3;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Panel grid with offset rows (brick pattern)
vec2 panel_cell(vec2 uv, float scale) {
	vec2 scaled = uv * scale;
	float row = floor(scaled.y);
	// Offset every other row by half
	scaled.x += mod(row, 2.0) * 0.5;
	return fract(scaled);
}

vec2 panel_id(vec2 uv, float scale) {
	vec2 scaled = uv * scale;
	float row = floor(scaled.y);
	scaled.x += mod(row, 2.0) * 0.5;
	return floor(scaled);
}

void fragment() {
	vec2 uv = UV;
	vec2 cell = panel_cell(uv, panel_scale);
	vec2 id = panel_id(uv, panel_scale);

	// --- Panel seam lines ---
	float seam_x = smoothstep(seam_width, seam_width * 0.3, cell.x) +
	               smoothstep(1.0 - seam_width, 1.0 - seam_width * 0.3, cell.x);
	float seam_y = smoothstep(seam_width, seam_width * 0.3, cell.y) +
	               smoothstep(1.0 - seam_width, 1.0 - seam_width * 0.3, cell.y);
	float seam = clamp(seam_x + seam_y, 0.0, 1.0);

	// --- Rivet dots: unrolled 2x2 corners to avoid GPU loop overhead ---
	float riv_lo = rivet_spacing;
	float riv_hi = 1.0 - rivet_spacing;
	float rr = rivet_radius;
	float d0 = length(cell - vec2(riv_lo, riv_lo));
	float d1 = length(cell - vec2(riv_hi, riv_lo));
	float d2 = length(cell - vec2(riv_lo, riv_hi));
	float d3 = length(cell - vec2(riv_hi, riv_hi));
	float rivets = clamp(
		smoothstep(rr, rr * 0.5, d0) +
		smoothstep(rr, rr * 0.5, d1) +
		smoothstep(rr, rr * 0.5, d2) +
		smoothstep(rr, rr * 0.5, d3),
		0.0, 1.0);

	// --- Per-panel color variation (subtle) ---
	float panel_var = hash(id) * 0.12 - 0.06; // +/-6% brightness

	// --- Wear: single-octave cheap approximation instead of two noise calls ---
	float wear = hash(floor(uv * 20.0)) * wear_amount;

	// --- Depth illusion via albedo shading (GLES2 friendly, no dFdx/dFdy) ---
	float edge_x = smoothstep(0.0, 0.1, cell.x) * smoothstep(1.0, 0.9, cell.x);
	float edge_y = smoothstep(0.0, 0.1, cell.y) * smoothstep(1.0, 0.9, cell.y);
	float edge_shadow = edge_x * edge_y;

	// --- Final color ---
	vec3 base = panel_color.rgb + panel_var;
	base *= mix(0.65, 1.0, edge_shadow);
	base = mix(base, base * 0.4, seam * 0.6);
	base = mix(base, base * 1.4, rivets * 0.5);
	base = mix(base, base * 0.7, wear);

	ALBEDO = base;
	METALLIC = 0.0;
	ROUGHNESS = mix(roughness_value, roughness_value + 0.25, wear);

	// Seam glow
	EMISSION = seam_color.rgb * seam * seam_emission * intensity;
}
