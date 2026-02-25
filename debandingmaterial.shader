shader_type spatial;
render_mode depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular = 0.5;
uniform float metallic = 0.0;
uniform float roughness : hint_range(0,1) = 1.0;
uniform sampler2D texture_roughness : hint_white;
uniform vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D texture_emission : hint_black_albedo;
uniform vec4 emission : hint_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float debanding_dither = 0.003;

const vec2 noise_magic = vec2(12.9898, 78.233);
varying vec3 world_pos;

void vertex() {
    UV = UV;
    world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    
    vec2 base_uv = UV;
    vec4 albedo_tex = texture(texture_albedo, base_uv);
    albedo_tex *= COLOR;
    
    // Stable world-space monochrome dither:
    // reduces visible lighting banding without camera-space flicker.
    vec3 noise_cell = floor(world_pos * 32.0);
    float noise = fract(sin(dot(noise_cell, vec3(noise_magic, 37.719))) * 43758.5453);
    float offset = (noise - 0.5) * debanding_dither;
    albedo_tex.rgb += vec3(offset);
    
    ALBEDO = albedo.rgb * albedo_tex.rgb;
    METALLIC = metallic;
    float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
    ROUGHNESS = roughness_tex * roughness;
    SPECULAR = specular;
    vec3 emission_tex = texture(texture_emission, base_uv).rgb;
    // Use emission color as fallback when no emission texture is provided
    vec3 emission_source = max(emission_tex, emission.rgb);
    EMISSION = emission_source * emission_energy;
}
