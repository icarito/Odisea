shader_type spatial;
render_mode cull_back, depth_draw_alpha_prepass;

// --- Lightmap horneado aplicado a mano (solo iOS) ---------------------------------
// Godot ata su lightmap a "max_texture_image_units - 4": unidad 12 en Android, 4 en
// iOS, donde choca con las texturas del material y con screen/depth_texture. La
// colision es silenciosa (sin error de linkeo) y el bake no se dibuja. El aplicador
// (IOSLightmapFallback.gd) setea estos dos uniforms para muestrearlo aca, en una
// unidad secuencial. Con energia 0 esto no hace NADA: en escritorio y Android sigue
// mandando el camino nativo del motor.
uniform sampler2D lightmap_tex : hint_albedo;
uniform float lightmap_energy = 0.0;

// Material settings
uniform float roughnessInside : hint_range(0.0, 1.0) = 1.0;
uniform float roughnessOutside : hint_range(0.0, 1.0) = 1.0;
uniform float specularInside : hint_range(0.0, 1.0) = 0.0;
uniform float specularOutside : hint_range(0.0, 1.0) = 0.0;
uniform float metallicInside : hint_range(0.0, 1.0) = 0.0;
uniform float metallicOutside : hint_range(0.0, 1.0) = 0.0;

// Base card settings
uniform sampler2D mainTexture : hint_albedo;
uniform sampler2D backTexture : hint_albedo;
uniform vec2 uvFlip = vec2(-1.0, -1.0);
uniform vec2 aspectRatio = vec2(1.0, 1.0);
uniform float alphaThreshold : hint_range(0.0, 1.0) = 0.5;
uniform bool lockVerticalParallax = true;

// Animation settings
uniform float animationSpeed : hint_range(0.0, 10.0) = 1.0;
uniform float animationIntensity : hint_range(0.0, 0.5) = 0.02;

// Card mask settings
uniform sampler2D maskTexture : hint_albedo;

// Layer 1 settings
uniform float depth1 : hint_range(0.0, 1.0) = 0.05;
uniform sampler2D texture1 : hint_albedo;

// Layer 2 settings
uniform float depth2 : hint_range(0.0, 1.0) = 0.1;
uniform sampler2D texture2 : hint_albedo;

// Layer 3 settings
uniform float depth3 : hint_range(0.0, 1.0) = 0.15;
uniform sampler2D texture3 : hint_albedo;

uniform float yOffset : hint_range(-1.0, 1.0) = 0.0;
uniform float grazing_noise_strength : hint_range(0.0, 0.02) = 0.0025;
uniform float grazing_noise_scale : hint_range(1.0, 64.0) = 18.0;

// --- Occlusion uniforms (updated per-frame by PropDitherManager) ---
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 0.5;
uniform float is_active = 0.0;
uniform float edge_fade : hint_range(0.1, 3.0) = 1.0;
uniform float transparency_min : hint_range(0.0, 1.0) = 0.3;
uniform float transparency_max : hint_range(0.0, 1.0) = 0.95;
uniform float floor_protect_radius : hint_range(0.5, 5.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

// Helper to offset UV based on view direction and depth
vec2 getParallaxUv(vec2 uv, vec3 viewDir, float depth) {
	// Adjust view direction xy by aspect ratio
	vec2 adjustedViewDirXy = viewDir.xy / (aspectRatio / length(aspectRatio));
	
	if (lockVerticalParallax) {
		adjustedViewDirXy.y = 0.0;
	}

	// Protect against grazing angles (division by zero)
	float vdz = viewDir.z;
	if (abs(vdz) < 0.05) vdz = 0.05 * sign(vdz);
	if (vdz == 0.0) vdz = 0.05;

	return clamp(
		uv + (adjustedViewDirXy / vdz) * depth,
		vec2(0.0),
		vec2(1.0)
	);
}

void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	// Match the main dither shader: discard first so hidden fragments do not
	// contribute color/emission before the occlusion test resolves.
	if (is_active > 0.5) {
		vec3 cam_to_player = player_pos - camera_pos;
		float dist_cam_player = length(cam_to_player);
		vec3 dir_cam_player = cam_to_player / dist_cam_player;
		vec3 cam_to_frag = world_pos - camera_pos;
		float t = dot(cam_to_frag, dir_cam_player);

		if (t > 0.1 && t < dist_cam_player) {
			vec3 projection = camera_pos + dir_cam_player * t;
			float dist_radial = distance(world_pos, projection);
			float taper = 1.0 - smoothstep(dist_cam_player - 1.5, dist_cam_player, t);
			float cylinder_radius = hole_radius * edge_fade * taper;

			if (dist_radial < cylinder_radius && cylinder_radius > 0.01) {
				float horizontal_dist = length(world_pos.xz - player_pos.xz);
				bool near_h = horizontal_dist < floor_protect_radius;
				bool floor_under = world_normal.y > 0.5 && camera_pos.y > world_pos.y && near_h && world_pos.y < (player_pos.y - 0.5);
				bool ceiling_above = world_normal.y < -0.5 && camera_pos.y < world_pos.y && near_h && world_pos.y > (player_pos.y + 2.0);

				if (!floor_under && !ceiling_above) {
					float depth_in_cone = 1.0 - (dist_radial / cylinder_radius);
					float transparency = mix(transparency_min, transparency_max, depth_in_cone);
					if (ign(FRAGCOORD.xy) < transparency) {
						discard;
					}
				}
			}
		}
	}

	// Simple parallax for capsule
	// We assume we are looking into the capsule.
	
	vec3 viewDir = normalize(normalize(-VERTEX) * mat3(TANGENT * uvFlip.x, -BINORMAL * uvFlip.y, NORMAL));
	
	// Create flipped UV for the pilot content (appears upside down otherwise)
	// Apply Y-offset here
	vec2 pilotUV = vec2(UV.x, (1.0 - UV.y) + yOffset);

	// Break up moire/aliasing when the camera sees the card at grazing angles.
	// The jitter is stable in world space to avoid frame-to-frame shimmer.
	vec3 view_world = normalize(camera_pos - world_pos);
	float grazing = 1.0 - abs(dot(normalize(world_normal), view_world));
	grazing = grazing * grazing;
	float noise = ign(floor(world_pos.xz * grazing_noise_scale)) - 0.5;
	vec2 grazing_noise = vec2(noise, -noise * 0.7) * grazing_noise_strength * grazing;
	pilotUV += grazing_noise;

	// Breath Animation (Glow)
	float pulse = (sin(TIME * animationSpeed) * 0.5 + 0.5) * animationIntensity;
	vec3 glowColor = vec3(0.0, 1.0, 1.0); // Cyan
	
	// Base layer (Deepest - The Pilot)
	vec2 uv3 = getParallaxUv(pilotUV, viewDir, depth3);
	vec4 color3 = texture(texture3, uv3);
	
	vec3 finalColor = color3.rgb;
	float finalAlpha = color3.a;
	
	// Middle layer (Optional)
	vec2 uv2 = getParallaxUv(pilotUV, viewDir, depth2);
	vec4 color2 = texture(texture2, uv2);
	finalColor = mix(finalColor, color2.rgb, color2.a * 0.3);
	
	// Front layer (Optional)
	vec2 uv1 = getParallaxUv(pilotUV, viewDir, depth1);
	vec4 color1 = texture(texture1, uv1);
	finalColor = mix(finalColor, color1.rgb, color1.a * 0.2);
	
	// Apply Glow
	finalColor += glowColor * pulse;
	
	// Frame/Mask (Optional)
	vec4 maskColor = texture(maskTexture, UV);
	vec4 frameColor = texture(mainTexture, UV);
	
	// If mask is used, blend frame over parallax content where mask is black
	// Assuming mask white = window, black = frame
	// If no mask, assume whole capsule is window
	
	// For capsule, we might not have a mask, so let's blend frame based on alpha?
	// Or just mix based on mask texture
	
	if (maskColor.a > 0.1) {
		// Window area
		// Multiply parallax content by mask intensity
		// But usually mask is binary.
		// Let's just output the parallax content
	} else {
		// Frame area
		// finalColor = frameColor.rgb;
		// actually, if we want optional frame, we should check opacity of frame texture?
	}
	
	// Simplified blending: Frame is top layer
	// Frame is shown where mask is black (0.0)
	float maskVal = maskColor.r; // mask is usually grayscale
	
	// If the mask is present (alpha > 0), use it. otherwise assume full window.
	// But current textures might just use color.
	
	// Blend Parallax Content and Frame
	// Where mask is 1.0 (white), we see the pilot (finalColor).
	// Where mask is 0.0 (black), we see the frame (frameColor).
	
	vec3 outColor = mix(frameColor.rgb, finalColor.rgb, maskVal);
	float outAlpha = mix(frameColor.a, 1.0, maskVal); // Pilot/Inside is opaque (1.0)
	
	ALBEDO = outColor;
	ALPHA = outAlpha;
	EMISSION = glowColor * pulse * maskVal; // Only glow inside the window
	
	// Extra boost for the pilot (Texture 3)
	// We use the alpha of color3 to determine where the pilot is
	float pilotAlpha = texture(texture3, uv3).a;
	EMISSION += glowColor * pulse * pilotAlpha * 2.0; // Double intensity for pilot
	
	// Material properties
	ROUGHNESS = roughnessInside;
	METALLIC = metallicInside;
	SPECULAR = specularInside;


	if (lightmap_energy > 0.0) {
		EMISSION += ALBEDO * texture(lightmap_tex, UV2).rgb * lightmap_energy;
	}
}
