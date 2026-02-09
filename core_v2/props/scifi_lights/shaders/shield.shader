shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform float iTime;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 shield_color : hint_color = vec4(0.79, 0.43, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.0;
uniform float noise_scale : hint_range(1.0, 20.0) = 8.0;

// Simple hash-based noise (no texture needed)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		val += amp * noise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return val;
}

void fragment() {
	// Fresnel effect — glow at edges
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);
	
	// Animated noise pattern
	vec2 uv = UV * noise_scale;
	float time = iTime * 0.3;
	float n1 = fbm(uv + vec2(time, -time * 0.7));
	float n2 = fbm(uv * 1.5 - vec2(time * 0.5, time));
	float pattern = n1 * n2 * 4.0;
	
	// Scrolling scanline
	float scan = smoothstep(0.4, 0.6, fract(UV.y * 3.0 - iTime * 0.2));
	
	// Combine
	float glow = fresnel * (0.5 + pattern * 0.5) + scan * fresnel * 0.3;
	glow = clamp(glow, 0.0, 1.0);
	
	ALBEDO = shield_color.rgb * glow * intensity;
	ALPHA = glow * 0.7 * intensity;
}
