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
uniform float blur_softness : hint_range(0.0, 2.0) = 0.8; // Controls the dreamy blur effect
uniform float edge_fade : hint_range(0.1, 3.0) = 1.2; // Controls how soft the edge transition is
uniform float wireframe_width : hint_range(0.5, 5.0) = 1.5; // Width of preserved wireframe edges
uniform vec4 wireframe_color : hint_color = vec4(0.3, 0.5, 0.7, 1.0); // Color tint for wireframe
uniform bool preserve_wireframe = true; // Toggle wireframe preservation
uniform float transparency_min : hint_range(0.0, 1.0) = 0.3; // Min transparency at edge of cone
uniform float transparency_max : hint_range(0.0, 1.0) = 0.95; // Max transparency at center of cone
uniform float floor_protect_radius : hint_range(0.5, 5.0) = 2.0; // Radius to protect floor under player

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 barycentric; // For edge detection

void vertex() {
	if (!uv1_triplanar) {
		UV = UV * uv1_scale.xy + uv1_offset.xy;
	}
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Generate barycentric-like coordinates from vertex ID for edge detection
	// This creates a pattern that helps detect triangle edges
	int vid = VERTEX_ID;
	int tri_vert = vid - (vid / 3) * 3; // 0, 1, or 2 within triangle
	if (tri_vert == 0) barycentric = vec3(1.0, 0.0, 0.0);
	else if (tri_vert == 1) barycentric = vec3(0.0, 1.0, 0.0);
	else barycentric = vec3(0.0, 0.0, 1.0);
	
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

// Smooth noise function for dreamy blur effect
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Smooth interpolation
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Multi-octave noise for organic blur
float dreamy_noise(vec2 uv, float time_offset) {
	float n = 0.0;
	n += smooth_noise(uv * 1.0 + time_offset) * 0.5;
	n += smooth_noise(uv * 2.0 - time_offset * 0.7) * 0.25;
	n += smooth_noise(uv * 4.0 + time_offset * 0.3) * 0.125;
	return n;
}

// Edge detection using barycentric coordinates (GLES2 compatible)
float detect_edge_bary() {
	// Detect triangle edges using barycentric coordinates
	vec3 bary = barycentric;
	// Find how close we are to any edge (edge = where one coord is near 0)
	float min_bary = min(min(bary.x, bary.y), bary.z);
	// Sharper edge detection with adjustable width
	float edge = 1.0 - smoothstep(0.0, wireframe_width * 0.05, min_bary);
	return edge;
}

// Silhouette edge detection using normal vs view angle (GLES2 compatible)
float detect_silhouette() {
	// Detect edges where the surface curves away sharply (silhouette)
	vec3 view_dir = normalize(camera_pos - world_pos);
	float ndotv = abs(dot(world_normal, view_dir));

	// Pixels near silhouette have low N.V (surface facing perpendicular to view)
	// This creates a nice outline effect on the outer edges
	float silhouette = 1.0 - smoothstep(0.0, 0.25, ndotv);

	return silhouette;
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
		
		// Check if fragment is BETWEEN camera and player
		if (t > 0.5 && t < dist_cam_player) {
			
			// Radial distance from line of sight
			vec3 projection = camera_pos + dir_cam_player * t;
			float dist_radial = distance(world_pos, projection);
			
			// CONE SHAPE: radius grows as we get closer to player
			float progress = t / dist_cam_player;
			float cone_radius = hole_radius * progress * edge_fade;

			if (dist_radial < cone_radius) {
				// --- FLOOR/CEILING EXCLUSION (only directly under/above player) ---
				// Check if this surface is directly below or above the player
				float horizontal_dist_to_player = length(world_pos.xz - player_pos.xz);
				bool near_player_horizontally = horizontal_dist_to_player < floor_protect_radius;

				// Floor: surface facing up (normal.y > 0.5), camera above surface, floor below player's feet
				bool is_floor = world_normal.y > 0.5;
				bool camera_above = camera_pos.y > world_pos.y;
				bool surface_below_player = world_pos.y < (player_pos.y - 0.5);
				bool floor_under_player = is_floor && camera_above && near_player_horizontally && surface_below_player;

				// Ceiling: surface facing down (normal.y < -0.5), camera below surface, ceiling above player's head
				bool is_ceiling = world_normal.y < -0.5;
				bool camera_below = camera_pos.y < world_pos.y;
				bool surface_above_player = world_pos.y > (player_pos.y + 2.0);
				bool ceiling_above_player = is_ceiling && camera_below && near_player_horizontally && surface_above_player;

				// Only skip occlusion for floor/ceiling directly at player's feet/head
				if (floor_under_player || ceiling_above_player) {
					// Don't discard - player is standing on this or it's right above their head
				} else {
					// How deep into the cone: 0 = edge, 1 = center (line of sight)
					float depth_in_cone = 1.0 - (dist_radial / cone_radius);

					// Add dreamy noise to the edge
					vec2 noise_uv = FRAGCOORD.xy * 0.08 * blur_softness;
					float noise = dreamy_noise(noise_uv, world_pos.x * 0.1 + world_pos.z * 0.1);
					float noisy_depth = depth_in_cone + (noise - 0.5) * blur_softness * 0.3;

					// Dither gradient: center = high transparency, edge = low transparency
					float dither = dither_pattern(FRAGCOORD.xy);

					// transparency from transparency_min (edge) to transparency_max (center)
					float transparency = mix(transparency_min, transparency_max, noisy_depth);

					if (dither < transparency) {
						discard;
					}
				}
			}
		}
	}
}
