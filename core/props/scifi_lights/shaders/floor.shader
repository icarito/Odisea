shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 grid_color : hint_color = vec4(0.1, 0.4, 0.8, 1.0);
uniform vec4 base_color : hint_color = vec4(0.02, 0.02, 0.03, 1.0);
uniform float grid_scale : hint_range(1.0, 40.0) = 10.0;
uniform float grid_width : hint_range(0.01, 0.2) = 0.04;
uniform float emission_strength : hint_range(0.0, 5.0) = 1.5;
uniform float reflectivity : hint_range(0.0, 1.0) = 0.85;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 grid_uv = UV * grid_scale;
	vec2 grid_frac = fract(grid_uv);
	
	// Grid lines
	float line_x = smoothstep(grid_width, grid_width * 0.5, grid_frac.x) + 
	               smoothstep(1.0 - grid_width, 1.0 - grid_width * 0.5, grid_frac.x);
	float line_y = smoothstep(grid_width, grid_width * 0.5, grid_frac.y) + 
	               smoothstep(1.0 - grid_width, 1.0 - grid_width * 0.5, grid_frac.y);
	float grid = clamp(line_x + line_y, 0.0, 1.0);
	
	// Reflective dark floor with glowing grid
	ALBEDO = base_color.rgb;
	METALLIC = reflectivity;
	ROUGHNESS = 0.1; // Very smooth for reflections
	SPECULAR = 0.8;
	
	// Grid emission
	EMISSION = grid_color.rgb * grid * emission_strength * intensity;
}
