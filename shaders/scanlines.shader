shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform float scan_speed : hint_range(0.1, 4.0) = 1.0;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 highlight_color : hint_color = vec4(1.0, 1.0, 0.3, 0.35);

void fragment() {
	// Horizontal animated scanlines over the object surface.
	float line = step(0.5, fract(UV.y * 120.0 + TIME * scan_speed));
	float scan = line * scan_strength;

	// Rim light to keep readable silhouette.
	float ndotv = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - ndotv, 2.0);

	float glow = clamp(scan + rim * 0.6, 0.0, 1.0);
	ALBEDO = highlight_color.rgb;
	ALPHA = glow * highlight_color.a;
}
