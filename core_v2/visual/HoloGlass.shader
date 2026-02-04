shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

uniform sampler2D texture_albedo : hint_albedo;
uniform vec4 albedo : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.0;
uniform float alpha_scissor_threshold = 0.0;
uniform bool flip_h = false;
uniform bool flip_v = true;
uniform bool back_flip_h = false;
uniform bool back_flip_v = false;

void fragment() {
    vec2 uv = UV;
    
    if (FRONT_FACING) {
        if (flip_h) uv.x = 1.0 - uv.x;
        if (flip_v) uv.y = 1.0 - uv.y;
    } else {
        if (back_flip_h) uv.x = 1.0 - uv.x;
        if (back_flip_v) uv.y = 1.0 - uv.y;
    }

    vec4 tex_color = texture(texture_albedo, uv);
    
    ALBEDO = tex_color.rgb * albedo.rgb;
    ALPHA = max(tex_color.a, albedo.a);
    EMISSION = ALBEDO * emission_energy;
    
    if (ALPHA < alpha_scissor_threshold) {
        discard;
    }
}
