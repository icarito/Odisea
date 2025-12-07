shader_type canvas_item;

uniform vec4 trail_color : hint_color = vec4(0.2,0.8,1,0.7);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	COLOR = trail_color;
	COLOR.rgb += glow_strength * 0.5;
}
