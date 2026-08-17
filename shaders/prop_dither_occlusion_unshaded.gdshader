// Prop Dither Occlusion Shader — unshaded variant.
//
// Same cone-discard occlusion as prop_dither_occlusion.gdshader, but for source
// materials with flags_unshaded=true (e.g. baked signage: flat text on a texture atlas,
// no PBR lighting was ever part of the design). The base shader is `shader_type spatial`
// without `unshaded` in render_mode, so ALBEDO there goes through the normal light pass —
// correct for lit props, but it makes an originally-unshaded material look dim/tinted by
// scene lighting once PropDitherManager wraps it. `render_mode` is fixed per shader file
// in Godot 3 (can't toggle at runtime), so this is a separate file instead of a uniform.
shader_type spatial;
render_mode cull_back, unshaded;

uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D texture_albedo : hint_albedo;
uniform bool has_albedo_map = false;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform bool use_vertex_color = false;

uniform bool emission_enabled = false;
uniform vec4 emission_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform int emission_op = 0; // 0 = ADD, 1 = MULTIPLY

// --- Occlusion uniforms (updated per-frame by PropDitherManager) ---
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 0.5;
uniform float is_active = 0.0;
uniform float edge_fade : hint_range(0.1, 3.0) = 1.0;
uniform float transparency_min : hint_range(0.0, 1.0) = 0.3;
uniform float transparency_max : hint_range(0.0, 1.0) = 0.95;
uniform float floor_protect_radius : hint_range(0.5, 5.0) = 1.0;
uniform bool stable_mobile_dither = false;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float bayer4(vec2 p) {
	float x = mod(floor(p.x), 4.0);
	float y = mod(floor(p.y), 4.0);
	if (y < 1.0) return (x < 1.0 ? 0.0 : (x < 2.0 ? 8.0 : (x < 3.0 ? 2.0 : 10.0))) / 16.0;
	if (y < 2.0) return (x < 1.0 ? 12.0 : (x < 2.0 ? 4.0 : (x < 3.0 ? 14.0 : 6.0))) / 16.0;
	if (y < 3.0) return (x < 1.0 ? 3.0 : (x < 2.0 ? 11.0 : (x < 3.0 ? 1.0 : 9.0))) / 16.0;
	return (x < 1.0 ? 15.0 : (x < 2.0 ? 7.0 : (x < 3.0 ? 13.0 : 5.0))) / 16.0;
}

void fragment() {
	if (is_active > 0.5) {
		vec3 cam_to_player = player_pos - camera_pos;
		float dist_cam_player = length(cam_to_player);
		vec3 dir_cam_player = cam_to_player / dist_cam_player;
		vec3 cam_to_frag = world_pos - camera_pos;
		float t = dot(cam_to_frag, dir_cam_player);

		if (t > 0.1 && t < dist_cam_player) {
			vec3 projection = camera_pos + dir_cam_player * t;
			float dist_radial = distance(world_pos, projection);
			float taper = 1.0 - smoothstep(dist_cam_player - 1.5, dist_cam_player, t);
			float cylinder_radius = hole_radius * edge_fade * taper;

			if (dist_radial < cylinder_radius && cylinder_radius > 0.01) {
				float horizontal_dist = length(world_pos.xz - player_pos.xz);
				bool near_h = horizontal_dist < floor_protect_radius;
				bool floor_under   = world_normal.y >  0.5 && camera_pos.y > world_pos.y && near_h && world_pos.y < (player_pos.y - 0.5);
				bool ceiling_above = world_normal.y < -0.5 && camera_pos.y < world_pos.y && near_h && world_pos.y > (player_pos.y + 2.0);

				if (!floor_under && !ceiling_above) {
					float depth_in_cone = 1.0 - (dist_radial / cylinder_radius);
					float transparency = mix(transparency_min, transparency_max, depth_in_cone);
					float threshold = stable_mobile_dither ? bayer4(FRAGCOORD.xy) : ign(FRAGCOORD.xy);
					if (threshold < transparency) {
						discard;
					}
				}
			}
		}
	}

	vec4 albedo_tex = has_albedo_map ? texture(texture_albedo, UV) : vec4(1.0);
	if (use_alpha_scissor && albedo_tex.a < alpha_scissor_threshold) {
		discard;
	}
	vec3 base_albedo = use_vertex_color ? (COLOR.rgb * albedo.rgb) : albedo.rgb;
	ALBEDO = base_albedo * albedo_tex.rgb;

	if (emission_enabled) {
		if (emission_op == 1) {
			EMISSION = ALBEDO * emission_color.rgb * emission_energy;
		} else {
			EMISSION = emission_color.rgb * emission_energy;
		}
	}
}
