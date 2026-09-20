extends GdUnitTestSuite

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")


func test_opening_cryo_pod_does_not_move_pilot() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var pilot: Spatial = level.get_node("Pilot")
	var pod: Spatial = level.get_node("Criopod_Vert")
	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	for _i in range(210):
		yield(get_tree(), "physics_frame")
	var before: Transform = pilot.global_transform
	var before_pod: Transform = pod.global_transform
	for _i in range(210):
		yield(get_tree(), "physics_frame")
	before = pilot.global_transform
	before_pod = pod.global_transform
	var wakeup_floor = level.get_node("Criopod_Vert/WakeupFloor/CollisionShape")
	var static_floor = level.get_node("Criopod_Vert/StaticBody/CollisionShape")
	print("RINGHUB setup pilot=", pilot.global_transform.origin, " floor_disabled=", wakeup_floor.disabled, " static_disabled=", static_floor.disabled, " on_floor=", pilot.is_on_floor())

	hatch.set_active(true)
	for _i in range(210):
		yield(get_tree(), "physics_frame")

	print("RINGHUB pilot before=", before.origin, " after=", pilot.global_transform.origin, " delta=", pilot.global_transform.origin - before.origin, " pod_delta=", pod.global_transform.origin - before_pod.origin, " local_before=", before_pod.affine_inverse().xform(before.origin), " local_after=", pod.global_transform.affine_inverse().xform(pilot.global_transform.origin), " floor_disabled=", wakeup_floor.disabled, " static_disabled=", static_floor.disabled, " on_floor=", pilot.is_on_floor(), " velocity=", pilot.velocity)
	assert_bool(bool(hatch.is_active)).is_true()
	assert_bool(pilot.global_transform.origin.distance_to(before.origin) < 0.01).is_true()
