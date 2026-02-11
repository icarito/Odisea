shader_type spatial;
render_mode cull_disabled;

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
	vec4 baseColor;
	vec4 maskColor;

	if (FRONT_FACING) {
		baseColor = texture(mainTexture, UV);
		maskColor = texture(maskTexture, UV);

		if (baseColor.a < alphaThreshold) {
			discard;
		}

		if (maskColor.a > 0.0) {
			// Calculate view direction in tangent space
			vec3 viewDir = normalize(
				normalize(-VERTEX) * mat3(
					TANGENT * uvFlip.x,
					-BINORMAL * uvFlip.y,
					NORMAL
				)
			);

			vec4 insideColor = vec4(0.0);

			// Layer 3
			vec2 uv3 = getParallaxUv(UV, viewDir, depth3);
			vec4 color3 = texture(texture3, uv3);
			insideColor = mix(insideColor, color3, color3.a);

			// Layer 2
			vec2 uv2 = getParallaxUv(UV, viewDir, depth2);
			vec4 color2 = texture(texture2, uv2);
			insideColor = mix(insideColor, color2, color2.a);

			// Layer 1
			vec2 uv1 = getParallaxUv(UV, viewDir, depth1);
			vec4 color1 = texture(texture1, uv1);
			insideColor = mix(insideColor, color1, color1.a);

			// Blend insideColor onto baseColor based on mask alpha
			baseColor.rgb = mix(
				baseColor.rgb,
				insideColor.rgb,
				maskColor.a * insideColor.a
			);
		}
	} else {
		baseColor = texture(backTexture, UV);
		maskColor = vec4(0.0);

		if (baseColor.a < alphaThreshold) {
			discard;
		}
	}

	ALBEDO = baseColor.rgb;

	// Set material properties
	ROUGHNESS = mix(roughnessOutside, roughnessInside, maskColor.a);
	SPECULAR = mix(specularOutside, specularInside, maskColor.a);
	METALLIC = mix(metallicOutside, metallicInside, maskColor.a);
}
