
extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"
var ReplayRecorder



# Setup method to initialize the test environment
func before_each():
	ReplayRecorder = preload("res://scripts/replay/ReplayRecorder.gd").new()
	assert_that(ReplayRecorder).is_not_null()
	add_child(ReplayRecorder)

func test_initialization():
	assert_that(ReplayRecorder).is_not_null()
	assert_that(ReplayRecorder.is_inside_tree()).is_true()

func test_start_recording():
	ReplayRecorder.start_recording()
	assert_that(ReplayRecorder.is_recording()).is_true()

func test_stop_recording():
	ReplayRecorder.start_recording()
	ReplayRecorder.stop_recording()
	assert_that(ReplayRecorder.is_recording()).is_false()

func test_input_event():
	var event = InputEventMouseMotion.new()
	event.relative = Vector2(10, 5)
	ReplayRecorder._input(event)
	assert_that(ReplayRecorder.mouse_motion_accumulated).is_equal(Vector2(10, 5))
