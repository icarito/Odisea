shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert, specular_schlick_ggx;

// Android/GLES2 fallback. It keeps the progressive frozen surface but avoids
// SCREEN_TEXTURE and the multi-octave hash shader that fails on some Adreno drivers.
uniform vec4 albedo : hint_color = vec4(0.42, 0.78, 1.0, 0.48);
uniform vec4 deep_color : hint_color = vec4(0.03, 0.19, 0.42, 1.0);
uniform float ice_scale : hint_range(0.05, 3.0) = 0.32;
uniform float opacity : hint_range(0.0, 1.0) = 0.46;
uniform float freeze_progress : hint_range(0.0, 1.0) = 0.0;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.36;
uniform float emission_boost : hint_range(0.0, 6.0) = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_position.xz * ice_scale;
	float broad = sin(p.x * 1.7 + p.y * 1.1) * sin(p.y * 2.3 - p.x * 0.8);
	float fine = sin(p.x * 5.1 - p.y * 3.7);
	float detail = broad * 0.35 + fine * 0.12 + 0.5;
	float frost = smoothstep(0.78 - freeze_progress * 0.48, 0.92 - freeze_progress * 0.38, detail);
	float crack = smoothstep(0.94, 0.985, abs(fine)) * crack_strength;
	vec3 ice_color = mix(deep_color.rgb, albedo.rgb, clamp(detail, 0.0, 1.0));
	ice_color = mix(ice_color, vec3(0.86, 0.94, 1.0), frost * (0.28 + freeze_progress * 0.5));

	ALBEDO = ice_color;
	ROUGHNESS = mix(0.24, 0.82, freeze_progress);
	SPECULAR = mix(0.75, 0.35, freeze_progress);
	EMISSION = albedo.rgb * crack * 0.025 * emission_boost;
	ALPHA = clamp(opacity + frost * 0.12, 0.28, 0.82);
}
