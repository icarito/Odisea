shader_type spatial;
render_mode depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : hint_albedo;
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 3.5;
uniform float softness = 1.5;
uniform bool debug_mode = false;
uniform bool use_triplanar = true;
uniform float uv_scale = 1.0;
uniform float cutoff_offset = 0.7;

varying vec3 world_pos;
varying vec3 world_normal;

// Matriz de Dithering 4x4
float dither_pattern(vec2 position) {
    int x = int(mod(position.x, 4.0));
    int y = int(mod(position.y, 4.0));
    int index = x + y * 4;
    float threshold[16];
    threshold[0] = 0.0625; threshold[1] = 0.5625; threshold[2] = 0.1875; threshold[3] = 0.6875;
    threshold[4] = 0.8125; threshold[5] = 0.3125; threshold[6] = 0.9375; threshold[7] = 0.4375;
    threshold[8] = 0.25;   threshold[9] = 0.75;   threshold[10] = 0.125;  threshold[11] = 0.625;
    threshold[12] = 1.0;   threshold[13] = 0.5;   threshold[14] = 0.875;  threshold[15] = 0.375;
    return threshold[index];
}

void vertex() {
    world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = (WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    // 1. Calcular color base (Triplanar o UV)
    vec3 albedo;
    if (use_triplanar) {
        vec3 blending = abs(world_normal);
        blending /= (blending.x + blending.y + blending.z);
        
        vec3 x_tex = texture(albedo_texture, world_pos.zy * uv_scale).rgb;
        vec3 y_tex = texture(albedo_texture, world_pos.xz * uv_scale).rgb;
        vec3 z_tex = texture(albedo_texture, world_pos.xy * uv_scale).rgb;
        
        albedo = x_tex * blending.x + y_tex * blending.y + z_tex * blending.z;
    } else {
        albedo = texture(albedo_texture, UV).rgb;
    }
    
    ALBEDO = albedo;
    
    // 2. Lógica de Ocultación (Distancia a la línea Cámara-Jugador)
    vec3 line_dir = player_pos - camera_pos;
    float line_len = length(line_dir);
    vec3 line_unit = line_dir / line_len;
    
    vec3 frag_to_cam = world_pos - camera_pos;
    float t = dot(frag_to_cam, line_unit);
    
    // Proyectar fragmento sobre el segmento Cámara-Jugador
    vec3 projection = camera_pos + max(t, 0.0) * line_unit;
    float dist = distance(world_pos, projection);
    
    // 2. Máscara de Ocultación Conica
    // Escalamos el radio basándonos en la posición a lo largo de la línea base.
    // Esto hace que el agujero se abra como un cono desde la cámara hacia el jugador.
    float cone_factor = mix(0.1, 1.0, t / line_len);
    float final_radius = hole_radius * cone_factor;
    float mask = smoothstep(final_radius, final_radius + softness, dist);
    
    // 1. Smart Floor Protection
    // Protect floors (Normal +Y) that are at or below the player's general level.
    // This keeps the ground solid between camera and player without protecting roofs.
    if (world_normal.y > 0.5 && camera_pos.y > world_pos.y) {
        if (world_pos.y <= player_pos.y + 0.5) {
            mask = 1.0;
        }
    }
    
    // 2. Background Plane Protection
    // Surfaces beyond the player's plane (from camera perspective) stay solid.
    float plane_mask = smoothstep(line_len - cutoff_offset - softness, line_len - cutoff_offset, t);
    mask = mix(mask, 1.0, plane_mask); 
    
    // Debug: Mostrar un tinte rojo si el dither descartaría el fragmento
    if (debug_mode && dither_pattern(FRAGCOORD.xy) > mask) {
        ALBEDO = mix(ALBEDO, vec3(1.0, 0.0, 0.0), 0.5);
    }
    
    // 3. Aplicar Dithering (Punch Hole)
    if (dither_pattern(FRAGCOORD.xy) > mask) {
        discard;
    }
}
