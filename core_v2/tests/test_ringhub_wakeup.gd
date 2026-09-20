extends GdUnitTestSuite

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")


func test_opening_cryo_pod_does_not_move_pilot() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var pilot: Spatial = level.get_node("Pilot")
	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	for _i in range(210):
		yield(get_tree(), "physics_frame")
	var before: Transform = pilot.global_transform
	for _i in range(210):
		yield(get_tree(), "physics_frame")
	before = pilot.global_transform

	hatch.set_active(true)
	for _i in range(210):
		yield(get_tree(), "physics_frame")

	assert_bool(bool(hatch.is_active)).is_true()
	assert_bool(pilot.global_transform.is_equal_approx(before)).is_true()
