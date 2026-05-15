extends GdUnitTestSuite

const PilotAnimatorScript = preload("res://core_v2/actors/PilotAnimatorV2.gd")
const ControllerStubScript = preload("res://core_v2/tests/PilotAnimatorControllerStub.gd")


func test_set_anim_tree_param_skips_redundant_updates() -> void:
	var animator = PilotAnimatorScript.new()
	var tree := AnimationTree.new()
	animator.add_child(tree)
	animator.animation_tree = tree

	animator._set_anim_tree_param("active", true)
	assert_bool(tree.active).is_true()

	# If the helper writes redundantly, this would flip back to true.
	tree.active = false
	animator._set_anim_tree_param("active", true)
	assert_bool(tree.active).is_false()

	animator._set_anim_tree_param("active", false)
	assert_bool(tree.active).is_false()

	animator.queue_free()

func test_footsteps_do_not_accumulate_without_locomotion_intent() -> void:
	var animator = PilotAnimatorScript.new()
	var controller = ControllerStubScript.new()
	animator.controller = controller

	controller.set_wish_direction(Vector3.ZERO)
	assert_bool(animator._has_locomotion_intent()).is_false()
	assert_bool(animator._should_accumulate_footsteps(true, 0.25, false)).is_false()

	controller.set_wish_direction(Vector3.FORWARD)
	assert_bool(animator._has_locomotion_intent()).is_true()
	assert_bool(animator._should_accumulate_footsteps(true, 0.25, true)).is_true()

	controller.is_pushing = true
	assert_bool(animator._should_accumulate_footsteps(true, 0.25, true)).is_false()

	animator.queue_free()
	controller.queue_free()
