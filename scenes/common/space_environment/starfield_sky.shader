shader_type canvas_item;

uniform float star_density : hint_range(0.0005, 0.01) = 0.002;
uniform float star_size : hint_range(0.5, 3.0) = 1.5;
uniform vec4 star_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float twinkle_speed : hint_range(0.1, 2.0) = 0.8;

void fragment() {
	vec2 uv = UV;
	float stars = fract(sin(dot(uv * star_density, vec2(12.9898,78.233))) * 43758.5453);
	float twinkle = 0.5 + 0.5 * sin(TIME * twinkle_speed + uv.x * 10.0 + uv.y * 10.0);
	float star = step(1.0 - star_size * 0.01, stars) * twinkle;
	// Gradiente vertical retro-futurista
	vec3 grad = mix(vec3(0.18,0.22,0.38), vec3(0.08,0.10,0.18), uv.y);
	COLOR = mix(vec4(grad,1.0), star_color, star);
}
