shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Dome wall texturing that ignores the mesh's own UVs (Qodot planar-projects each
// face independently against its own texture axis, so a tiling texture applied
// straight to those UVs shows a visible seam at every wall segment boundary,
// since the pieces aren't rectangular). Instead this rebuilds UV from the
// fragment's ANGULAR position around the dome's vertical axis (world XZ), which
// every wall segment shares — so the texture wraps continuously with no seams,
// at the cost of a bit of warp near sharp curvature changes.

uniform sampler2D albedo_texture : hint_albedo;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D roughness_texture : hint_white;
uniform sampler2D ao_texture : hint_white;
uniform sampler2D depth_texture : hint_black;

uniform vec3 dome_center = vec3(0.0, 0.0, 0.0);
// How many texture repeats around the full 360-degree circumference.
uniform float radial_repeats : hint_range(1.0, 64.0) = 18.0;
// World units per texture repeat, vertically. Picked to land the texture's own
// tile seam (top/bottom edge of the grid pattern) on the wall's real horizontal
// joints — measured from the baked mesh, the strongest ones sit at world Y=0
// (the base) and Y=6.75 (see tools/probe_dome_wall_seams notes), 6.75m apart.
uniform float vertical_scale : hint_range(0.5, 20.0) = 6.75;
// Shifts the pattern up/down without changing its repeat rate, for nudging a
// specific band into place by eye.
uniform float vertical_offset : hint_range(-10.0, 10.0) = 0.0;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform float depth_scale : hint_range(0.0, 0.2) = 0.04;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_pos;
// Cylindrical tangent/bitangent, rotated into view space in vertex() so they
// line up with VIEW/NORMAL, which are always view-space in fragment().
varying vec3 view_tangent;
varying vec3 view_bitangent;

void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 radial = world_pos - dome_center;
	radial.y = 0.0;
	vec3 radial_dir = normalize(radial + vec3(0.0001, 0.0, 0.0));
	vec3 tangent_dir = normalize(cross(vec3(0.0, 1.0, 0.0), radial_dir));
	mat3 world_to_view = mat3(INV_CAMERA_MATRIX);
	view_tangent = normalize(world_to_view * tangent_dir);
	view_bitangent = normalize(world_to_view * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec3 radial = world_pos - dome_center;
	float angle = atan(radial.x, radial.z); // -PI..PI
	vec2 cyl_uv = vec2(angle / 6.28318530718 * radial_repeats, world_pos.y / vertical_scale + vertical_offset);

	// Orthogonalize against the mesh's real (possibly faceted, not perfectly
	// cylindrical) normal so lighting still follows the actual geometry.
	vec3 n = normalize(NORMAL);
	vec3 t = normalize(view_tangent - n * dot(view_tangent, n));
	vec3 b = cross(n, t);

	// Manual parallax (single-sample offset) in the cylindrical tangent space —
	// SpatialMaterial's built-in depth mapping assumes the mesh's own UV/tangent,
	// which we're bypassing, so it's redone here to keep the depth look.
	vec3 tangent_view_dir = normalize(vec3(dot(VIEW, t), dot(VIEW, b), dot(VIEW, n)));
	float height = texture(depth_texture, cyl_uv).r;
	vec2 parallax_offset = tangent_view_dir.xy * (height * depth_scale - depth_scale * 0.5);
	vec2 uv = cyl_uv - parallax_offset;

	vec4 albedo = texture(albedo_texture, uv);
	float rough = texture(roughness_texture, uv).r;
	float ao = texture(ao_texture, uv).r;
	vec3 tex_normal = texture(normal_texture, uv).rgb * 2.0 - 1.0;
	tex_normal.xy *= normal_scale;

	ALBEDO = albedo.rgb;
	METALLIC = metallic_value;
	ROUGHNESS = rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.0;
	NORMAL = normalize(t * tex_normal.x + b * tex_normal.y + n * tex_normal.z);
}
