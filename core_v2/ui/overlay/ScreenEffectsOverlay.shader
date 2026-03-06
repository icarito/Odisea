shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 overlay_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float death_progress : hint_range(0.0, 1.0) = 0.0;
uniform float death_curve : hint_range(0.0, 0.3) = 0.14;
uniform float death_feather : hint_range(0.001, 0.08) = 0.02;
uniform float cinematic_progress : hint_range(0.0, 1.0) = 0.0;
uniform float cinematic_bar_height : hint_range(0.0, 0.35) = 0.11;

float edge_mask(float threshold, float feather, float position) {
	return 1.0 - smoothstep(threshold - feather, threshold + feather, position);
}

void fragment() {
	vec2 uv = UV;
	float center_weight = 1.0 - pow(abs((uv.x * 2.0) - 1.0), 2.0);
	float death_half = death_progress * 0.5;
	float death_curve_offset = death_curve * center_weight;
	float upper_lid = death_half + death_curve_offset;
	float lower_lid = 1.0 - upper_lid;

	float death_top = edge_mask(upper_lid, death_feather, uv.y);
	float death_bottom = smoothstep(lower_lid - death_feather, lower_lid + death_feather, uv.y);
	float death_mask = max(death_top, death_bottom);

	float bar_height = cinematic_progress * cinematic_bar_height;
	float cinematic_top = edge_mask(bar_height, 0.0015, uv.y);
	float cinematic_bottom = smoothstep((1.0 - bar_height) - 0.0015, (1.0 - bar_height) + 0.0015, uv.y);
	float cinematic_mask = max(cinematic_top, cinematic_bottom);

	float alpha = clamp(max(death_mask, cinematic_mask), 0.0, 1.0);
	COLOR = vec4(overlay_color.rgb, overlay_color.a * alpha);
}
