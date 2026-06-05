shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Sci-Fi Grated Metal Floor with subtle underglow
// Diamond-plate / tread pattern with emissive accent lines

uniform vec4 base_color : hint_color = vec4(0.06, 0.07, 0.08, 1.0);
uniform vec4 accent_color : hint_color = vec4(0.9, 0.5, 0.05, 1.0);
uniform float grid_scale : hint_range(2.0, 30.0) = 12.0;
uniform float line_width : hint_range(0.01, 0.1) = 0.03;
uniform float accent_emission : hint_range(0.0, 3.0) = 0.8;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.25;
uniform float tread_depth : hint_range(0.0, 1.0) = 0.6;
uniform float stripe_width : hint_range(0.0, 0.5) = 0.12;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV * grid_scale;
	vec2 cell = fract(uv);

	// Diamond-plate tread pattern
	float diamond = abs(cell.x - 0.5) + abs(cell.y - 0.5);
	float tread = smoothstep(0.45, 0.42, diamond);

	// Grid lines (thin)
	float gx = smoothstep(line_width, line_width * 0.3, cell.x) +
	           smoothstep(1.0 - line_width, 1.0 - line_width * 0.3, cell.x);
	float gy = smoothstep(line_width, line_width * 0.3, cell.y) +
	           smoothstep(1.0 - line_width, 1.0 - line_width * 0.3, cell.y);
	float grid = clamp(gx + gy, 0.0, 1.0);

	// Warning stripes along edges (UV.x near 0 or 1 = edges of floor)
	float stripe_uv = fract(UV.y * 8.0 + UV.x * 8.0);
	float stripe = smoothstep(0.45, 0.5, stripe_uv) * smoothstep(0.95, 0.9, stripe_uv);
	
	float edge_mask = 0.0;
	if (stripe_width > 0.49) {
		edge_mask = 1.0;
	} else {
		edge_mask = smoothstep(stripe_width, stripe_width - 0.07, UV.x) + smoothstep(1.0 - stripe_width, 1.0 - stripe_width + 0.07, UV.x);
	}
	edge_mask = clamp(edge_mask, 0.0, 1.0);

	// Color
	vec3 color = base_color.rgb;
	color = mix(color, color * 1.2, tread * tread_depth);
	color = mix(color, color * 0.7, grid * 0.3);

	// Warning stripe overlay
	vec3 stripe_color = mix(color, accent_color.rgb * 0.8, stripe * edge_mask * 0.6);
	color = stripe_color;

	ALBEDO = color;
	METALLIC = metallic_value;
	ROUGHNESS = mix(roughness_value, roughness_value + 0.15, tread);
	SPECULAR = 0.7;

	// Subtle accent line emission
	EMISSION = accent_color.rgb * grid * accent_emission * 0.15;
	// Warning stripe glow at edges
	EMISSION += accent_color.rgb * stripe * edge_mask * accent_emission * 0.4;
}
