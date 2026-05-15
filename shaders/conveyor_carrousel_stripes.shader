shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : hint_color = vec4(0.08, 0.09, 0.1, 1.0);
uniform vec4 color_b : hint_color = vec4(0.38, 0.34, 0.16, 1.0);
uniform float stripe_count = 20.0;
uniform float phase = 0.0;
uniform float fill = 0.4;
uniform float emission = 0.012;
uniform float softness = 0.08;
uniform float metalness = 0.18;
uniform float roughness = 0.84;
uniform float outer_radius = 3.0;
uniform float lane_inner_ratio = 0.58;
uniform float lane_outer_ratio = 0.94;
uniform float motion_dir = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float angle = atan(local_pos.z, local_pos.x) / 6.28318530718;
	float radius = length(local_pos.xz);
	float radius_norm = radius / max(outer_radius, 0.001);
	float lane_mask = smoothstep(lane_inner_ratio - 0.08, lane_inner_ratio + 0.03, radius_norm);
	lane_mask *= 1.0 - smoothstep(lane_outer_ratio - 0.04, lane_outer_ratio + 0.03, radius_norm);
	float track = fract((angle + (phase * motion_dir)) * stripe_count);
	float stripe = 1.0 - smoothstep(fill - softness, fill + softness, track);
	float motion_mask = lane_mask * stripe;

	vec3 base_col = mix(color_a.rgb * 0.88, color_a.rgb, lane_mask);
	vec3 col = mix(base_col, color_b.rgb, motion_mask);

	float inner_plate = 1.0 - smoothstep(lane_inner_ratio - 0.12, lane_inner_ratio + 0.02, radius_norm);
	col = mix(col, color_a.rgb * 0.86, inner_plate);

	ALBEDO = col;
	METALLIC = metalness;
	ROUGHNESS = roughness;
	EMISSION = color_b.rgb * motion_mask * emission;
}
