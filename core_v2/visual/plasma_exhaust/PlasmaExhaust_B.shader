shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform sampler2D flipbook_tex : hint_albedo;
uniform vec2 grid_size = vec2(4.0, 4.0);
uniform float animation_speed = 10.0;
uniform vec4 tint_color : hint_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float emission_strength = 2.0;
uniform float intensity = 1.0;
uniform float color_phase = 0.0;

void fragment() {
    float total_frames = grid_size.x * grid_size.y;
    float frame = floor(mod(TIME * animation_speed, total_frames));

    vec2 frame_size = 1.0 / grid_size;
    vec2 frame_coord = vec2(mod(frame, grid_size.x), floor(frame / grid_size.x));

    vec2 uv = UV / grid_size + frame_coord * frame_size;

    vec4 tex = texture(flipbook_tex, uv);

    // Simple colorization based on color_phase
    vec3 final_tint = mix(tint_color.rgb, vec3(1.0, 1.0, 1.0), color_phase);

    ALBEDO = tex.rgb * final_tint * emission_strength * intensity;
    ALPHA = tex.a * intensity * (1.0 - UV.y);
}
