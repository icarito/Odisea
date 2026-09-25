shader_type spatial;
// Variante doble-lado y TRANSPARENTE de FlatFake (vidrios CULL_DISABLED vistos de
// ambos lados en el perfil low-end). Mismo shading falso que FlatFake, con blend_mix.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, specular_disabled;

// En Godot 3 hint_color es solo para vec4: con vec3 el shader no compila.
uniform vec3 albedo = vec3(0.7, 0.72, 0.76);
uniform vec3 light_dir_view = vec3(0.35, 0.55, 0.75);
uniform float ambient = 0.14;
uniform float vertical_ao = 0.35;
uniform float exposure = 0.88;
// glow=1 => el color no se sombrea (vidrios/luces/holo "emiten" plano).
uniform float glow = 0.0;
// Lightmap horneado opcional (IOSLightmapFallback setea lightmap_mix=1).
uniform sampler2D lightmap_tex;
uniform float lightmap_energy = 1.0;
uniform float lightmap_mix = 0.0;
uniform float alpha = 0.45;

varying float v_world_y;

void vertex() {
	v_world_y = (WORLD_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 l = normalize(light_dir_view);
	float ndl = clamp(dot(normalize(NORMAL), l) * 0.5 + 0.5, 0.0, 1.0);
	ndl = pow(ndl, 1.4);
	float ao = 1.0 - vertical_ao * clamp(0.5 - v_world_y * 0.04, 0.0, 1.0);
	vec3 shaded = albedo * (ambient + (1.0 - ambient) * ndl) * ao * exposure;
		vec3 lm_mul = vec3(1.0);
	if (lightmap_mix > 0.001) { lm_mul = mix(vec3(1.0), texture(lightmap_tex, UV2).rgb * lightmap_energy, lightmap_mix); }
ALBEDO = mix(shaded, albedo, glow) * lm_mul;
	ALPHA = alpha;
}
