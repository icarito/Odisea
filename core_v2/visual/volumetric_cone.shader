shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform vec4 color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;
uniform float falloff_exponent : hint_range(0.1, 5.0) = 2.0;

uniform bool use_mask = false;
uniform sampler2D mask : hint_albedo;
uniform float mask_scroll = 0.0;
uniform vec2 mask_tiling = vec2(1.0, 1.0);

// CylinderMesh solo llega a UV.y = 0.5 en el lateral; con 2.0 el falloff alcanza 0
// en la punta del cono. 1.0 = comportamiento previo (SearchLightV2).
uniform float uv_length_scale : hint_range(0.5, 4.0) = 1.0;
// 0.0 = borde duro (comportamiento previo). >0 difumina la silueta del cono.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Simple distance falloff along Z (assuming cone height is 1.0 in local space)
	// In Godot 3, vertex position in fragment is in view space.
	// We'll use the UV.y which usually maps to the height of primitive meshes.
	float falloff = pow(1.0 - clamp(UV.y * uv_length_scale, 0.0, 1.0), falloff_exponent);

	// Edge softening: la silueta del cono es donde la superficie queda de canto
	// respecto de la camara (N.V ~ 0). abs() porque cull_disabled da normales invertidas.
	float edge = 1.0;
	if (edge_softness > 0.0) {
		edge = smoothstep(0.0, edge_softness, abs(dot(normalize(NORMAL), normalize(VIEW))));
	}

	float mask_factor = 1.0;
	if (use_mask) {
		vec2 mask_uv = UV * mask_tiling + vec2(0.0, mask_scroll);
		vec4 mask_tex = texture(mask, mask_uv);
		mask_factor = mask_tex.r * mask_tex.a;
	}

	ALBEDO = color.rgb;
	ALPHA = color.a * falloff * edge * alpha_multiplier * 0.3 * mask_factor;
}
