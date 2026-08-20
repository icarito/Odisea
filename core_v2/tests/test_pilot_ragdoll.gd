extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const PilotScene = preload("res://core_v2/actors/Pilot_v2.tscn")

func before() -> void:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna and anna.has_method("set_replay_mode"):
		anna.set_replay_mode(true)

func test_begin_ragdoll_activates_simulation_and_disables_collision() -> void:
	var pilot = PilotScene.instance()
	add_child(pilot)

	assert_bool(pilot.is_ragdoll).is_false()
	var cs = pilot.get_node_or_null("CollisionShape") as CollisionShape
	assert_object(cs).is_not_null()
	assert_bool(cs.disabled).is_false()

	pilot.begin_ragdoll()

	assert_bool(pilot.is_ragdoll).is_true()
	assert_bool(cs.disabled).is_true()

	var animator = pilot.get_node_or_null("Visual/Pivot")
	assert_object(animator).is_not_null()
	assert_bool(animator.is_ragdoll).is_true()

	var skel = pilot.get_node_or_null("Visual/Pivot/Skeleton/Skinned_Mesh_0/Skeleton") as Skeleton
	assert_object(skel).is_not_null()
	var pb_count = 0
	for child in skel.get_children():
		if child is PhysicalBone:
			pb_count += 1
	assert_int(pb_count).is_greater(0)

	pilot.free()

func test_end_ragdoll_restores_state() -> void:
	var pilot = PilotScene.instance()
	add_child(pilot)

	pilot.begin_ragdoll()
	assert_bool(pilot.is_ragdoll).is_true()

	pilot.end_ragdoll()

	assert_bool(pilot.is_ragdoll).is_false()
	var cs = pilot.get_node_or_null("CollisionShape") as CollisionShape
	assert_bool(cs.disabled).is_false()

	var animator = pilot.get_node_or_null("Visual/Pivot")
	assert_bool(animator.is_ragdoll).is_false()

	pilot.free()

func test_suit_breached_triggers_ragdoll() -> void:
	var pilot = PilotScene.instance()
	add_child(pilot)

	assert_bool(pilot.is_ragdoll).is_false()
	pilot._on_suit_breached()
	assert_bool(pilot.is_ragdoll).is_true()

	pilot.free()

func test_full_reset_clears_ragdoll() -> void:
	var pilot = PilotScene.instance()
	add_child(pilot)

	pilot.begin_ragdoll()
	assert_bool(pilot.is_ragdoll).is_true()

	pilot.full_reset()
	assert_bool(pilot.is_ragdoll).is_false()

	pilot.free()
