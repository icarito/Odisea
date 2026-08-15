shader_type spatial;
render_mode depth_draw_opaque;

// Conducción de plasma: carcasa metálica oscura y bandas cian que avanzan.
// Usa UV.y porque es el eje largo del CylinderMesh antes de su orientación en
// PipeSection; cada tramo se lee como conducción técnica, no como masa orgánica.
uniform vec4 base_color : hint_color = vec4(0.008, 0.018, 0.035, 1.0);
uniform vec4 flow_color : hint_color = vec4(0.03, 0.72, 1.0, 1.0);
uniform vec3 flow_dir = vec3(1.0, 0.0, 0.0);
uniform float noise_scale = 3.2;
uniform float flow_phase = 0.0;
uniform float emission_strength = 1.6;
uniform float pipe_alpha = 1.0;
uniform float flow_contrast = 0.5;
uniform float metallic_amount = 0.65;
uniform float roughness_amount = 0.28;

void fragment() {
	float bands = 0.5 + 0.5 * sin((UV.y * noise_scale - flow_phase) * 6.283185);
	float hot_band = smoothstep(0.72, 0.94, bands);

	ALBEDO = mix(base_color.rgb, flow_color.rgb * 0.16, hot_band * 0.35);
	EMISSION = flow_color.rgb * hot_band * emission_strength;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	ALPHA = pipe_alpha;
}
