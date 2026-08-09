shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert, specular_schlick_ggx;

// Android/GLES2 fallback. Recovers the layered depth + sky fresnel of the desktop look,
// but keeps two of its deliberate cuts: no SCREEN_TEXTURE (the framebuffer copy it needs
// stalls tile-based mobile GPUs), and no dot/fract hash noise (Adreno runs fragment math
// in mediump, and the hash's large multiplied constants lose enough precision there to
// break into visible blocks — same bug class fixed with bayer dithering in
// gas_flipbook.shader). Layering plain sin() octaves instead avoids that precision cliff.
uniform vec4 albedo : hint_color = vec4(0.42, 0.78, 1.0, 0.48);
uniform vec4 deep_color : hint_color = vec4(0.03, 0.19, 0.42, 1.0);
uniform float ice_scale : hint_range(0.05, 3.0) = 0.32;
uniform float opacity : hint_range(0.0, 1.0) = 0.46;
uniform float freeze_progress : hint_range(0.0, 1.0) = 0.0;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.36;
uniform float emission_boost : hint_range(0.0, 6.0) = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

// Three sines at non-aligned angles/frequencies read as organic ripples; a single
// sin(x)*sin(y) product (the first version of this) tiles into an obvious grid because
// its zero-crossings line up on both axes.
float ice_octave(vec2 p) {
	float n = sin(dot(p, vec2(0.98, 0.17)) * 3.1);
	n += sin(dot(p, vec2(-0.65, 0.76)) * 4.7);
	n += sin(dot(p, vec2(0.34, -0.94)) * 2.3);
	return n / 3.0;
}

void vertex() {
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
	vec2 p = world_position.xz * ice_scale;

	// Three offset octaves stand in for the desktop's three parallax layers (no view-angle
	// displacement here, just distinct colors/frequencies so the surface doesn't read flat).
	float top_layer = ice_octave(p) * 0.5 + 0.5;
	float middle_layer = ice_octave(p * 1.37 + vec2(5.1)) * 0.5 + 0.5;
	float deep_layer = ice_octave(p * 0.72 + vec2(-7.3, 2.8)) * 0.5 + 0.5;
	float detail = top_layer * 0.36 + middle_layer * 0.34 + deep_layer * 0.3;

	float ridge = 1.0 - abs(middle_layer * 2.0 - 1.0);
	float crack = smoothstep(0.9, 0.98, ridge) * crack_strength;

	vec3 deep_c = deep_color.rgb * (0.62 + deep_layer * 0.38);
	vec3 mid_c = mix(deep_c, albedo.rgb, 0.34 + middle_layer * 0.3);
	vec3 top_c = mix(mid_c, vec3(0.9, 0.97, 1.0), top_layer * 0.28);
	vec3 ice_color = mix(deep_c, top_c, 0.55);

	// Fake sky reflection: cheap (dot + mix, no texture) but it's most of what read as
	// "depth" in the desktop version, so it earns its keep even without real refraction.
	float facing = clamp(abs(dot(world_normal, view_direction)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 2.0);
	vec3 sky_reflection = mix(vec3(0.16, 0.34, 0.55), vec3(0.82, 0.95, 1.0), clamp(view_direction.y * 0.5 + 0.5, 0.0, 1.0));
	ice_color = mix(ice_color, sky_reflection, (0.1 + fresnel * 0.42) * (1.0 - freeze_progress * 0.6));

	float frost_threshold = mix(0.82, 0.24, freeze_progress);
	float frost = smoothstep(frost_threshold - 0.14, frost_threshold + 0.1, detail);
	ice_color = mix(ice_color, vec3(0.9, 0.965, 1.0), frost * mix(0.2, 0.8, freeze_progress));
	ice_color += vec3(0.7, 0.9, 1.0) * crack * 0.35;

	ALBEDO = ice_color;
	ROUGHNESS = mix(0.2, 0.85, freeze_progress);
	SPECULAR = mix(0.7, 0.35, freeze_progress);
	EMISSION = albedo.rgb * crack * 0.05 * emission_boost;
	float frozen_opacity = mix(opacity, 0.9, freeze_progress);
	ALPHA = clamp(frozen_opacity + frost * 0.12 + fresnel * 0.06, 0.3, 0.92);
}
