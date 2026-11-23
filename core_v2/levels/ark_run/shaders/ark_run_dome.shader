shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// FD-324 — domos con volumen sci-fi. Fresnel/rim-light azul-cian + bandas
// geodesicas sutiles derivadas de la posicion local del mesh (angulo alrededor y
// altura), que dan contraste en la silueta en vez de un plano lavado. Se aplica
// al mismo material del MultiMesh de cada tipo de domo: 0 draw calls extra.

uniform vec4 base_color : hint_color = vec4(0.34, 0.43, 0.52, 1.0);
uniform vec4 rim_color : hint_color = vec4(0.15, 0.82, 1.0, 1.0);
uniform float rim_power = 2.6;
uniform float rim_gain = 0.85;
uniform float band_frequency = 9.0;
uniform float band_strength = 0.16;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float ang = atan(v_local.x, v_local.z);
	float band = abs(sin(ang * band_frequency + v_local.y * 0.08));
	band = smoothstep(0.86, 1.0, band);

	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), rim_power);

	ALBEDO = base_color.rgb * (1.0 + band * band_strength);
	ROUGHNESS = 0.62;
	METALLIC = 0.18;
	EMISSION = rim_color.rgb * (fresnel * rim_gain + band * 0.06);
}
