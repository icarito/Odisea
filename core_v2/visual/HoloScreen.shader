shader_type spatial;
// La textura del Viewport llega con el RGB PREMULTIPLICADO por el alfa de la UI pero con el
// canal alfa saturado a 255 (medido: el azul del theme, (48,106,153) al 62%, sale
// (30,66,95,255)). O sea: el alfa esta perdido, pero el BRILLO todavia lo codifica.
//
// Por eso el alfa se reconstruye abajo desde la luminancia, en vez de usar el canal alfa o
// de irse a blend_add. El aditivo tambien caló el fondo, pero volvia fantasma la tipografia:
// en aditivo TODO suma luz, tambien las letras.
//
// depth_draw_always: la proyeccion tiene que aportar SU profundidad o el desenfoque por
// distancia del ambiente muestrea el mundo lejano que se ve a traves y lo desenfoca encima.
render_mode cull_disabled, unshaded, blend_mix, depth_draw_always;

uniform sampler2D texture_albedo : hint_albedo;
uniform vec4 albedo : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.0;
uniform float alpha_scissor_threshold = 0.0;
// Opacidad del PANEL de vidrio del holograma. Se aplica al alfa y tambien a la emision:
// en unshaded la EMISSION se suma aparte del ALBEDO, asi que con emission_energy = 3 la
// pantalla sale ~4x mas brillante que su color y el fondo que deja pasar el alfa queda
// tapado por ese brillo. Bajando las dos, el panel se vuelve vidrio de verdad.
//
// Ojo: esto NO hace transparente la UI dibujada adentro del viewport. Eso es otro
// problema, sin resolver: los pixeles no pintados del viewport de los terminales salen
// negro opaco (los del selector radial del ascensor, con la misma config, salen
// transparentes).
// Opacidad del VIDRIO, o sea de la zona sin tinta. No toca las letras.
uniform float hologram_alpha : hint_range(0.0, 1.0) = 1.0;
// Brillo a partir del cual un pixel se considera tinta plena y se pinta opaco. Mas bajo =
// mas cosas de la UI se vuelven solidas.
uniform float ink_level : hint_range(0.05, 1.0) = 0.45;
uniform bool flip_h = false;
uniform bool flip_v = true;
uniform bool back_flip_h = false;
uniform bool back_flip_v = false;
uniform bool aligned_flip_h = false;
uniform bool aligned_flip_v = true;
uniform bool flip_h_when_viewed_from_back = false;
uniform bool flip_v_when_viewed_from_back = true;

void fragment() {
    vec2 uv = UV;
    
    if (FRONT_FACING) {
        if (flip_h) uv.x = 1.0 - uv.x;
        if (flip_v) uv.y = 1.0 - uv.y;
    } else {
        if (back_flip_h) uv.x = 1.0 - uv.x;
        if (back_flip_v) uv.y = 1.0 - uv.y;
    }

    vec3 camera_offset = CAMERA_MATRIX[3].xyz - WORLD_MATRIX[3].xyz;
    bool viewed_from_back = dot(camera_offset, normalize(WORLD_MATRIX[2].xyz)) < 0.0;
    if (viewed_from_back) {
        if (flip_h_when_viewed_from_back) uv.x = 1.0 - uv.x;
        if (flip_v_when_viewed_from_back) uv.y = 1.0 - uv.y;
    }

    if (aligned_flip_h) uv.x = 1.0 - uv.x;
    if (aligned_flip_v) uv.y = 1.0 - uv.y;

    vec4 tex_color = texture(texture_albedo, uv);
    
    // Cobertura reconstruida: la tinta (clara) llega a 1 y se pinta OPACA; el fondo del
    // panel (oscuro) cae a 0 y se ve a traves.
    float luma = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
    float coverage = clamp(luma / ink_level, 0.0, 1.0);
    // Como el RGB viene premultiplicado, se des-premultiplica con esa misma cobertura o el
    // texto saldria lavado, con el color a medio camino del fondo.
    ALBEDO = (tex_color.rgb / max(coverage, 0.02)) * albedo.rgb;
    // El atenuador solo baja el piso de vidrio; la tinta conserva su opacidad.
    ALPHA = max(coverage, albedo.a * hologram_alpha);
    EMISSION = ALBEDO * emission_energy * coverage;
    
    if (ALPHA < alpha_scissor_threshold) {
        discard;
    }
}
