extends GdUnitTestSuite

# test_room_3d_lab.gd - GdUnit3 tests for Room3DLab environment & airlocks (FD-281).

const Room3DLabScene = preload("res://core_v2/scenes/Room3DLab.tscn")
const STEP := 1.0 / 60.0

func _step_lab(lab: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		if lab.has_method("_physics_process"):
			lab.call("_physics_process", STEP)
		_step_children_recursive(lab, STEP)

func _step_children_recursive(node: Node, dt: float) -> void:
	for child in node.get_children():
		if child.has_method("_physics_process") and not child.is_physics_processing():
			child.call("_physics_process", dt)
		_step_children_recursive(child, dt)

func test_lab_scene_instantiation_and_nodes() -> void:
	var lab: Spatial = auto_free(Room3DLabScene.instance())
	add_child(lab)

	assert_object(lab.control_room).is_not_null()
	assert_object(lab.cryo_room).is_not_null()
	assert_object(lab.plasma_room).is_not_null()

	assert_object(lab.airlock_1).is_not_null()
	assert_object(lab.airlock_2).is_not_null()
	assert_object(lab.airlock_3).is_not_null()

	# Verify initial room states
	assert_float(lab.control_room.temperature).is_equal(20.0)
	assert_float(lab.control_room.pressure).is_equal(1.0)
	assert_float(lab.control_room.contamination).is_equal(0.0)

	assert_float(lab.cryo_room.temperature).is_equal(-150.0)
	assert_float(lab.cryo_room.pressure).is_equal(1.0)

	assert_float(lab.plasma_room.temperature).is_equal(120.0)
	assert_float(lab.plasma_room.pressure).is_equal(2.8)
	assert_bool(lab.plasma_room.is_overpressured()).is_true()

	for airlock in [lab.airlock_1, lab.airlock_2, lab.airlock_3]:
		assert_float(airlock.global_transform.origin.y).is_equal_approx(1.3, 0.001)
	assert_float(lab.airlock_1.transform.basis.z.dot(Vector3(0.5, 0.0, 0.866025))).is_equal_approx(1.0, 0.001)
	assert_float(lab.airlock_2.transform.basis.z.dot(Vector3(-0.5, 0.0, 0.866025))).is_equal_approx(1.0, 0.001)

	for room in [lab.control_room, lab.cryo_room, lab.plasma_room]:
		assert_bool(room is Area).is_true()
		assert_bool(room.debug_render).is_true()
		assert_object(room.get_node("CollisionShape").shape).is_instanceof(BoxShape)
	assert_object(lab.get_node("Rooms/ControlRoom/ObservationDeck")).is_not_null()
	assert_int(lab.get_node("Rooms/ControlRoom/GlassShell").get_child_count()).is_equal(4)
	assert_int(lab.get_node("Rooms/CryoChamber/Walls").get_child_count()).is_equal(6)
	assert_int(lab.get_node("Rooms/PlasmaChamber/Walls").get_child_count()).is_equal(6)
	assert_bool(lab.get_node("HoloTerminals/TerminalTelemetry").is_active).is_true()
	for terminal_name in ["TerminalTelemetry", "TerminalCameras", "TerminalAirlocks"]:
		var terminal: Node = lab.get_node("HoloTerminals/" + terminal_name)
		assert_float(terminal.get_node("ScreenContainer").scale.length()).is_equal_approx(sqrt(3.0), 0.001)
		assert_bool(terminal.get_node("Viewport").get_child_count() > 0).is_true()
	for panel_path in [
		"HoloTerminals/TerminalTelemetry/Viewport/RoomDialsPanel_Control",
		"HoloTerminals/TerminalCameras/Viewport/RoomDialsPanel_Cryo",
		"HoloTerminals/TerminalAirlocks/Viewport/RoomDialsPanel_Plasma",
	]:
		var panel: Node = lab.get_node(panel_path)
		assert_object(panel._room).is_not_null()

func test_overpressure_airlock_locking_and_purge() -> void:
	var lab: Spatial = auto_free(Room3DLabScene.instance())
	add_child(lab)
	_step_lab(lab, 0.1)

	# Airlock 1 (Control <-> Cryo) should NOT be overpressure locked
	assert_bool(lab.airlock_1.is_overpressure_locked()).is_false()

	# Airlock 2 (Control <-> Plasma) and Airlock 3 (Cryo <-> Plasma) SHOULD be overpressure locked
	assert_bool(lab.airlock_2.is_overpressure_locked()).is_true()
	assert_bool(lab.airlock_3.is_overpressure_locked()).is_true()

	# Interaction requests on locked airlocks must fail
	assert_bool(lab.airlock_2.request_door_interaction("outer")).is_false()
	assert_bool(lab.airlock_3.start_cycle()).is_false()

	# Execute purge on plasma chamber
	lab.purge_plasma_chamber()
	_step_lab(lab, 0.1)

	# Plasma room pressure returned to 1.0 (nominal)
	assert_float(lab.plasma_room.pressure).is_equal(1.0)
	assert_bool(lab.plasma_room.is_overpressured()).is_false()

	# Airlocks 2 and 3 must now be unlocked
	assert_bool(lab.airlock_2.is_overpressure_locked()).is_false()
	assert_bool(lab.airlock_3.is_overpressure_locked()).is_false()

func test_environmental_propagation_when_airlock_open() -> void:
	var lab: Spatial = auto_free(Room3DLabScene.instance())
	add_child(lab)

	# Purge plasma room first so airlock 3 can open
	lab.purge_plasma_chamber()
	_step_lab(lab, 0.1)

	var temp_cryo_initial: float = lab.cryo_room.temperature
	var temp_plasma_initial: float = lab.plasma_room.temperature

	# Open exit door of Airlock 3 (Cryo <-> Plasma)
	lab.airlock_3.open_exit_door("inner", true, true)
	assert_str(lab.airlock_3.get_open_exit_door_name()).is_equal("inner")

	# Step time for environmental propagation
	_step_lab(lab, 2.0)

	# Temperature should have propagated (Cryo warmed up, Plasma cooled down)
	assert_bool(lab.cryo_room.temperature > temp_cryo_initial).is_true()
	assert_bool(lab.plasma_room.temperature < temp_plasma_initial).is_true()
