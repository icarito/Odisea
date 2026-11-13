extends GdUnitTestSuite

# Feedback diegético de controles (LeverV2 / PedestalButton): el pulso de emisión
# debe ser determinista (contado en ticks de física, sin Tween/randf), restaurarse por
# snapshot y no alterar las señales/APIs existentes.

const LeverScene := preload("res://core_v2/props/controls/LeverV2.tscn")
const ButtonScene := preload("res://core_v2/props/controls/PedestalButton.tscn")

func _host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self

func test_lever_pulse_ticks_are_deterministic_and_end() -> void:
	var lever = auto_free(LeverScene.instance())
	_host().add_child(lever)
	yield(get_tree(), "idle_frame")

	var toggled := [false]
	lever.connect("lever_toggled", self, "_on_toggled", [toggled])

	var initial_pulse: int = lever._pulse_ticks
	assert_int(initial_pulse).is_equal(0)

	lever.interact()
	lever.step(10.0) # animación completada -> pulso arranca
	assert_bool(lever.is_active).is_true()
	assert_bool(toggled[0]).is_true()
	assert_int(lever._pulse_ticks).is_greater(0)

	var ticks_before: int = lever._pulse_ticks
	lever.step(1.0 / 60.0)
	assert_int(lever._pulse_ticks).is_equal(ticks_before - 1)

	for _i in range(ticks_before + 2):
		lever.step(1.0 / 60.0)
	assert_int(lever._pulse_ticks).is_equal(0)

func test_lever_snapshot_restores_pulse_and_state() -> void:
	var lever = auto_free(LeverScene.instance())
	_host().add_child(lever)
	yield(get_tree(), "idle_frame")

	lever.interact()
	lever.step(10.0)
	var snap: Dictionary = lever.get_snapshot()
	assert_int(snap.get("pulse_ticks", 0)).is_greater(0)
	assert_bool(snap.get("active", false)).is_true()

	lever._pulse_ticks = 0
	lever.is_active = false
	lever.restore_snapshot(snap)
	assert_bool(lever.is_active).is_true()
	assert_int(lever._pulse_ticks).is_greater(0)

func test_pedestal_button_pulse_on_rising_edge_and_bezel_emissive() -> void:
	var button = auto_free(ButtonScene.instance())
	_host().add_child(button)
	yield(get_tree(), "idle_frame")
	assert_int(button._pulse_ticks).is_equal(0)

	button.interact() # toggle off -> on
	assert_bool(button.is_active).is_true()
	assert_int(button._pulse_ticks).is_equal(button.PULSE_TICKS)

	var mesh: MeshInstance = button.get_node("ButtonMesh")
	var mat = mesh.material_override
	assert_bool(mat is SpatialMaterial).is_true()
	assert_bool(mat.emission_enabled).is_true()
	assert_float(mat.emission_energy).is_greater(1.0) # boost de pulso sobre el actuador

	var ticks_before: int = button._pulse_ticks
	button.step(1.0 / 60.0)
	assert_int(button._pulse_ticks).is_equal(ticks_before - 1)

	for _i in range(ticks_before + 2):
		button.step(1.0 / 60.0)
	assert_int(button._pulse_ticks).is_equal(0)
	assert_bool(button.is_active).is_true() # estado lógico no se pierde al terminar el pulso

func _on_toggled(_is_on: bool, flag: Array) -> void:
	flag[0] = true
