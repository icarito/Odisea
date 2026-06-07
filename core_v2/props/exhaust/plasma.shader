shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

uniform sampler2D flipbook_tex : hint_albedo;
uniform int columns = 8;
uniform int rows = 8;
uniform float animation_speed = 12.0;
uniform vec4 plasma_color : hint_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform float emission_intensity = 2.0;
uniform float distortion_strength = 0.02;
uniform float pulse_factor = 1.0;

void fragment() {
	float t = TIME;

	// Organic distortion
	vec2 ripple = vec2(
		sin(UV.y * 20.0 + t * 4.0) * 0.5 + 0.5,
		cos(UV.x * 20.0 + t * 4.0) * 0.5 + 0.5
	);

	vec2 distorted_uv = UV + (ripple - 0.5) * distortion_strength;

	// Flipbook calculation
	float total_frames = float(columns * rows);
	float frame = mod(floor(t * animation_speed), total_frames);
	vec2 frame_size = vec2(1.0 / float(columns), 1.0 / float(rows));
	vec2 frame_offset = vec2(
		mod(frame, float(columns)) * frame_size.x,
		floor(frame / float(columns)) * frame_size.y
	);

	vec2 final_uv = frame_offset + clamp(distorted_uv, 0.0, 1.0) * frame_size;

	vec4 tex = texture(flipbook_tex, final_uv);

	// Apply color and intensity
	vec3 color = plasma_color.rgb * tex.rgb * emission_intensity * pulse_factor;
	float alpha = tex.a * plasma_color.a * pulse_factor;

	ALBEDO = color;
	ALPHA = alpha;
}
