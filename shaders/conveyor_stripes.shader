shader_type spatial;
render_mode unshaded;

uniform vec4 color_a : hint_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform vec4 color_b : hint_color = vec4(0.15, 0.35, 0.15, 1.0);
uniform float tiling = 6.0;      // cuántas rayas por unidad UV
uniform float speed = 0.8;       // velocidad del desplazamiento de rayas
uniform vec2 dir = vec2(0, 0); // dirección de desplazamiento en UV
uniform float fill = 0.8;        // grosor relativo de cada raya (0..1)
uniform float emission = 0.2;    // brillo sutil para legibilidad

void fragment() {
	vec2 uv = UV;
	vec2 d = normalize(dir);
	float u = dot(uv, d) * tiling + TIME * speed;
	float f = fract(u);
	float s = step(f, fill);
	vec3 col = mix(color_a.rgb, color_b.rgb, s);
	ALBEDO = col;
	EMISSION = col * emission;
}
