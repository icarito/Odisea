shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform vec4 color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform float falloff_exponent : hint_range(0.1, 5.0) = 2.0;

void fragment() {
	// Simple distance falloff along Z (assuming cone height is 1.0 in local space)
	// In Godot 3, vertex position in fragment is in view space.
	// We'll use the UV.y which usually maps to the height of primitive meshes.
	float falloff = pow(1.0 - UV.y, falloff_exponent);

	// Edge softening
	float edge = sin(UV.x * 3.14159); // Crude

	ALBEDO = color.rgb;
	ALPHA = color.a * falloff * alpha_multiplier * 0.3;
}
