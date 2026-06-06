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

// Simple 3D noise function
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

void vertex() {
    float n = noise(VERTEX * noise_scale + vec3(0.0, TIME * speed, 0.0));
    VERTEX += NORMAL * n * distortion_amount * intensity;
}

void fragment() {
    vec3 noise_coord = vec3(UV * noise_scale, TIME * speed);
    float n = noise(noise_coord);

    // Gradient along Y (v-axis)
    float mask = pow(1.0 - UV.y, 2.0);

    // Pulse
    float pulse = 0.8 + 0.2 * sin(TIME * pulse_frequency * 6.28);

    // Color phase shift
    vec4 final_color = mix(base_color, hot_color, color_phase + n * 0.5);

    ALBEDO = final_color.rgb * brightness * intensity * pulse * n;
    ALPHA = mask * intensity * n;
}
