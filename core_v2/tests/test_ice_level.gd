extends GdUnitTestSuite

const IceLevelScript = preload("res://core_v2/systems/ice/IceLevel.gd")
const IceObjectFreezerScript = preload("res://core_v2/systems/ice/IceObjectFreezer.gd")
const FrostVignetteScene = preload("res://core_v2/ui/overlay/FrostVignette.tscn")
const STEP := 1.0 / 60.0

class DummyBody extends Spatial:
	func _init() -> void:
		add_to_group("ice_vulnerable")

func _make_level(auto_start: bool = true) -> Node:
	var level = auto_free(IceLevelScript.new())
	level.auto_start = auto_start
	level.debug_draw = false
	add_child(level)
	return level

func test_ice_rise_and_snapshot_are_deterministic() -> void:
	var level = _make_level()
	level.base_speed = 0.5
	level.accel = 0.1
	level.reset()
	for _i in range(120):
		level._physics_process(STEP)
	var snapshot: Dictionary = level.get_snapshot()
	var expected_height: float = level.ice_height
	for _i in range(60):
		level._physics_process(STEP)
	level.restore_snapshot(snapshot)
	assert_float(level.ice_height).is_equal_approx(expected_height, 0.0000001)

func test_frost_contact_uses_band_and_core_multiplier() -> void:
	var level = _make_level(false)
	level.ice_height = 10.0
	level.walkable_surface_depth = 0.45
	level.core_submersion_depth = 1.25
	var body = auto_free(DummyBody.new())
	add_child(body)
	var contacts := []
	level.connect("frost_contact", self, "_collect_contact", [contacts])
	body.translation.y = 9.7
	level._scan_vulnerable_bodies(STEP)
	assert_int(contacts.size()).is_equal(0)
	body.translation.y = 9.4
	level._scan_vulnerable_bodies(STEP)
	assert_int(contacts.size()).is_equal(1)
	assert_bool(contacts[0]["in_core"]).is_false()
	body.translation.y = 8.5
	level._scan_vulnerable_bodies(STEP)
	assert_bool(contacts[1]["in_core"]).is_true()
	assert_float(contacts[1]["dps"]).is_equal_approx(level.damage_per_second * level.core_damage_multiplier, 0.0001)

func test_respawn_safety_keeps_checkpoint_above_frost() -> void:
	var level = _make_level(false)
	level.respawn_safety_margin = 3.0
	level.ice_height = 20.0
	level.ensure_safe_for_respawn(10.0)
	assert_float(level.ice_height).is_equal_approx(7.0, 0.0001)
	assert_float(level.get_frost_ceiling()).is_less_equal(10.0)

# Al reaparecer el mundo está pausado (no corre _physics_process), así que el clamp de
# ensure_safe_for_respawn tiene que dejar el colisionador y el visual al día por sí mismo:
# si no, Elías reaparece sobre un piso de hielo invisible a la altura donde murió.
func test_respawn_safety_syncs_collider_and_asks_for_a_visual_reset() -> void:
	var level = _make_level(false)
	level.respawn_safety_margin = 3.0
	level.ice_height = 20.0
	var resets := [0]
	level.connect("ice_visuals_reset", self, "_count_reset", [resets])
	level.ensure_safe_for_respawn(10.0)
	assert_int(resets[0]).is_equal(1)
	var collider: StaticBody = level.get_node("IceCollider")
	assert_float(collider.global_transform.origin.y).is_equal_approx(level.ice_height - 0.1, 0.0001)

func _count_reset(counter: Array) -> void:
	counter[0] += 1

func test_frost_vignette_becomes_visible_from_bottom_contact() -> void:
	assert_object(get_node_or_null("/root/FrostVignetteManager")).is_not_null()
	var vignette = auto_free(FrostVignetteScene.instance())
	add_child(vignette)
	vignette.set_damage_direction(Vector2(0.0, 1.0), 0.9)
	vignette.set_hazard_active(true)
	vignette._process(0.1)
	var rect: ColorRect = vignette.get_node("Vignette")
	assert_bool(rect.visible).is_true()
	assert_float(vignette._intensity).is_greater(0.1)
	assert_float(vignette._directionality).is_equal_approx(0.9, 0.001)
	var material: ShaderMaterial = rect.material
	if _exposes_shader_param(material, "intensity"):
		assert_float(float(material.get_shader_param("intensity"))).is_greater(0.1)
		assert_float(float(material.get_shader_param("directionality"))).is_equal_approx(0.9, 0.001)
		var frost_color: Color = material.get_shader_param("frost_color")
		assert_float(frost_color.r).is_greater(0.9)
		assert_float(frost_color.g).is_greater(0.95)
		assert_float(frost_color.b).is_equal_approx(1.0, 0.001)

func test_ice_material_freezes_progressively_with_height() -> void:
	var level = auto_free(IceLevelScript.new())
	level.auto_start = false
	level.debug_draw = true
	level.initial_freeze_progress = 0.32
	level.visual_freeze_height = 10.0
	add_child(level)
	var surface: MeshInstance = level.get_node("IceSurface")
	var material: ShaderMaterial = surface.material_override
	level.ice_height = level.start_height
	level._update_debug_visuals()
	assert_float(level.visual_freeze_progress).is_equal_approx(0.32, 0.001)
	level.ice_height = level.start_height + 10.0
	level._update_debug_visuals()
	assert_float(level.visual_freeze_progress).is_equal_approx(1.0, 0.001)
	if _exposes_shader_param(material, "freeze_progress"):
		assert_float(float(material.get_shader_param("freeze_progress"))).is_equal_approx(1.0, 0.001)

func test_object_freezer_does_not_fill_cutout_or_procedural_surfaces() -> void:
	var freezer = auto_free(IceObjectFreezerScript.new())
	var cutout := SpatialMaterial.new()
	cutout.flags_transparent = true
	cutout.params_use_alpha_scissor = true
	var procedural := ShaderMaterial.new()
	procedural.shader = Shader.new()
	procedural.shader.code = "shader_type spatial; void fragment() { discard; }"
	var solid := SpatialMaterial.new()

	assert_bool(freezer._can_wrap_material(cutout)).is_false()
	assert_bool(freezer._can_wrap_material(procedural)).is_false()
	assert_bool(freezer._can_wrap_material(solid)).is_true()

# El binario headless de CI usa el rasterizer dummy: los ShaderMaterial no guardan
# parámetros y get_shader_param() devuelve null (float(null) es error de script). Los
# valores se asertan sobre el estado del nodo; el material se revisa solo donde el
# rasterizer sí los expone (corridas locales con GLES2).
func _exposes_shader_param(material: ShaderMaterial, param: String) -> bool:
	return material != null and material.get_shader_param(param) != null

func _collect_contact(body: Node, dps: float, in_core: bool, contacts: Array) -> void:
	contacts.append({"body": body, "dps": dps, "in_core": in_core})
