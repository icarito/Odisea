shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 base_color : hint_color = vec4(0.08, 0.09, 0.1, 1.0);
uniform vec4 move_color : hint_color = vec4(0.92, 0.78, 0.26, 1.0);
uniform float phase = 0.0;
uniform float tiling = 18.0;
uniform float fill = 0.42;
uniform float softness = 0.12;
uniform float emission = 0.75;
uniform float inner_radius = 2.35;
uniform float outer_radius = 2.7;
uniform float motion_dir = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float radius = length(local_pos.xz);
	float band_mask = smoothstep(inner_radius - 0.05, inner_radius + 0.02, radius);
	band_mask *= 1.0 - smoothstep(outer_radius - 0.02, outer_radius + 0.05, radius);

	float angle = atan(local_pos.z, local_pos.x) / 6.28318530718;
	float radial_t = clamp((radius - inner_radius) / max(outer_radius - inner_radius, 0.001), 0.0, 1.0);
	float center_fade = smoothstep(0.05, 0.28, radial_t) * (1.0 - smoothstep(0.72, 0.95, radial_t));
	float track = fract(angle * tiling + phase * motion_dir);
	float dash = 1.0 - smoothstep(fill - softness, fill + softness, track);
	float motion = band_mask * center_fade * dash;
	vec3 col = mix(base_color.rgb, move_color.rgb, motion);
	ALBEDO = col;
	EMISSION = move_color.rgb * motion * emission;
}
