extends GdUnitTestSuite

const PilotAnimatorScript = preload("res://core_v2/actors/PilotAnimatorV2.gd")


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
