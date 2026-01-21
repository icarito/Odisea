shader_type spatial;
render_mode unshaded, cull_front, depth_test_disable;

// Odisea V3 Shadow Projection Shader
// Projects a texture inside the volume defined by the mesh (Cube),
// utilizing the depth buffer to reconstruct world position.

uniform sampler2D splat_texture : hint_albedo;
uniform float shadow_opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 shadow_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);

// We need inverse view-projection to reconstruct world pos from depth
// Godot provides INV_CAMERA_MATRIX. We need to manually handle projection?
// Actually, Godot's VIEW matrix transforms World -> Camera (View).
// PROJECTION transforms View -> Clip.
// We need Clip -> World. 
// INV_PROJECTION_MATRIX * INV_VIEW_MATRIX? (INV_CAMERA_MATRIX is usually just world transform of camera).

void vertex() {
	// We draw the FRONT faces if we are outside, or BACK faces if we are inside?
	// cull_front means we see the inside of the back faces.
	// This ensures we always draw pixels BEHIND the front face of the cube.
	// It's a common decal trick.
}

void fragment() {
	// 1. Get Depth
	// In GLES2, DEPTH_TEXTURE might not work on all hardware/drivers.
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	
	// 2. Reconstruct ND Coordinates
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	
	// 3. Reconstruct View Space Position
	vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz /= view_pos.w;
	
	// 4. Reconstruct World Space Position
	vec4 world_pos = CAMERA_MATRIX * vec4(view_pos.xyz, 1.0);
	
	// 5. Transform to Object Local Space (The Cube)
	// 'inverse(WORLD_MATRIX)' is not available in fragment in some versions, but 'inverse(mat4(WORLD_MATRIX))' works?
	// Godot shader language provides it usually.
	vec4 local_pos = inverse(WORLD_MATRIX) * world_pos;
	
	// 6. Check Bounds (Cube is centered at 0, extents usually -1..1 or -0.5..0.5)
	// Default CubeMesh is size 2 (-1 to 1). Let's assume -1 to 1.
	// We add a small margin to avoid sharp cuts? Or hard cut.
	// Decal Logic:
	if (abs(local_pos.x) > 1.0 || abs(local_pos.y) > 1.0 || abs(local_pos.z) > 1.0) {
		discard;
	}
	
	// 7. UV Projection (Projecting Down -Y axis)
	// Local XZ maps to UV.
	// Range -1..1 -> 0..1
	vec2 proj_uv = local_pos.xz * 0.5 + 0.5;
	
	// 8. Sample Texture
	// Use a procedural circle if no texture
	float blob = 1.0 - distance(proj_uv, vec2(0.5)) * 2.0;
	blob = clamp(blob, 0.0, 1.0);
	blob = smoothstep(0.0, 1.0, blob); // Soft edge
	
	// Optional: Use texture if assigned
	// float tex_alpha = texture(splat_texture, proj_uv).a;
	
	ALBEDO = shadow_color.rgb;
	ALPHA = blob * shadow_color.a * shadow_opacity;
	
	// Vertical Falloff (Fade out at top of box to blend with objects entering volume)
	// Local Y goes from -1 (bottom) to 1 (top).
	// Fade from 1.0 at bottom to 0.0 at top?
	// float falloff = 1.0 - (local_pos.y * 0.5 + 0.5);
	// ALPHA *= falloff;
}
