shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

// Hologram Cyan Color
uniform vec4 holo_color : hint_color = vec4(0.0, 1.0, 1.0, 0.8);

// Emission intensity
uniform float emission_energy : hint_range(0.0, 5.0) = 2.0;

// Scanline effect
uniform float scanline_speed : hint_range(0.0, 10.0) = 2.0;
uniform float scanline_density : hint_range(1.0, 200.0) = 150.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.5;

// Rim/Fresnel glow
uniform float fresnel_power : hint_range(0.1, 10.0) = 3.0;

// Glitch/Noise
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.05;

void fragment() {
    // 1. Basic Fresnel Rim effect (GLES2 Compatible)
    // Compute dot product between normal and view direction
    float NdotV = dot(normalize(NORMAL), normalize(VIEW));
    // Clamp to avoid negative values
    NdotV = max(0.0, NdotV);
    float fresnel = pow(1.0 - NdotV, fresnel_power);
    
    // 2. Scanlines
    // Use SCREEN_UV.y or direct local vertex Y (FRAGCOORD for GLES2 robustness)
    float time_offset = TIME * scanline_speed;
    float scanline = sin((UV.y * scanline_density) - time_offset) * 0.5 + 0.5;
    
    // 3. Glitch Effect (Simple UV shift based on time sine waves)
    float glitch = step(0.95, sin(TIME * 15.0 + UV.y * 10.0)) * glitch_intensity;
    
    // Combine base color with fresnel rim and scanlines
    vec3 out_color = holo_color.rgb * emission_energy;
    
    // The core is slightly transparent, the edges (fresnel) are more opaque
    float base_alpha = holo_color.a;
    float final_alpha = base_alpha * (fresnel + 0.2); // +0.2 to keep the center slightly visible
    
    // Apply scanlines to darken certain horizontal bands
    final_alpha *= mix(1.0, scanline, scanline_strength);
    
    // Apply glitch opacity flashes
    final_alpha = mix(final_alpha, 0.0, glitch);
    
    // Output
    ALBEDO = out_color;
    // For GLES2 unshaded mode, we can just use ALBEDO as emission
    // but transparent blend mode uses ALPHA.
    ALPHA = clamp(final_alpha, 0.0, 1.0);
}
