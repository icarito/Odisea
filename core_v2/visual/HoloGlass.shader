shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

uniform sampler2D texture_albedo : hint_albedo;
uniform vec4 albedo : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.0;
uniform float alpha_scissor_threshold = 0.0;

void fragment() {
    vec2 uv = UV;
    
    // UV is not flipped on back face, creating a natural mirror effect 
    // when seen from behind (through the glass)
    // User requested Y inversion for back face
    if (!FRONT_FACING) {
        uv.y = 1.0 - uv.y;
    }


    
    vec4 tex_color = texture(texture_albedo, uv);
    
    ALBEDO = tex_color.rgb * albedo.rgb;
    ALPHA = tex_color.a * albedo.a;
    EMISSION = ALBEDO * emission_energy;
    
    if (ALPHA < alpha_scissor_threshold) {
        discard;
    }
}
