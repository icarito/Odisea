shader_type spatial;
// Variante doble-lado de FlatFake para el perfil low-end. El material original de
// las rejillas (steel grate / deck de los andamios) es CULL_DISABLED: es un unico
// quad que tambien se mira desde abajo. Al hornear, los triangulos del deck pueden
// quedar con winding hacia abajo, asi que con cull_back desaparecen vistos desde
// arriba y el jugador camina sobre una superficie invisible. Mismo shading que
// FlatFake, solo cambia el render_mode.
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled;

// En Godot 3 hint_color es solo para vec4: con vec3 el shader no compila.
uniform vec3 albedo = vec3(0.7, 0.72, 0.76);
uniform vec3 light_dir_view = vec3(0.35, 0.55, 0.75);
uniform float ambient = 0.14;
uniform float vertical_ao = 0.35;
uniform float exposure = 0.88;
// glow=1 => el color no se sombrea (vidrios/luces/holo "emiten" plano).
uniform float glow = 0.0;

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
	ALBEDO = mix(shaded, albedo, glow);
}
