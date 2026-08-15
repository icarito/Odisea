shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform sampler2D flipbook_tex : hint_albedo;
uniform vec2 grid_size = vec2(8.0, 8.0);
uniform float animation_speed = 10.0;
uniform vec4 tint_color : hint_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float emission_strength = 2.0;
uniform float intensity = 1.0;
uniform float color_phase = 0.0;
uniform float wobble_amount = 0.06;  // sideways UV undulation
uniform float wobble_speed = 3.0;
uniform float taper = 0.7;           // plume narrows toward the tip
uniform float phase_offset = 0.0;    // per-layer flipbook phase (depth variation)
uniform float depth_offset = 0.0;    // per-layer offset along the billboard normal

void vertex() {
    // Axis-billboard: keep the quad's long axis aligned with the plume direction
    // (the node's local +Y, transformed to world — so it follows whatever the
    // parent container rotation is) and spin it around that axis to face the
    // camera. GLES2-safe.
    vec3 cam = (CAMERA_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 origin = (WORLD_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 up = normalize(WORLD_MATRIX[1].xyz);   // local +Y in world = plume axis
    vec3 to_cam = normalize(cam - origin);
    // Right vector perpendicular to the plume axis, rotated toward the camera.
    vec3 right = cross(up, to_cam);
    float rl = length(right);
    // Guard against the camera looking straight down the plume axis.
    right = rl > 0.001 ? right / rl : normalize(WORLD_MATRIX[0].xyz);
    vec3 facing = normalize(cross(right, up));  // billboard normal
    vec3 local = VERTEX;
    // depth_offset pushes this layer slightly toward/away from camera so stacked
    // layers read as volume rather than one flat sheet.
    vec3 world = origin + right * local.x + up * local.y + facing * (local.z + depth_offset);
    VERTEX = (inverse(WORLD_MATRIX) * vec4(world, 1.0)).xyz;
}

// Continuous cross-fade between adjacent flipbook frames (no discrete puffs).
vec4 sample_flipbook(vec2 local, float t) {
    float total = grid_size.x * grid_size.y;
    float fpos = mod(t, total);
    float f0 = floor(fpos);
    float f1 = mod(f0 + 1.0, total);
    float blend = fract(fpos);
    vec2 fs = 1.0 / grid_size;
    vec2 c0 = vec2(mod(f0, grid_size.x), floor(f0 / grid_size.x));
    vec2 c1 = vec2(mod(f1, grid_size.x), floor(f1 / grid_size.x));
    vec4 t0 = texture(flipbook_tex, clamp(local, 0.0, 1.0) * fs + c0 * fs);
    vec4 t1 = texture(flipbook_tex, clamp(local, 0.0, 1.0) * fs + c1 * fs);
    return mix(t0, t1, blend);
}

void fragment() {
    float along = UV.y;  // 0 base .. 1 tip

    // Undulate sideways, stronger toward the tip, so the flame waves like a
    // real plume instead of a static sheet.
    float wob = sin(UV.y * 6.2831 * 1.5 + TIME * wobble_speed) * wobble_amount * along;

    // Narrow toward the tip for a directional plume.
    float width = mix(1.0, 1.0 - taper, along);
    float centered = (UV.x - 0.5 + wob) / max(width, 0.001) + 0.5;

    vec4 tex = sample_flipbook(vec2(centered, UV.y), TIME * animation_speed + phase_offset);

    vec3 final_tint = mix(tint_color.rgb, vec3(1.0, 1.0, 1.0), color_phase);

    float side_mask = step(abs(centered - 0.5), 0.5);
    float tip_mask = 1.0 - along;

    ALBEDO = tex.rgb * final_tint * emission_strength * intensity;
    ALPHA = tex.a * intensity * tip_mask * side_mask;
}
