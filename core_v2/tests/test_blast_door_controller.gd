extends GdUnitTestSuite

# Test focalizado de BlastDoorController (FD-289 T3, tracker #319).
# Cubre: contrato (grupo replay_sync + API), apertura horizontal por progreso,
# determinismo del progreso, snapshot roundtrip y semaforo de borde (§6.2).

const BlastDoorScene = preload("res://core_v2/props/doors/BlastDoorController.tscn")

var _opened_calls := 0
var _closed_calls := 0

func _on_opened() -> void:
	_opened_calls += 1

func _on_closed() -> void:
	_closed_calls += 1

func _spawn_door() -> Node:
	var host: Spatial = auto_free(Spatial.new())
	host.name = "BlastDoorTestHost"
	add_child(host)
	var door: Node = BlastDoorScene.instance()
	host.add_child(door)
	return door

func test_contract_and_groups() -> void:
	var door = _spawn_door()
	yield(get_tree(), "idle_frame")

	assert_bool(door.is_in_group("replay_sync")).is_true()
	assert_bool(door.has_method("open")).is_true()
	assert_bool(door.has_method("close")).is_true()
	assert_bool(door.has_method("on_blast_door_open")).is_true()
	assert_bool(door.has_method("set_network_healthy_count")).is_true()
	assert_bool(door.has_method("get_snapshot")).is_true()
	assert_bool(door.has_method("restore_snapshot")).is_true()
	assert_bool(door.is_open()).is_false()

func test_horizontal_open_retracts_both_panels_opposite_ways() -> void:
	var door = _spawn_door()
	yield(get_tree(), "idle_frame")

	var panel_a = door.get_node("PanelA")
	var panel_b = door.get_node("PanelB")
	var a_closed: float = panel_a.translation.x
	var b_closed: float = panel_b.translation.x

	door.open(true)
	yield(get_tree(), "idle_frame")

	assert_bool(door.is_open()).is_true()
	assert_float(panel_a.translation.x).is_equal_approx(a_closed - door.panel_slide, 0.001)
	assert_float(panel_b.translation.x).is_equal_approx(b_closed + door.panel_slide, 0.001)

func test_animated_open_advances_progress_and_emits_opened() -> void:
	var door = _spawn_door()
	yield(get_tree(), "idle_frame")

	door.connect("opened", self, "_on_opened")
	_opened_calls = 0

	door.open(false)
	for _i in range(10):
		door.step(0.1)
	# anim_duration = 3.0 -> 1.0s transcurrido = ~0.33 de progreso.
	assert_bool(door.anim_progress > 0.0 and door.anim_progress < 1.0).is_true()
	assert_int(_opened_calls).is_equal(0)

	for _i in range(60):
		door.step(0.1)
	assert_float(door.anim_progress).is_equal(1.0)
	assert_int(_opened_calls).is_equal(1)
	door.disconnect("opened", self, "_on_opened")

func test_progress_and_pose_are_deterministic() -> void:
	var a = _spawn_door()
	var b = _spawn_door()
	yield(get_tree(), "idle_frame")

	a.open(false)
	b.open(false)
	a.set_physics_process(false)
	b.set_physics_process(false)
	for _i in range(7):
		a.step(0.1)
		b.step(0.1)

	assert_float(a.anim_progress).is_equal_approx(b.anim_progress, 0.0001)
	assert_float(a.get_node("PanelA").translation.x).is_equal_approx(b.get_node("PanelA").translation.x, 0.0001)
	assert_float(a.get_node("PanelB").translation.x).is_equal_approx(b.get_node("PanelB").translation.x, 0.0001)

func test_snapshot_roundtrip_restores_state_and_progress() -> void:
	var a = _spawn_door()
	yield(get_tree(), "idle_frame")

	a.open(false)
	for _i in range(7):
		a.step(0.1)
	# Congelar a antes de crear c: si no, un tick de fisica del motor mientras
	# esperamos el idle_frame avanza a y descuadra el snapshot.
	a.set_physics_process(false)
	a.set_network_healthy_count(3)
	var a_progress: float = a.anim_progress
	var a_panel_x: float = a.get_node("PanelA").translation.x
	var snapshot = a.get_snapshot()

	var c = _spawn_door()
	yield(get_tree(), "idle_frame")
	c.restore_snapshot(snapshot)
	c.set_physics_process(false)

	assert_bool(c.is_open()).is_true()
	assert_float(c.anim_progress).is_equal_approx(a_progress, 0.001)
	assert_float(c.target_progress).is_equal_approx(a.target_progress, 0.001)
	assert_int(c.get_network_healthy_count()).is_equal(3)
	assert_float(c.get_node("PanelA").translation.x).is_equal_approx(a_panel_x, 0.001)

func test_semaphore_pulses_when_restoring() -> void:
	var door = _spawn_door()
	yield(get_tree(), "idle_frame")

	door.set_network_healthy_count(0)
	var phase_off = door._pulse_phase
	door.step(0.1)
	assert_float(door._pulse_phase).is_equal(phase_off)

	# 1-2 redes HEALTHY -> ambar pulsante: el phase avanza con step.
	door.set_network_healthy_count(2)
	var phase_before = door._pulse_phase
	door.step(0.1)
	assert_bool(abs(door._pulse_phase - phase_before) > 0.0001).is_true()

	# 4 redes -> listo, sin pulso.
	door.set_network_healthy_count(4)
	assert_int(door.get_network_healthy_count()).is_equal(4)

func test_restore_before_ready_is_deferred() -> void:
	var door: Node = BlastDoorScene.instance()
	var snapshot := {
		"active": true,
		"progress": 1.0,
		"target": 1.0,
		"healthy_count": 4,
		"pulse_phase": 0.0,
		"panel_slide": 5.7
	}
	door.restore_snapshot(snapshot)
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	host.add_child(door)
	yield(get_tree(), "idle_frame")

	assert_bool(door.is_open()).is_true()
	assert_int(door.get_network_healthy_count()).is_equal(4)
