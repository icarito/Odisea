shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, unshaded, shadows_disabled, ambient_light_disabled;

uniform sampler2D smoke_atlas : hint_albedo;
uniform int atlas_columns = 8;
uniform int atlas_rows = 8;
uniform float frames_per_second = 16.0;
uniform float alpha_multiplier = 1.35;
uniform float emission_strength = 0.12;
uniform float fire_emission_strength = 1.35;
uniform vec2 atlas_size = vec2(1024.0, 1024.0);
uniform float frame_padding_px = 1.5;

varying vec4 instance_color;
varying float particle_age;
varying float particle_fire_mix;
varying float particle_frame_time;

void vertex() {
	instance_color = COLOR;
	particle_age = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	particle_fire_mix = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	particle_frame_time = INSTANCE_CUSTOM.z;

	// Full billboard: align local XY with camera XY so gas reads well from above and below.
	MODELVIEW_MATRIX = INV_CAMERA_MATRIX * mat4(
		CAMERA_MATRIX[0],
		CAMERA_MATRIX[1],
		CAMERA_MATRIX[2],
		WORLD_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(WORLD_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(WORLD_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(WORLD_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

float bayer4(vec2 p) {
	vec2 q = floor(mod(p, 4.0));
	float x = q.x;
	float y = q.y;
	if (y < 0.5) {
		if (x < 0.5) return 0.03125;
		if (x < 1.5) return 0.53125;
		if (x < 2.5) return 0.15625;
		return 0.65625;
	}
	if (y < 1.5) {
		if (x < 0.5) return 0.78125;
		if (x < 1.5) return 0.28125;
		if (x < 2.5) return 0.90625;
		return 0.40625;
	}
	if (y < 2.5) {
		if (x < 0.5) return 0.21875;
		if (x < 1.5) return 0.71875;
		if (x < 2.5) return 0.09375;
		return 0.59375;
	}
	if (x < 0.5) return 0.96875;
	if (x < 1.5) return 0.46875;
	if (x < 2.5) return 0.84375;
	return 0.34375;
}

void fragment() {
	float columns = max(float(atlas_columns), 1.0);
	float rows = max(float(atlas_rows), 1.0);
	float total_frames = columns * rows;
	float frame = mod(floor(max(particle_frame_time, 0.0) * max(frames_per_second, 0.001)), total_frames);
	float frame_x = mod(frame, columns);
	float frame_y = floor(frame / columns);
	vec2 frame_size = vec2(1.0 / columns, 1.0 / rows);
	vec2 local_padding = frame_padding_px * vec2(columns, rows) / atlas_size;
	vec2 local_uv = clamp(UV, local_padding, vec2(1.0) - local_padding);
	vec2 atlas_uv = (local_uv * frame_size) + vec2(frame_x * frame_size.x, frame_y * frame_size.y);

	vec4 tex = texture(smoke_atlas, atlas_uv);
	vec4 modulated = tex * instance_color;
	float age_fade = smoothstep(0.0, 0.015, particle_age) * (1.0 - smoothstep(0.92, 1.0, particle_age));
	float alpha = modulated.a * alpha_multiplier * age_fade;

	ALBEDO = modulated.rgb;
	EMISSION = modulated.rgb * mix(emission_strength, fire_emission_strength, particle_fire_mix);
	
	// Ordered dither avoids Android/GLES2 precision artifacts from dot/fract noise.
	vec2 pos = FRAGCOORD.xy + floor(mod(TIME * 12.0, 4.0));
	float limit = bayer4(pos);
	if (alpha < limit) {
		discard;
	}
}
