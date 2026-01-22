shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, depth_test_disable, unshaded;

uniform float radius = 1.2;
uniform float hardness = 0.7;
uniform float rotation_angle = 0.0;
uniform float base_opacity = 0.6;
uniform float height_alpha = 1.0;

varying vec3 v_decal_pos;
varying vec3 v_decal_right;
varying vec3 v_decal_up;
varying vec3 v_decal_fwd;
varying vec3 v_half_scale;

void vertex() {
	v_decal_pos = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	
	v_decal_right = normalize((WORLD_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	v_decal_up = normalize((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	v_decal_fwd = normalize((WORLD_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	
	v_half_scale = vec3(
		length((WORLD_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz),
		length((WORLD_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz),
		length((WORLD_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz)
	) * 0.5;
}

void fragment() {
	// Reconstruct world position from depth
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec4 world = CAMERA_MATRIX * view;
	vec3 world_pos = world.xyz;
	
	vec3 p = world_pos - v_decal_pos;
	
	// Check bounds
	float in_x = step(abs(dot(p, v_decal_right)), v_half_scale.x);
	float in_y = step(abs(dot(p, v_decal_up)), v_half_scale.y);
	float in_z = step(abs(dot(p, v_decal_fwd)), v_half_scale.z);
	float in_bounds = in_x * in_y * in_z;
	
	// Project onto XZ plane
	vec2 uv = vec2(dot(p, v_decal_right), dot(p, v_decal_fwd)) / radius;
	
	// Rotation
	float s = sin(rotation_angle);
	float c = cos(rotation_angle);
	uv = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
	
	// Oval squeeze
	uv.x *= 1.5;
	
	// Distance and alpha
	float dist = length(uv);
	float current_hardness = mix(hardness * 0.4, hardness, height_alpha);
	float alpha_mask = 1.0 - smoothstep(current_hardness, 1.0, dist);
	float final_alpha = alpha_mask * base_opacity * pow(height_alpha, 1.5) * in_bounds;
	
	ALBEDO = vec3(0.0);
	ALPHA = final_alpha;
}
