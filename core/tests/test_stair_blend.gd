extends GdUnitTestSuite

const SCENE_PATH := "res://core/tests/TestStairBlend.tscn"
const InputData = preload("res://core/input/InputData.gd")

func test_stair_climb_does_not_trigger_jump_fall_blend() -> void:
	var runner := scene_runner(SCENE_PATH)
	runner.maximize_view()

	var scene := runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_that(pilot).is_not_null()

	var animator = pilot.get_node_or_null("Visual/Pivot")
	assert_that(animator).is_not_null()
	var tree: AnimationTree = animator.get_node_or_null("AnimationTree")
	assert_that(tree).is_not_null()

	# Force deterministic stepping through external input path.
	pilot.is_replay_mode = true

	var jump_frames := 0
	var fall_frames := 0
	var float_frames := 0

	for _i in range(120):
		var input := InputData.new()
		input.move_vec = Vector2(0, -1) # forward
		input.sprint = false
		input.jump = false
		input.crouch = false
		pilot.external_input = input
		pilot.external_input_provided = true
		yield(runner.simulate_frames(1), "completed")

		if tree.get("parameters/conditions/is_jumping"):
			jump_frames += 1
		if tree.get("parameters/conditions/is_falling"):
			fall_frames += 1
		if tree.get("parameters/conditions/is_floating"):
			float_frames += 1

	var final_pos: Vector3 = pilot.global_transform.origin
	assert_that(final_pos.y).is_greater(0.9)

	# We allow a tiny tolerance for transition settle, but this should remain near zero on stairs.
	assert_that(jump_frames).is_less_equal(2)
	assert_that(fall_frames).is_less_equal(2)
	assert_that(float_frames).is_less_equal(2)
