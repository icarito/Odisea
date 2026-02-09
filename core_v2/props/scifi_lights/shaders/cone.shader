shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;
uniform float iTime;
uniform float blenda;
uniform float blendb;

void vertex() {
	
}

float floor_grid(vec2 p) {
    vec2 e = vec2(0.05); 
	vec2 a = 1.-smoothstep(1.0 - e, vec2(1.001), fract(p));
	vec2 b = smoothstep(vec2(0.0), e + 0.001, fract(p));
    vec2 l = (0.5*(clamp((a + b),0.,2.) - (1.0 - e)))*clamp(1.0 - 3.*e,0.,1.);
    return clamp(((l.x + l.y) ),0.,1.);
}

const vec3 col_o = vec3(0.79, 0.43, 1.0);

void fragment() {
	vec2 tuv = UV;
	
	vec3 col = vec3(0);
	float alpha = 0.0;
	
	// Semi-transparent base tint always visible
	float base_alpha = 0.15 * blenda;
	col = col_o * 0.3 * blenda;
	alpha = base_alpha;
	
	if(blenda > 0.) {
		int d = int(tuv.x * 80.);
		
		vec2 tuv2 = tuv * vec2(10., 1);
		vec2 ouv = tuv2;
		tuv2 = floor(tuv2 * 80.) / 80.;
		vec2 offset = round(tuv2 * 20.) / 20.;
		vec3 dot_col = vec3(0.);
	    for(int i = 0; i < 3; i++) {
	        float t = iTime + float(i) * 5.1 + (abs(tuv2.y)) * 6.5;
	        float r = (pow(sin(t), 3.0) + 1.0) * 0.02;
	        
	        if(length(tuv2 - offset) < r + 0.001) {
				if(i == 0) dot_col.x = 1.;
				if(i == 1) dot_col.yz = vec2(1.);
				if(i == 2) dot_col.z = 1.;
	        }
		}
		dot_col *= vec3(floor_grid(ouv * 20. + 0.375));
		
		float mask = 1. - smoothstep(0., 4., abs(float(d % 10) - 4.5));
		mask *= 1. - smoothstep(0., 0.001, (.5 - UV.y - blenda * 0.5));
		mask *= 1. - smoothstep(0., 0.001, -(.5 - UV.y - blendb * 0.5));
		dot_col *= mask;
		
		float dot_strength = length(dot_col);
		col += dot_col * 2.0;
		alpha = clamp(alpha + dot_strength * 0.9, 0.0, 0.95);
	}
	
	ALBEDO = col;
	ALPHA = alpha;
}
