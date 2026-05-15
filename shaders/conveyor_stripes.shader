shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : hint_color = vec4(0.08, 0.08, 0.08, 1.0);
uniform vec4 color_b : hint_color = vec4(0.42, 0.36, 0.16, 1.0);
uniform float tiling = 6.0;
uniform float phase = 0.0;
uniform vec2 dir = vec2(0.0, 1.0);
uniform float fill = 0.42;
uniform float emission = 0.015;
uniform float softness = 0.08;
uniform float metalness = 0.18;
uniform float roughness = 0.82;

void fragment() {
	vec2 uv = UV;
	vec2 d = normalize(max(abs(dir.x) + abs(dir.y), 0.0001) * dir);
	float u = dot(uv, d) * tiling + phase;
	float f = fract(u);
	float edge = 1.0 - smoothstep(fill - softness, fill + softness, f);
	vec3 col = mix(color_a.rgb, color_b.rgb, edge);
	ALBEDO = col;
	METALLIC = metalness;
	ROUGHNESS = roughness;
	EMISSION = col * emission;
}
