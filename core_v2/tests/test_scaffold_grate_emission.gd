extends GdUnitTestSuite

# Rejillas del scaffold: la grilla tiene que leerse sobre el piso casi negro de
# RingHub en DARK sin volverse neon. El fix es una emision tenue en las barras
# (SteelGratePlatform.grate_emission_energy), aplicada solo por la fuente de
# RingHub; Dome_Intro conserva su grilla puramente lit.

const PlatformScene = preload("res://core_v2/props/scaffold/SteelGratePlatform.tscn")
const HubRingScene = preload("res://core_v2/props/scaffold/ScaffoldHubRing.tscn")
const RINGHUB_LEVEL := "res://core_v2/levels/RingHub_Level.tscn"
const RINGHUB_WALKWAYS := "res://core_v2/levels/interiors/RingHub_SpiralWalkways_baked.mesh"
const DOMEINTRO_WALKWAYS := "res://core_v2/levels/interiors/DomeIntro_SpiralWalkways_baked.mesh"
# Piso de los niveles del ring (deck-top de ScaffoldHubRing). Artefacto horneado
# de Dome_Intro, para probar que el default 0.0 sigue siendo lit-only.
const DOMEINTRO_RING_FLOOR := "res://core_v2/levels/interiors/Dome_Intro_Floor_1_baked.mesh"
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


func _ring_deck_surface(ring: Spatial) -> SpatialMaterial:
	var visual = ring.get_node_or_null("CombinedMesh")
	if visual == null:
		return null
	return _find_grate_surface(visual.mesh as ArrayMesh)


func test_hub_ring_grate_emission_defaults_off() -> void:
	# Default 0.0: cualquier anillo fuera de RingHub (Dome_Intro y demas) queda
	# con el deck-top puramente lit.
	var ring: Spatial = auto_free(HubRingScene.instance())
	add_child(ring)
	yield(get_tree(), "idle_frame")

	var grate := _ring_deck_surface(ring)
	assert_object(grate).is_not_null()
	assert_bool(grate.params_use_alpha_scissor).is_true()
	assert_bool(grate.emission_enabled).is_false()


func test_hub_ring_grate_emission_energy_lifts_deck_subtly() -> void:
	var ring: Spatial = auto_free(HubRingScene.instance())
	ring.grate_emission_energy = 0.25
	add_child(ring)
	yield(get_tree(), "idle_frame")

	var grate := _ring_deck_surface(ring)
	assert_object(grate).is_not_null()
	assert_bool(grate.emission_enabled).is_true()
	# Solo emiten las barras: la superficie del deck es alpha-scissor con textura.
	assert_bool(grate.params_use_alpha_scissor).is_true()
	assert_bool(grate.albedo_texture != null).is_true()
	var peak: float = max(grate.emission.r, max(grate.emission.g, grate.emission.b))
	assert_bool(peak > 0.04).is_true()
	assert_bool(peak <= MAX_SUBTLE_PEAK).is_true()
	# Las caras laterales/vigas del anillo no heredan la emision.
	var side: Material = (ring.get_node("CombinedMesh").mesh as ArrayMesh).surface_get_material(1)
	assert_bool((side as SpatialMaterial).emission_enabled).is_false()


func test_ringhub_level_ring_floors_follow_lit_dark() -> void:
	# acabcc9d saco la emision constante 0.25 de los decks del hub (RingFloor y
	# Floor_2..5): ahora son acero puramente lit, para que sigan LIT/DARK y el bake
	# les proyecte sombra. El brillo de DARK lo maneja el light state, no una
	# emision fija en el material (ver test_hub_ring_grate_emission_*).
	var level: Spatial = auto_free(load(RINGHUB_LEVEL).instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	for floor_name in ["RingFloor", "Floor_2", "Floor_3", "Floor_4", "Floor_5"]:
		var ring: Spatial = level.get_node_or_null("Hub/%s" % floor_name)
		assert_object(ring).is_not_null()
		assert_float(ring.grate_emission_energy).is_equal(0.0)
		var grate := _ring_deck_surface(ring)
		assert_object(grate).is_not_null()
		assert_bool(grate.emission_enabled).is_false()


func test_dome_intro_hub_ring_stays_lit_only() -> void:
	# Mismo default 0.0 en el anillo horneado del Dome: sin emision.
	var grate := _find_grate_surface(load(DOMEINTRO_RING_FLOOR))
	assert_object(grate).is_not_null()
	assert_bool(grate.params_use_alpha_scissor).is_true()
	assert_bool(grate.emission_enabled).is_false()
