// Reja del hueco del ascensor. Vivia duplicada byte a byte en dos sub_resource del
// .tscn (ids 5 y 11): dos recursos Shader identicos son dos programas distintos para
// el rasterizador, y en Adreno cada programa cuesta cientos de milisegundos al entrar
// a la escena. Los dos materiales solo diferian en el uniform tiling, que es por
// material, asi que comparten este archivo sin cambiar un pixel.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 fence_color : hint_color = vec4(0.35, 0.35, 0.35, 1.0);
uniform vec2 tiling = vec2(10.0, 10.0);
uniform float wire_thickness : hint_range(0.01, 0.5) = 0.08;
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 0.5;
uniform float is_active = 0.0;
uniform float edge_fade = 1.0;
uniform float transparency_min = 0.3;
uniform float transparency_max = 0.95;
varying vec3 world_pos;

void vertex() { world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float occlusion_noise(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }

void fragment() {
    if (is_active > 0.5) {
        vec3 ray = player_pos - camera_pos;
        float ray_length = length(ray);
        vec3 direction = ray / max(ray_length, 0.001);
        float along = dot(world_pos - camera_pos, direction);
        if (along > 0.1 && along < ray_length) {
            float radial = distance(world_pos, camera_pos + direction * along);
            float radius = hole_radius * edge_fade * (1.0 - smoothstep(ray_length - 1.5, ray_length, along));
            if (radial < radius && radius > 0.01 && occlusion_noise(FRAGCOORD.xy) < mix(transparency_min, transparency_max, 1.0 - radial / radius)) { discard; }
        }
    }
    vec2 uv = UV * tiling;
    vec2 grid_uv = fract(vec2(uv.x + uv.y, uv.x - uv.y) * 0.5);
    float line_x = step(grid_uv.x, wire_thickness) + step(1.0 - wire_thickness, grid_uv.x);
    float line_y = step(grid_uv.y, wire_thickness) + step(1.0 - wire_thickness, grid_uv.y);
    float alpha = clamp(max(line_x, line_y), 0.0, 1.0);
    if (alpha < 0.5) { discard; }
    ALBEDO = fence_color.rgb * 0.8;
    METALLIC = 1.0;
    ROUGHNESS = 0.5;
    vec2 center_dist = abs(grid_uv - 0.5) * 2.0;
    float d = max(center_dist.x, center_dist.y);
    float ao = smoothstep(1.0 - wire_thickness * 2.0, 1.0, d);
    ALBEDO *= mix(1.0, 0.5, ao);
}
