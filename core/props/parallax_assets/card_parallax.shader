shader_type spatial;
render_mode cull_disabled, depth_draw_alpha_prepass;

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

// Helper to offset UV based on view direction and depth
vec2 getParallaxUv(vec2 uv, vec3 viewDir, float depth) {
	// Adjust view direction xy by aspect ratio
	vec2 adjustedViewDirXy = viewDir.xy / (aspectRatio / length(aspectRatio));
	return clamp(
		uv + (adjustedViewDirXy / viewDir.z) * depth,
		vec2(0.0),
		vec2(1.0)
	);
}

void fragment() {
	// Simple parallax for capsule
	// We assume we are looking into the capsule.
	
	vec3 viewDir = normalize(normalize(-VERTEX) * mat3(TANGENT * uvFlip.x, -BINORMAL * uvFlip.y, NORMAL));
	
	// Base layer (Deepest - The Pilot)
	vec2 uv3 = getParallaxUv(UV, viewDir, depth3);
	vec4 color3 = texture(texture3, uv3);
	
	vec3 finalColor = color3.rgb;
	float finalAlpha = color3.a;
	
	// Middle layer (Optional)
	vec2 uv2 = getParallaxUv(UV, viewDir, depth2);
	vec4 color2 = texture(texture2, uv2);
	finalColor = mix(finalColor, color2.rgb, color2.a * 0.3);
	
	// Front layer (Optional)
	vec2 uv1 = getParallaxUv(UV, viewDir, depth1);
	vec4 color1 = texture(texture1, uv1);
	finalColor = mix(finalColor, color1.rgb, color1.a * 0.2);
	
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
	
	// Back face logic?
	if (!FRONT_FACING) {
		// Just show dark back or same content dimmed
		outColor *= 0.3; 
	}

	ALBEDO = outColor;
	ALPHA = outAlpha;
	
	// Material properties
	ROUGHNESS = roughnessInside;
	METALLIC = metallicInside;
	SPECULAR = specularInside;
}
