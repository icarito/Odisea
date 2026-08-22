extends GdUnitTestSuite

const IceLevelScript = preload("res://core_v2/systems/ice/IceLevel.gd")
const IceObjectFreezerScript = preload("res://core_v2/systems/ice/IceObjectFreezer.gd")
const FrostVignetteScene = preload("res://core_v2/ui/overlay/FrostVignette.tscn")
const Room3DScript = preload("res://core_v2/systems/room/Room3D.gd")
const STEP := 1.0 / 60.0

class DummyBody extends Spatial:
	func _init() -> void:
		add_to_group("ice_vulnerable")

class DummyPlayer extends KinematicBody:
	func _init() -> void:
		add_to_group("ice_vulnerable")
	func set_ice_submersion(_depth: float) -> void:
		pass

class DummyTank extends Node:
	var tank_level: float = 1.0
	var coolant_capacity: float = 1.0

	func _init(level: float) -> void:
		tank_level = level
		add_to_group("coolant_source")

class DummyLeak extends Node:
	var intensity: float = 0.0

	func _init(value: float) -> void:
		intensity = value
		add_to_group("coolant_leak")

	func get_leak_intensity() -> float:
		return intensity

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


func test_snapshot_restore_repositions_the_ice_collider() -> void:
	var level = _make_level(false)
	level.ice_height = 0.0
	var snapshot: Dictionary = level.get_snapshot()
	level.ice_height = 12.0
	level._update_ice_collider()
	var resets := [0]
	level.connect("ice_visuals_reset", self, "_count_reset", [resets])
	level.restore_snapshot(snapshot)
	var collider: StaticBody = level.get_node("IceCollider")
	assert_float(collider.global_transform.origin.y).is_equal_approx(-0.1, 0.001)
	assert_int(resets[0]).is_equal(1)

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


func test_respawn_safety_never_hides_ice_below_its_start_height() -> void:
	var level = _make_level(false)
	level.start_height = 0.0
	level.respawn_safety_margin = 3.0
	level.ice_height = 2.0

	level.ensure_safe_for_respawn(1.0)

	assert_float(level.ice_height).is_equal_approx(level.start_height, 0.0001)

func test_rising_ice_remains_a_walkable_platform() -> void:
	var level = _make_level(false)
	var collider: StaticBody = level.get_node("IceCollider")
	assert_int(collider.collision_layer).is_equal(1)
	var player = auto_free(DummyPlayer.new())
	add_child(player)
	player.translation.y = 1.01
	level.ice_height = 0.02
	level._update_ice_collider()
	assert_float(collider.global_transform.origin.y).is_equal_approx(-0.1, 0.001)
	assert_int(collider.collision_layer).is_equal(1)


func test_coolant_volume_caps_the_ice_and_leaves_the_last_floor() -> void:
	var west: DummyTank = auto_free(DummyTank.new(0.0))
	var east: DummyTank = auto_free(DummyTank.new(1.0))
	add_child(west)
	add_child(east)
	var level = _make_level(false)
	level.base_speed = 20.0
	level.max_coolant_height = 18.0
	level.start()

	# Un tanque agotado aporta exactamente media columna: sin fuga en el otro,
	# la superficie no puede seguir subiendo.
	level.step(1.0)
	assert_float(level.ice_height).is_equal_approx(9.0, 0.001)
	assert_bool(level.is_running).is_false()

	# Si ambos se vacían ya no hay caudal: conserva la altura alcanzada, no persigue
	# el volumen pendiente ni se derrite.
	east.tank_level = 0.0
	level.start()
	level.step(1.0)
	assert_float(level.ice_height).is_equal_approx(9.0, 0.001)
	assert_bool(level.is_running).is_false()


func test_coolant_volume_rises_visibly_instead_of_jumping_to_drained_height() -> void:
	var west: DummyTank = auto_free(DummyTank.new(0.0))
	var east: DummyTank = auto_free(DummyTank.new(1.0))
	add_child(west)
	add_child(east)
	var level = _make_level(false)
	level.base_speed = 0.15
	level.max_coolant_height = 18.0
	level.start()

	level.step(1.0)

	assert_float(level.ice_height).is_greater(0.0)
	assert_float(level.ice_height).is_less(9.05)
	assert_bool(level.is_running).is_true()


func test_coolant_capacity_calculates_the_maximum_ice_height() -> void:
	var small: DummyTank = auto_free(DummyTank.new(0.0))
	small.coolant_capacity = 1.0
	var large: DummyTank = auto_free(DummyTank.new(0.0))
	large.coolant_capacity = 3.0
	add_child(small)
	add_child(large)
	var level = _make_level(false)
	level.max_coolant_height = 8.0

	assert_float(level._get_coolant_height_cap()).is_equal_approx(8.0, 0.0001)


func test_closed_or_empty_coolant_flow_stops_ice_without_lowering_it() -> void:
	var tank: DummyTank = auto_free(DummyTank.new(1.0))
	add_child(tank)
	var leak: DummyLeak = auto_free(DummyLeak.new(0.0))
	add_child(leak)
	var level = _make_level(false)
	level.ice_height = 4.0
	level.start()

	level.step(1.0)

	assert_float(level.ice_height).is_equal_approx(4.0, 0.0001)
	assert_bool(level.is_running).is_false()

	tank.tank_level = 0.0
	leak.intensity = 1.0
	level.start()
	level.step(1.0)
	assert_float(level.ice_height).is_equal_approx(4.0, 0.0001)
	assert_bool(level.is_running).is_false()


func test_static_ice_keeps_damaging_while_room_is_freezing() -> void:
	var room = auto_free(Room3DScript.new())
	room.name = "ColdRoom"
	room.temperature = -1.0
	add_child(room)
	var tank: DummyTank = auto_free(DummyTank.new(0.0))
	add_child(tank)
	var level = _make_level(false)
	level.room_path = NodePath("../ColdRoom")
	level.ice_height = 4.0
	var body: DummyBody = auto_free(DummyBody.new())
	body.translation.y = 3.0
	add_child(body)
	var contacts := []
	level.connect("frost_contact", self, "_collect_contact", [contacts])

	level.step(STEP)

	assert_bool(level.is_running).is_false()
	assert_int(contacts.size()).is_equal(1)


func test_ice_rise_speed_scales_with_active_leak_count() -> void:
	var tank: DummyTank = auto_free(DummyTank.new(0.5))
	add_child(tank)
	var first_leak: DummyLeak = auto_free(DummyLeak.new(1.0))
	var second_leak: DummyLeak = auto_free(DummyLeak.new(1.0))
	add_child(first_leak)
	add_child(second_leak)
	var level = _make_level(false)
	level.base_speed = 0.2
	level.rise_twitch_amount = 0.0
	level.max_coolant_height = 18.0
	level.start()

	level.step(1.0)

	assert_float(level.ice_speed).is_equal_approx(0.4, 0.0001)
	assert_float(level.ice_height).is_equal_approx(0.4, 0.0001)

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

# El disco de hielo tiene que morir contra la pared del domo a cualquier altura: con un
# radio fijo quedaba un anillo de piso descubierto abajo, y al cerrarse la bóveda el mismo
# disco habría asomado por fuera.
func test_ice_disc_follows_the_dome_wall_at_every_height() -> void:
	var level = auto_free(IceLevelScript.new())
	level.auto_start = false
	level.debug_draw = true
	add_child(level)

	# Radios de la pared medidos sobre DomeTerrace_baked.mesh (ver tools/measure_dome_profile.gd).
	for probe in [[0.5, 31.33], [8.0, 30.98], [14.0, 29.18], [22.0, 23.62], [30.0, 10.91]]:
		var radius: float = level.get_surface_radius_at(probe[0])
		assert_float(radius).is_greater(probe[1])
		# Y enterrado en el espesor de la pared (~0.7 m), no metros más allá.
		assert_float(radius).is_less(probe[1] + 0.7)

	# La malla y la placa que se pisa tienen que cubrir el punto más ancho del perfil.
	var surface: MeshInstance = level.get_node("IceSurface")
	assert_float(surface.mesh.size.x).is_greater_equal(level.get_surface_radius_at(0.0) * 2.0)
	var box: BoxShape = level.get_node("IceCollider").get_child(0).shape
	assert_float(box.extents.x).is_greater_equal(level.get_surface_radius_at(0.0))

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


func test_ice_visuals_stay_off_until_ice_rises() -> void:
	var IceVisualBandScript = preload("res://core_v2/systems/ice/IceVisualBand.gd")
	var level = _make_level(false)
	var band = auto_free(IceVisualBandScript.new())
	add_child(band)
	band._connect_ice_level()
	assert_bool(band.is_visual_active()).is_false()
	assert_bool(band.is_using_cpu_particles()).is_true()
	var cpu: CPUParticles = band.get_node_or_null("CPUParticles")
	assert_object(cpu).is_not_null()
	band._on_ice_height_changed(level.start_height)
	assert_bool(band.is_visual_active()).is_false()
	band._on_ice_height_changed(level.start_height + 1.0)
	assert_bool(band.is_visual_active()).is_true()
	band.reset_visuals()
	assert_bool(band.is_visual_active()).is_false()


func test_object_freezer_waits_for_ice_rise() -> void:
	var freezer = auto_free(IceObjectFreezerScript.new())
	var level = _make_level(false)
	add_child(freezer)
	freezer._connect_ice_level()
	assert_bool(freezer.has_started_wrapping()).is_false()
	assert_int(freezer._scans_done).is_equal(0)
	freezer._on_ice_height_changed(level.start_height)
	assert_bool(freezer.has_started_wrapping()).is_false()
	assert_int(freezer._scans_done).is_equal(0)
	freezer._on_ice_height_changed(level.start_height + 1.0)
	assert_bool(freezer.has_started_wrapping()).is_true()
	assert_int(freezer._scans_done).is_equal(1)

# El binario headless de CI usa el rasterizer dummy: los ShaderMaterial no guardan
# parámetros y get_shader_param() devuelve null (float(null) es error de script). Los
# valores se asertan sobre el estado del nodo; el material se revisa solo donde el
# rasterizer sí los expone (corridas locales con GLES2).
func _exposes_shader_param(material: ShaderMaterial, param: String) -> bool:
	return material != null and material.get_shader_param(param) != null

func _collect_contact(body: Node, dps: float, in_core: bool, contacts: Array) -> void:
	contacts.append({"body": body, "dps": dps, "in_core": in_core})
