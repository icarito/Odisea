shader_type spatial;
render_mode blend_mix,depth_draw_alpha_prepass;

uniform vec4 base_color : hint_color = vec4(0.45,0.55,0.60,0.5); // ligeramente sucio
uniform float grime_strength = 0.35; // mezcla de suciedad
uniform float edge_darkening = 0.5; // oscurecer bordes verticales

// Hash simple para ruido (sin textura, barato en GLES2)
float hash(vec2 p){
	p = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return fract(sin(p.x+p.y)*43758.5453);
}

float noise(vec2 p){
	vec2 i=floor(p); vec2 f=fract(p);
	float a=hash(i);
	float b=hash(i+vec2(1.0,0.0));
	float c=hash(i+vec2(0.0,1.0));
	float d=hash(i+vec2(1.0,1.0));
	vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

void fragment(){
	vec2 uv = UV * 4.0; // escala ruido
	float n = noise(uv);
	float grime = mix(0.0, n, grime_strength);
	// oscurecer bordes según distancia a centro X
	float edge = abs(UV.x - 0.5) * 2.0; // 0 centro, 1 bordes
	float edge_factor = mix(1.0 - edge_darkening, 1.0, edge);
	vec3 col = base_color.rgb * edge_factor - grime * 0.2;
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = base_color.a - grime * 0.15;
}
