shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// FD-324 — pase Tron de las terrazas. Base grafito oscuro con rejilla industrial
// cada `grid_spacing` metros y ribete cian tenue en el borde de la placa. Todo el
// patron sale de la posicion LOCAL del vertice (CubeMesh de 200x2x200 => +-100 en
// x/z), asi que se repite igual en cada instancia del MultiMesh y no agrega draw
// calls: es el mismo pase con otro material.

uniform vec4 base_color : hint_color = vec4(0.045, 0.05, 0.062, 1.0);
uniform vec4 grid_color : hint_color = vec4(0.16, 0.22, 0.27, 1.0);
uniform vec4 trim_color : hint_color = vec4(0.12, 0.82, 1.0, 1.0);
uniform float grid_spacing = 10.0;
uniform float grid_width = 0.035;
uniform float half_extent = 100.0;
uniform float trim_width = 3.0;
uniform float trim_emission = 0.42;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 p = v_local.xz;
	vec2 f = fract(p / grid_spacing);
	vec2 dist = min(f, vec2(1.0) - f);
	float line = max(
		smoothstep(grid_width, 0.0, dist.x),
		smoothstep(grid_width, 0.0, dist.y));

	vec2 edge = min(abs(p), vec2(half_extent) - abs(p));
	float trim = smoothstep(trim_width, 0.0, min(edge.x, edge.y));

	vec3 color = mix(base_color.rgb, grid_color.rgb, line * 0.55);
	color = mix(color, trim_color.rgb * 0.55, trim * 0.45);

	ALBEDO = color;
	ROUGHNESS = 0.68;
	METALLIC = 0.25;
	EMISSION = trim_color.rgb * trim * trim_emission + grid_color.rgb * line * 0.04;
}
