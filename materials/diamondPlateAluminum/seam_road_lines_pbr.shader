shader_type spatial;

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
uniform float normal_scale : hint_range(0.0, 2.0) = 0.45;
uniform float black_metallic : hint_range(0.0, 1.0) = 0.55;
uniform float black_roughness : hint_range(0.0, 1.0) = 0.48;

void fragment() {
	float stripe_position = fract(UV.x * stripe_count);
	float stripe = step(stripe_position, stripe_width);
	vec3 road_color = texture(albedo_texture, UV).rgb;
	float road_roughness = texture(roughness_texture, UV).r;
	float road_ao = texture(ao_texture, UV).r;

	ALBEDO = mix(scaffold_black.rgb, road_color, stripe);
	METALLIC = mix(black_metallic, 0.16, stripe);
	ROUGHNESS = mix(black_roughness, road_roughness, stripe);
	AO = mix(1.0, road_ao, stripe);
	NORMALMAP = texture(normal_texture, UV).rgb;
	NORMALMAP_DEPTH = normal_scale * stripe;
	ALPHA = 1.0;
}
