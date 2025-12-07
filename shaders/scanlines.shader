shader_type canvas_item;

uniform float scan_speed : hint_range(0.1, 2.0) = 1.0;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	float scan = step(0.5, fract(UV.y * 120.0 + TIME * scan_speed));
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * 0.7, scan * scan_strength);
}
