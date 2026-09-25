extends GdUnitTestSuite

# Rejillas del scaffold: la grilla tiene que leerse sobre el piso casi negro de
# RingHub en DARK sin volverse neon. El fix es una emision tenue en las barras
# (SteelGratePlatform.grate_emission_energy), aplicada solo por la fuente de
# RingHub; Dome_Intro conserva su grilla puramente lit.

const PlatformScene = preload("res://core_v2/props/scaffold/SteelGratePlatform.tscn")
const RINGHUB_WALKWAYS := "res://core_v2/levels/interiors/RingHub_SpiralWalkways_baked.mesh"
const DOMEINTRO_WALKWAYS := "res://core_v2/levels/interiors/DomeIntro_SpiralWalkways_baked.mesh"
# En tier flat el gate mapea la emision a glow = clamp(max(em)*4, 0.25, 1); por
# encima de ~0.15 la rejilla ya no es "apenas visible" sino una luz de neon.
const MAX_SUBTLE_PEAK := 0.15


func _find_grate_surface(mesh: ArrayMesh) -> SpatialMaterial:
	if mesh == null:
		return null
	for i in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(i)
		if mat is SpatialMaterial and (mat as SpatialMaterial).params_use_alpha_scissor:
			return mat as SpatialMaterial
	return null


func test_grate_emission_defaults_off() -> void:
	# El default no toca nada: cualquier SteelGratePlatform fuera de RingHub
	# (Dome_Intro, props sueltos) sigue siendo acero puramente lit.
	var platform = auto_free(PlatformScene.instance())
	add_child(platform)
	yield(get_tree(), "idle_frame")

	var deck = platform.get_node_or_null("VisualRoot/DeckGrate")
	assert_object(deck).is_not_null()
	var mat: Material = deck.material_override
	assert_bool(mat is SpatialMaterial).is_true()
	assert_bool((mat as SpatialMaterial).emission_enabled).is_false()


func test_grate_emission_energy_lifts_bars_subtly() -> void:
	var platform = auto_free(PlatformScene.instance())
	platform.grate_emission_energy = 0.25
	add_child(platform)
	yield(get_tree(), "idle_frame")

	var deck = platform.get_node_or_null("VisualRoot/DeckGrate")
	assert_object(deck).is_not_null()
	var mat: SpatialMaterial = deck.material_override as SpatialMaterial
	assert_bool(mat.emission_enabled).is_true()
	# La malla del deck es alpha-scissor: emiten las barras, no los huecos.
	assert_bool(mat.params_use_alpha_scissor).is_true()
	assert_bool(mat.albedo_texture != null).is_true()
	var peak: float = max(mat.emission.r, max(mat.emission.g, mat.emission.b))
	assert_bool(peak > 0.04).is_true()
	assert_bool(peak <= MAX_SUBTLE_PEAK).is_true()


func test_ringhub_grate_is_emissive() -> void:
	var grate := _find_grate_surface(load(RINGHUB_WALKWAYS))
	assert_object(grate).is_not_null()
	assert_bool(grate.emission_enabled).is_true()
	var peak: float = max(grate.emission.r, max(grate.emission.g, grate.emission.b))
	assert_bool(peak > 0.04).is_true()
	assert_bool(peak <= MAX_SUBTLE_PEAK).is_true()


func test_dome_intro_grate_stays_lit_only() -> void:
	# Regresion de radio de impacto: el re-hornear RingHub no debe encender la
	# grilla de Dome_Intro (misma textura/material base, distinta fuente).
	var grate := _find_grate_surface(load(DOMEINTRO_WALKWAYS))
	assert_object(grate).is_not_null()
	assert_bool(grate.emission_enabled).is_false()
