// Prop Dither Occlusion Shader — Godot 3 GLES2 compatible
// Cone-based dither: fragments between camera and player are discarded
// via Bayer 4x4 pattern. Applied automatically by PropDitherManager to
// all layer 7 (Props) meshes at runtime.
//
// Based on the proven dither_hiding.shader from project history.
shader_type spatial;
render_mode depth_draw_alpha_prepass, cull_back;

// --- Standard PBR uniforms (copied from SpatialMaterial at runtime) ---
uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular : hint_range(0,1) = 0.5;
uniform float metallic : hint_range(0,1) = 0.0;
uniform float roughness : hint_range(0,1) = 1.0;
uniform sampler2D texture_metallic_roughness_ao : hint_white;
uniform sampler2D texture_normal : hint_normal;
uniform float normal_scale : hint_range(-2.0, 2.0) = 1.0;
uniform bool has_normal_map = false;
uniform bool has_mrao_map = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

// --- Occlusion uniforms (updated per-frame by PropDitherManager) ---
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 0.5;
uniform float is_active = 0.0;
uniform float blur_softness : hint_range(0.0, 2.0) = 0.5;
uniform float edge_fade : hint_range(0.1, 3.0) = 1.0;
uniform float transparency_min : hint_range(0.0, 1.0) = 0.3;
uniform float transparency_max : hint_range(0.0, 1.0) = 0.95;
uniform float floor_protect_radius : hint_range(0.5, 5.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// --- Hash / noise for organic dither edges ---
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float dreamy_noise(vec2 uv, float time_offset) {
	float n = 0.0;
	n += smooth_noise(uv * 1.0 + time_offset) * 0.5;
	n += smooth_noise(uv * 2.0 - time_offset * 0.7) * 0.25;
	n += smooth_noise(uv * 4.0 + time_offset * 0.3) * 0.125;
	return n;
}

// --- Bayer 4x4 ordered dither ---
float dither_pattern(vec2 position) {
	int x = int(mod(position.x, 4.0));
	int y = int(mod(position.y, 4.0));
	int index = x + y * 4;

	float limit = 0.0;
	if (index == 0) limit = 0.0625;
	if (index == 1) limit = 0.5625;
	if (index == 2) limit = 0.1875;
	if (index == 3) limit = 0.6875;
	if (index == 4) limit = 0.8125;
	if (index == 5) limit = 0.3125;
	if (index == 6) limit = 0.9375;
	if (index == 7) limit = 0.4375;
	if (index == 8) limit = 0.25;
	if (index == 9) limit = 0.75;
	if (index == 10) limit = 0.125;
	if (index == 11) limit = 0.625;
	if (index == 12) limit = 1.0;
	if (index == 13) limit = 0.5;
	if (index == 14) limit = 0.875;
	if (index == 15) limit = 0.375;

	return limit;
}

void fragment() {
	// --- Standard PBR output ---
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	if (has_mrao_map) {
		vec4 mrao = texture(texture_metallic_roughness_ao, UV);
		METALLIC = mrao.r * metallic;
		ROUGHNESS = mrao.g;
		AO = mrao.b;
		AO_LIGHT_AFFECT = 0.0;
	}

	if (has_normal_map) {
		NORMALMAP = texture(texture_normal, UV).rgb;
		NORMALMAP_DEPTH = normal_scale;
	}

	// --- Cone-based dither occlusion ---
	if (is_active > 0.5) {
		vec3 cam_to_player = player_pos - camera_pos;
		float dist_cam_player = length(cam_to_player);
		vec3 dir_cam_player = normalize(cam_to_player);

		vec3 cam_to_frag = world_pos - camera_pos;

		// Projection of fragment onto the camera→player line of sight
		float t = dot(cam_to_frag, dir_cam_player);

		// Fragment is between camera and player
		if (t > 0.1 && t < dist_cam_player) {

			// Radial distance from line of sight
			vec3 projection = camera_pos + dir_cam_player * t;
			float dist_radial = distance(world_pos, projection);

			// Taper the cylinder near the player so objects beside them aren't hidden
			float taper = 1.0 - smoothstep(dist_cam_player - 1.5, dist_cam_player, t);
			float cylinder_radius = hole_radius * edge_fade * taper;

			if (dist_radial < cylinder_radius && cylinder_radius > 0.01) {
				// --- Floor/ceiling protection ---
				float horizontal_dist = length(world_pos.xz - player_pos.xz);
				bool near_player_h = horizontal_dist < floor_protect_radius;

				bool is_floor = world_normal.y > 0.5;
				bool camera_above = camera_pos.y > world_pos.y;
				bool below_feet = world_pos.y < (player_pos.y - 0.5);
				bool floor_under = is_floor && camera_above && near_player_h && below_feet;

				bool is_ceiling = world_normal.y < -0.5;
				bool camera_below = camera_pos.y < world_pos.y;
				bool above_head = world_pos.y > (player_pos.y + 2.0);
				bool ceiling_above = is_ceiling && camera_below && near_player_h && above_head;

				if (!floor_under && !ceiling_above) {
					float depth_in_cone = 1.0 - (dist_radial / cylinder_radius);

					// Dreamy noise at edge
					vec2 noise_uv = FRAGCOORD.xy * 0.08 * blur_softness;
					float noise = dreamy_noise(noise_uv, world_pos.x * 0.1 + world_pos.z * 0.1);
					float noisy_depth = depth_in_cone + (noise - 0.5) * blur_softness * 0.3;

					// Dither: center = high transparency, edge = low
					float dither = dither_pattern(FRAGCOORD.xy);
					float transparency = mix(transparency_min, transparency_max, noisy_depth);

					if (dither < transparency) {
						discard;
					}
				}
			}
		}
	}
}
