shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D hull_tex : hint_albedo;
uniform sampler2D grid_tex : hint_albedo;
uniform sampler2D lights_tex : hint_albedo;

uniform vec4 hull_color : hint_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 grid_color : hint_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec4 lights_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float parallax_grid = 0.02;
uniform float parallax_lights = 0.04;
uniform float parallax_strength = 1.0;
uniform vec2 uv_scale = vec2(12.0, 4.0);
uniform float brightness = 1.0;
uniform int debug_mode = 0;

void fragment() {
	vec2 base_uv = UV * uv_scale;
	vec2 view_offset = VIEW.xy / max(abs(VIEW.z), 0.15);
	
	vec4 hull = texture(hull_tex, base_uv) * hull_color;
	vec2 grid_uv = base_uv + view_offset * parallax_grid * parallax_strength;
	vec4 grid = texture(grid_tex, grid_uv) * grid_color;
	vec2 lights_uv = base_uv + view_offset * parallax_lights * parallax_strength;
	vec4 lights = texture(lights_tex, lights_uv) * lights_color;
	
	vec3 final_color = hull.rgb;
	final_color = mix(final_color, grid.rgb, grid.a);
	final_color += lights.rgb * lights.a;

	if (debug_mode == 1) {
		final_color = hull.rgb;
	} else if (debug_mode == 2) {
		final_color = grid.rgb * max(grid.a, 0.12);
	} else if (debug_mode == 3) {
		final_color = lights.rgb * max(lights.a, 0.12);
	} else if (debug_mode == 4) {
		final_color = vec3(fract(base_uv.x), fract(base_uv.y), 0.25);
	}
	
	ALBEDO = final_color * brightness;
}
