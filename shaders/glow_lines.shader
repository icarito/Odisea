shader_type canvas_item;

uniform float line_speed : hint_range(0.1, 2.0) = 0.7;
uniform vec4 glow_color : hint_color = vec4(0.8,1.0,1.0,1.0);

void fragment() {
	float lines = abs(sin(UV.y * 40.0 + TIME * line_speed));
	COLOR = mix(COLOR, glow_color, lines * 0.7);
}
