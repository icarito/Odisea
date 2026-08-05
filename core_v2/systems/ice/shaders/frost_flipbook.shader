shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D smoke_atlas : hint_albedo;
uniform int atlas_columns = 8;
uniform int atlas_rows = 8;
uniform float frames_per_second = 16.0;
uniform vec2 atlas_size = vec2(1024.0, 1024.0);
uniform float frame_padding_px = 1.5;

varying vec4 instance_color;
varying float particle_age;
varying float particle_frame_time;

void vertex() {
	instance_color = COLOR;
	particle_age = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	particle_frame_time = INSTANCE_CUSTOM.z;
	MODELVIEW_MATRIX = INV_CAMERA_MATRIX * mat4(
		CAMERA_MATRIX[0], CAMERA_MATRIX[1], CAMERA_MATRIX[2], WORLD_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(WORLD_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(WORLD_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(WORLD_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	float columns = max(float(atlas_columns), 1.0);
	float rows = max(float(atlas_rows), 1.0);
	float frame = mod(floor(max(particle_frame_time, 0.0) * max(frames_per_second, 0.001)), columns * rows);
	vec2 frame_size = vec2(1.0 / columns, 1.0 / rows);
	vec2 padding = frame_padding_px * vec2(columns, rows) / atlas_size;
	vec2 local_uv = clamp(UV, padding, vec2(1.0) - padding);
	vec2 atlas_uv = local_uv * frame_size + vec2(mod(frame, columns), floor(frame / columns)) * frame_size;
	vec4 tex = texture(smoke_atlas, atlas_uv);
	float age_fade = smoothstep(0.0, 0.08, particle_age) * (1.0 - smoothstep(0.72, 1.0, particle_age));
	// El atlas aporta solo la silueta. El vapor mantiene color blanco y alpha suave,
	// sin ordered dither ni corte binario.
	ALBEDO = instance_color.rgb;
	EMISSION = instance_color.rgb * 0.035;
	ALPHA = tex.a * instance_color.a * age_fade * 0.82;
}
