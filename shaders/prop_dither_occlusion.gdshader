// Prop Dither Occlusion Shader — Godot 3 GLES2 compatible
// Cone-based dither: fragments between camera and player are discarded
// via Bayer 4x4 pattern. Applied automatically by PropDitherManager to
// all layer 7 (Props) meshes at runtime.
//
// Based on the proven dither_hiding.shader from project history.
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_never;

// --- Lightmap horneado aplicado a mano (opt-in: ODISEA_MANUAL_LIGHTMAP=1) ----------
// Godot ata su lightmap a "max_texture_image_units - 4": unidad 12 en Android, 4 en
// iOS, donde choca con las texturas del material y con screen/depth_texture. La
// colision es silenciosa (sin error de linkeo) y el bake no se dibuja.
// IOSLightmapFallback.gd setea estos dos uniforms para muestrearlo aca, en una unidad
// secuencial. Con lightmap_energy en 0 esto no hace NADA: en escritorio y Android
// sigue mandando el camino nativo del motor.
uniform sampler2D lightmap_tex : hint_albedo;
uniform float lightmap_energy = 0.0;

// --- Standard PBR uniforms (copied from SpatialMaterial at runtime) ---
uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D texture_albedo : hint_albedo;
uniform bool has_albedo_map = false;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0,1) = 0.5;
uniform float metallic : hint_range(0,1) = 0.0;
uniform float roughness : hint_range(0,1) = 1.0;
uniform sampler2D texture_metallic_roughness_ao : hint_white;
uniform vec4 mrao_metallic_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 mrao_roughness_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 mrao_ao_mask = vec4(0.0, 0.0, 1.0, 0.0);
uniform sampler2D texture_normal : hint_normal;
uniform float normal_scale : hint_range(-2.0, 2.0) = 1.0;
uniform bool has_normal_map = false;
uniform bool has_mrao_map = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform bool use_world_uv = false;
uniform vec2 world_uv_repeat = vec2(1.0, 1.0);
uniform bool use_vertex_color = false;

// --- Emission uniforms (copied from SpatialMaterial at runtime) ---
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
uniform vec4 ghost_tint : hint_color = vec4(0.05, 0.07, 0.11, 1.0);
uniform float ghost_alpha_min : hint_range(0.0, 1.0) = 0.3;

// UN SOLO varying. iOS/PowerVR GLES2 garantiza 8 varying vectors y scene.glsl ya se
// come casi todos; este shader tuvo 2 hasta el 2026-05-30 y paso a 4 en 23a32022
// ("Fixes for scaffold field", que agrego local_pos + instance_uv_extent para
// use_world_uv). Desde entonces las superficies que convierte no se dibujan en iOS,
// mientras que card_parallax y seam_road_lines_pbr -- mismo GLES2, MAS samplers, con
// discard -- se dibujan bien con 2 varyings. La cuenta de samplers estaba descartada;
// la de varyings no se habia mirado.
//
// world_pos y world_normal se reconstruyen en fragment: ahi VERTEX y NORMAL estan en
// espacio de vista y CAMERA_MATRIX los lleva a mundo. Es el MISMO valor, solo que
// calculado en vez de interpolado. local_pos no se puede reconstruir sin invertir
// WORLD_MATRIX, asi que se queda: es el unico que sobrevive.
varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

// Interleaved gradient noise — smooth, no tiling, cheap (no sin/hash)
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// A fixed 4x4 Bayer matrix avoids the diagonal precision bands produced by
// the IGN hash at large FRAGCOORD values on GLES2/mediump Android drivers.
float bayer4(vec2 p) {
	float x = mod(floor(p.x), 4.0);
	float y = mod(floor(p.y), 4.0);
	if (y < 1.0) return (x < 1.0 ? 0.0 : (x < 2.0 ? 8.0 : (x < 3.0 ? 2.0 : 10.0))) / 16.0;
	if (y < 2.0) return (x < 1.0 ? 12.0 : (x < 2.0 ? 4.0 : (x < 3.0 ? 14.0 : 6.0))) / 16.0;
	if (y < 3.0) return (x < 1.0 ? 3.0 : (x < 2.0 ? 11.0 : (x < 3.0 ? 1.0 : 9.0))) / 16.0;
	return (x < 1.0 ? 15.0 : (x < 2.0 ? 7.0 : (x < 3.0 ? 13.0 : 5.0))) / 16.0;
}

void fragment() {
	float ghost_k = 0.0;
	// cull_back means FRONT_FACING is always true here in practice, but keep
	// this in sync with prop_dither_occlusion_double_sided.gdshader (see that
	// file's header comment) rather than let the two drift apart again.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 world_pos = (CAMERA_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((CAMERA_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// --- Cone occlusion discard FIRST — skip all PBR work on hidden fragments ---
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
					ghost_k = clamp(depth_in_cone * 1.4, 0.0, 0.8);
				}
			}
		}
	}

	// --- Standard PBR output ---
	vec2 sample_uv = UV;
	if (use_world_uv) {
		vec3 abs_normal = abs(world_normal);
		vec2 instance_uv_extent = vec2(length(WORLD_MATRIX[0].xyz), length(WORLD_MATRIX[2].xyz));
		vec2 planar_uv;
		vec2 extent;
		if (abs_normal.y >= abs_normal.x && abs_normal.y >= abs_normal.z) {
			// Horizontal face: project on XZ. Flip U when normal points down so
			// top and bottom views are consistent (no mirror artifact).
			planar_uv = local_pos.xz + vec2(0.5);
			extent = instance_uv_extent;
			if (world_normal.y < 0.0) planar_uv.x = 1.0 - planar_uv.x;
		} else if (abs_normal.x >= abs_normal.z) {
			// X-dominant face: project on ZY
			planar_uv = local_pos.zy + vec2(0.5);
			extent = vec2(instance_uv_extent.y, instance_uv_extent.y);
			if (world_normal.x > 0.0) planar_uv.x = 1.0 - planar_uv.x;
		} else {
			// Z-dominant face: project on XY
			planar_uv = local_pos.xy + vec2(0.5);
			extent = vec2(instance_uv_extent.x, instance_uv_extent.x);
			if (world_normal.z < 0.0) planar_uv.x = 1.0 - planar_uv.x;
		}
		sample_uv = planar_uv * extent * world_uv_repeat + uv1_offset.xy;
	}
	vec4 albedo_tex = has_albedo_map ? texture(texture_albedo, sample_uv) : vec4(1.0);
	if (use_alpha_scissor && albedo_tex.a < alpha_scissor_threshold) {
		discard;
	}
	// When vertex_color_use_as_albedo: multiply COLOR * albedo so white COLOR
	// (mesh has no vertex color data) degrades gracefully to albedo_color.
	vec3 base_albedo = use_vertex_color ? (COLOR.rgb * albedo.rgb) : albedo.rgb;
	ALBEDO = base_albedo * albedo_tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	if (has_mrao_map) {
		vec4 mrao = texture(texture_metallic_roughness_ao, UV);
		METALLIC = dot(mrao, mrao_metallic_mask) * metallic;
		ROUGHNESS = dot(mrao, mrao_roughness_mask) * roughness;
		AO = dot(mrao, mrao_ao_mask);
		AO_LIGHT_AFFECT = 0.0;
	}

	if (has_normal_map) {
		NORMALMAP = texture(texture_normal, UV).rgb;
		NORMALMAP_DEPTH = normal_scale;
	}

	// --- Emission output ---
	if (emission_enabled) {
		if (emission_op == 1) {
			EMISSION = ALBEDO * emission_color.rgb * emission_energy;
		} else {
			EMISSION = emission_color.rgb * emission_energy;
		}
	}


	if (lightmap_energy > 0.0) {
		EMISSION += ALBEDO * texture(lightmap_tex, UV2).rgb * lightmap_energy;
	}

	ALBEDO = mix(ALBEDO, ghost_tint.rgb, ghost_k);
	EMISSION *= 1.0 - ghost_k;
	ALPHA = mix(1.0, ghost_alpha_min, ghost_k);
}
