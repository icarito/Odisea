shader_type spatial;
render_mode depth_draw_alpha_prepass, cull_back;

uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular : hint_range(0,1) = 0.5;
uniform float metallic : hint_range(0,1) = 0.0;
uniform float roughness : hint_range(0,1) = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform bool uv1_triplanar = false;
uniform float uv1_blend_sharpness = 1.0;

varying vec3 uv1_triplanar_pos;
varying vec3 uv1_power_normal;

// --- Wall Occlusion Uniforms ---
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 1.5;
uniform float is_active = 0.0; // 0.0 or 1.0

varying vec3 world_pos;

void vertex() {
	if (!uv1_triplanar) {
		UV = UV * uv1_scale.xy + uv1_offset.xy;
	}
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	if (uv1_triplanar) {
		TANGENT = vec3(0.0,0.0,-1.0) * abs(NORMAL.x);
		TANGENT+= vec3(1.0,0.0,0.0) * abs(NORMAL.y);
		TANGENT+= vec3(1.0,0.0,0.0) * abs(NORMAL.z);
		TANGENT = normalize(TANGENT);
		BINORMAL = vec3(0.0,1.0,0.0) * abs(NORMAL.x);
		BINORMAL+= vec3(0.0,0.0,-1.0) * abs(NORMAL.y);
		BINORMAL+= vec3(0.0,1.0,0.0) * abs(NORMAL.z);
		BINORMAL = normalize(BINORMAL);
		uv1_power_normal=pow(abs(NORMAL),vec3(uv1_blend_sharpness));
		uv1_power_normal/=dot(uv1_power_normal,vec3(1.0));
		uv1_triplanar_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz * uv1_scale + uv1_offset;
		uv1_triplanar_pos *= vec3(1.0,-1.0, 1.0);
	}
}

vec4 triplanar_texture(sampler2D p_sampler,vec3 p_weights,vec3 p_triplanar_pos) {
	vec4 samp=vec4(0.0);
	samp+= texture(p_sampler,p_triplanar_pos.xy) * p_weights.z;
	samp+= texture(p_sampler,p_triplanar_pos.xz) * p_weights.y;
	samp+= texture(p_sampler,p_triplanar_pos.zy * vec2(-1.0,1.0)) * p_weights.x;
	return samp;
}

// 4x4 Dither Pattern function
float dither_pattern(vec2 position) {
	int x = int(mod(position.x, 4.0));
	int y = int(mod(position.y, 4.0));
	int index = x + y * 4;
	
	float limit = 0.0;
	if (index == 0) limit = 0.0625;
	if (index == 1) limit = 0.5625;
	if (index == 2) limit = 0.1875;
	if (index == 3) limit = 0.6875;
	if (index == 4) limit = 0.8125;
	if (index == 5) limit = 0.3125;
	if (index == 6) limit = 0.9375;
	if (index == 7) limit = 0.4375;
	if (index == 8) limit = 0.25;
	if (index == 9) limit = 0.75;
	if (index == 10) limit = 0.125;
	if (index == 11) limit = 0.625;
	if (index == 12) limit = 1.0;
	if (index == 13) limit = 0.5;
	if (index == 14) limit = 0.875;
	if (index == 15) limit = 0.375;
	
	return limit;
}

void fragment() {
	vec4 albedo_tex;
	if (uv1_triplanar) {
		albedo_tex = triplanar_texture(texture_albedo,uv1_power_normal,uv1_triplanar_pos);
	} else {
		albedo_tex = texture(texture_albedo, UV);
	}
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	METALLIC = metallic;

	ROUGHNESS = roughness;
	SPECULAR = specular;
	
	// --- Occlusion Logic ---
	if (is_active > 0.5) {
		vec3 cam_to_player = player_pos - camera_pos;
		float dist_cam_player = length(cam_to_player);
		vec3 dir_cam_player = normalize(cam_to_player);
		
		vec3 cam_to_frag = world_pos - camera_pos;
		
		// Projection of fragment onto the line of sight
		float t = dot(cam_to_frag, dir_cam_player);
		
		// Check if fragment is BETWEEN camera and player (with margins)
		if (t > 0.1 && t < (dist_cam_player - 0.1)) {
			
			// Radial distance from line of sight
			vec3 projection = camera_pos + dir_cam_player * t;
			float dist_radial = distance(world_pos, projection);
			
			if (dist_radial < hole_radius) {
				// Dithering based on screen coordinates for consistency
				if (dither_pattern(FRAGCOORD.xy) < 0.9) {
					discard;
				}
			}
		}
	}
}
