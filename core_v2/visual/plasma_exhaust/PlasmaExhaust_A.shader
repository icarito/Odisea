shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform vec4 base_color : hint_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform vec4 hot_color : hint_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float noise_scale = 2.0;
uniform float distortion_amount = 0.5;
uniform float speed = 1.0;
uniform float intensity = 1.0;
uniform float color_phase = 0.0;
uniform float brightness = 2.0;
uniform float pulse_frequency = 1.0;
uniform float flame_sharpness = 0.5;

// Simple 3D value noise
float hash(vec3 p) {
    p = fract(p * 0.3183099 + .1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Fractal noise (4 octaves) for smoother, more organic flow
float fbm(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// Turbulent (ridged) variant — sharper licks, more flame-like than smooth fbm.
float turbulence(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * abs(noise(p) * 2.0 - 1.0);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

void vertex() {
    // Plasma flows upward (local +Y): scroll the noise field down over time
    // and bias the displacement toward the flow axis so it reads as a rising
    // column, not a randomly dented tube.
    vec3 flow = VERTEX * noise_scale + vec3(0.0, TIME * speed * 2.0, 0.0);
    float n = fbm(flow);
    // Taper displacement toward the tip so the base stays anchored.
    float taper = clamp(UV.y, 0.0, 1.0);
    vec3 dir = normalize(NORMAL + vec3(0.0, 1.0, 0.0));
    VERTEX += dir * (n - 0.5) * distortion_amount * intensity * taper;
}

void fragment() {
    // Two layers scrolling at different speeds → flowing, churning plasma
    // rather than a static noise shell on a cone.
    vec3 coord_a = vec3(UV * noise_scale, 0.0) + vec3(0.0, TIME * speed, 0.0);
    vec3 coord_b = vec3(UV * noise_scale * 2.0 + 5.0, 0.0) + vec3(0.0, TIME * speed * 1.7, 0.0);
    float n = mix(fbm(coord_a), turbulence(coord_b), 0.5);

    // Bright core near the base, fading toward the tip and toward the
    // silhouette edges (UV.x at 0/1).
    float tip_fade = pow(1.0 - UV.y, 1.5);
    float edge_fade = sin(UV.x * 3.14159);
    float mask = tip_fade * edge_fade;

    // Flicker instead of a uniform pulse.
    float pulse = 0.7 + 0.3 * sin(TIME * pulse_frequency * 6.28 + n * 6.28);

    // Hotter core where noise is dense.
    vec4 final_color = mix(base_color, hot_color, clamp(color_phase + n, 0.0, 1.0));

    ALBEDO = final_color.rgb * brightness * intensity * pulse * (0.6 + n);
    // Carve flame tongues out of the noise so it isn't a solid tube.
    // flame_sharpness narrows the smoothstep band → crisper licks.
    float lo = mix(0.2, 0.45, flame_sharpness);
    float hi = mix(0.7, 0.95, flame_sharpness);
    float flame = smoothstep(lo, hi, n) * mask;
    ALPHA = clamp(flame * intensity, 0.0, 1.0);
}
