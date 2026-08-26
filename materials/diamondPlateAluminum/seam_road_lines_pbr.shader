shader_type spatial;

// --- Lightmap horneado aplicado a mano (solo iOS) ---------------------------------
// Godot ata su lightmap a "max_texture_image_units - 4": unidad 12 en Android, 4 en
// iOS, donde choca con las texturas del material y con screen/depth_texture. La
// colision es silenciosa (sin error de linkeo) y el bake no se dibuja. El aplicador
// (IOSLightmapFallback.gd) setea estos dos uniforms para muestrearlo aca, en una
// unidad secuencial. Con energia 0 esto no hace NADA: en escritorio y Android sigue
// mandando el camino nativo del motor.
uniform sampler2D lightmap_tex : hint_albedo;
uniform float lightmap_energy = 0.0;

// Variante PBR de las juntas de seguridad de Dome_Intro. El patrón conserva
// amarillo/negro industrial; las bandas amarillas toman el desgaste RoadLines.
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled;

uniform sampler2D albedo_texture : hint_albedo;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D roughness_texture : hint_white;
uniform sampler2D ao_texture : hint_white;
uniform vec4 scaffold_black : hint_color = vec4(0.18, 0.19, 0.21, 1.0);
uniform float stripe_count = 14.0;
uniform float stripe_width = 0.50;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.25;
// Los seams son largos: una sola copia 1K por placa diluye todo el desgaste.
// Repetir sólo el muestreo PBR mantiene las franjas verticales en su escala.
uniform vec2 pbr_texture_repeat = vec2(4.0, 3.0);
uniform float black_metallic : hint_range(0.0, 1.0) = 0.55;
uniform float black_roughness : hint_range(0.0, 1.0) = 0.48;

// Contrato de PropDitherManager. Se mantiene este PBR, pero sus placas en la
// capa de props se recortan cuando tapan al personaje.
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
				bool floor_under = world_normal.y > 0.5 && camera_pos.y > world_pos.y && near_h && world_pos.y < (player_pos.y - 0.5);
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

	float stripe_position = fract(UV.x * stripe_count);
	float stripe = step(stripe_position, stripe_width);
	vec2 pbr_uv = UV * pbr_texture_repeat;
	vec3 road_color = texture(albedo_texture, pbr_uv).rgb;
	float road_roughness = texture(roughness_texture, pbr_uv).r;
	float road_ao = texture(ao_texture, pbr_uv).r;

	ALBEDO = mix(scaffold_black.rgb, road_color, stripe);
	METALLIC = mix(black_metallic, 0.16, stripe);
	ROUGHNESS = mix(black_roughness, road_roughness, stripe);
	AO = mix(1.0, road_ao, stripe * 0.35);
	AO_LIGHT_AFFECT = 0.35;
	NORMALMAP = texture(normal_texture, pbr_uv).rgb;
	NORMALMAP_DEPTH = normal_scale * stripe;
	ALPHA = 1.0;

	if (lightmap_energy > 0.0) {
		EMISSION += ALBEDO * texture(lightmap_tex, UV2).rgb * lightmap_energy;
	}
}
