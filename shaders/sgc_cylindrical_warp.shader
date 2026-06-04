shader_type spatial;
render_mode diffuse_lambert, vertex_lighting, cull_disabled, shadows_disabled, depth_draw_opaque;

// FD-052: SGC Cylindrical Projection (GLES2)
//
// Scaffold flat in XZ, player walks on Z=0 baseline, moves along Z.
// Cylinder axis = X — ring closes around Z.
//
//   r     = base_radius - world.y   (Y=0 → r=base_radius, Y>0 → toward axis)
//   theta = world.z / base_radius   (arc length / radius, no stretch)
//   warped.x = world.x              (cylinder axis, unchanged)
//   warped.y = base_radius - r*cos(theta)
//   warped.z = r * sin(theta)
//
// At theta=0, Z=0: warped == world ✓
// Player walks in +Z → theta increases → floor curves overhead.

uniform vec4  albedo_color   : hint_color = vec4(0.38, 0.38, 0.42, 1.0);
uniform float base_radius    = 190.0;
uniform float transition_blend : hint_range(0.0, 1.0) = 1.0;
uniform float rotation_speed = 0.0;
uniform int   debug_theta    = 0;

varying float v_theta;

void vertex() {
	vec3 world = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float r     = base_radius - world.y;
	float theta = world.z / base_radius + TIME * rotation_speed;

	vec3 warped;
	warped.x = world.x;
	warped.y = base_radius - r * cos(theta);
	warped.z = r * sin(theta);

	vec3 world_final = mix(world, warped, transition_blend);

	MODELVIEW_MATRIX = mat4(1.0);
	vec4 view_pos = INV_CAMERA_MATRIX * vec4(world_final, 1.0);
	VERTEX = view_pos.xyz;

	v_theta = theta;
}

void fragment() {
	if (debug_theta == 1) {
		float t = clamp(v_theta * 0.5 / 3.14159 + 0.5, 0.0, 1.0);
		ALBEDO = vec3(1.0 - t, t, 0.2);
	} else {
		ALBEDO = albedo_color.rgb;
	}
}
