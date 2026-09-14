shader_type canvas_item;
// HoloScreen.shader para una vista 2D (el control remoto, que no tiene el presentador 3D): mismo
// vidrio y misma tinta. La textura del Viewport llega con el RGB premultiplicado y el alfa perdido,
// asi que la cobertura se reconstruye desde la luminancia, igual que alla (ver HoloScreen.shader).
// HudViewMount le copia los valores del material de HudViewPresenter.tscn.

uniform vec4 albedo : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.0;
uniform float hologram_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float ink_level : hint_range(0.05, 1.0) = 0.45;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float luma = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	float coverage = clamp(luma / ink_level, 0.0, 1.0);
	vec3 color = (tex_color.rgb / max(coverage, 0.02)) * albedo.rgb;
	// En unshaded el 3D suma la emision al albedo: la tinta brilla, el vidrio no.
	COLOR = vec4(min(color * (1.0 + emission_energy * coverage), vec3(1.0)),
		max(coverage, albedo.a * hologram_alpha));
}
