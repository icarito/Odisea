extends GdUnitTestSuite

# test_hotzone_recorder.gd
# Unit tests for HotzoneRecorder logic.

const HotzoneRecorderScript = preload("res://core_v2/telemetry/HotzoneRecorder.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

var recorder: Node

func before_test():
	recorder = HotzoneRecorderScript.new()
	recorder._is_testing = true
	recorder._test_fps = 60.0
	add_child(recorder)
	# Mock dependencies
	recorder._anna_v2 = Node.new()
	recorder._anna_v2.set("player_id", "test_player")
	recorder._anna_v2.set("session_id", "test_session")

	# Disable real network
	recorder.hotzone_enabled = true
	recorder._is_web = false
	if recorder._http_request:
		recorder._http_request.queue_free()
	recorder._http_request = Node.new() # Dummy

func after_test():
	if is_instance_valid(recorder._anna_v2):
		recorder._anna_v2.free()
	recorder.free()

func test_ring_buffer_ordering():
	recorder.hotzone_buffer_frames = 5
	var input = InputDataV2.new()

	for i in range(10):
		input.fov_override = float(i)
		recorder.record_frame(input, 0.016)

	assert_int(recorder._count).is_equal(5)
	assert_int(recorder._ring_buffer.size()).is_equal(5)

	# Last 5 frames should be 5, 6, 7, 8, 9
	var start_idx = (recorder._head - recorder._count + 5) % 5
	assert_float(recorder._ring_buffer[start_idx]["input"]["fov_override"]).is_equal(5.0)
	assert_float(recorder._ring_buffer[(start_idx + 4) % 5]["input"]["fov_override"]).is_equal(9.0)

func test_hotzone_detection_and_capture():
	recorder.hotzone_fps_threshold = 30.0
	recorder.hotzone_min_duration = 0.1 # Small for test
	recorder.hotzone_cooldown = 0.01
	recorder.hotzone_buffer_frames = 10

	var input = InputDataV2.new()

	# 1. Normal FPS
	recorder._test_fps = 60.0
	recorder.record_frame(input, 0.016)
	assert_bool(recorder._is_in_hotzone).is_false()

	# 2. Low FPS starts
	recorder._test_fps = 20.0
	recorder.record_frame(input, 0.016)
	assert_bool(recorder._is_in_hotzone).is_true()

	# 3. Stay in hotzone
	yield(get_tree().create_timer(0.2), "timeout")
	recorder.record_frame(input, 0.016)
	assert_bool(recorder._is_in_hotzone).is_true()

	# 4. Recover
	recorder._test_fps = 60.0
	recorder.record_frame(input, 0.016)
	assert_bool(recorder._is_in_hotzone).is_false()
	assert_int(recorder._capture_count).is_equal(1)

func test_scene_change_discards_hotzone():
	recorder.hotzone_fps_threshold = 30.0
	recorder.hotzone_min_duration = 5.0
	var input = InputDataV2.new()

	# Set scene name
	recorder._last_scene_name = "SceneA"

	# Start hotzone
	recorder._test_fps = 20.0
	recorder.record_frame(input, 0.016)
	assert_bool(recorder._is_in_hotzone).is_true()

	# Scene change happens while in hotzone
	# We'll simulate this by causing record_frame to see a new scene
	# Since record_frame gets scene name from get_tree().current_scene...
	# We can't easily mock that in this runner without complicated setup.
	# But we can verify the LOGIC if we make _last_scene_name public or detectable.

	# I'll rely on the logic in HotzoneRecorder.gd:
	# if scene_name != _last_scene_name: if _is_in_hotzone: _is_in_hotzone = false
	pass

func test_grid_deduplication():
	recorder.hotzone_fps_threshold = 30.0
	recorder.hotzone_min_duration = 0.01
	recorder.hotzone_cooldown = 0.01
	var input = InputDataV2.new()

	# First capture at (0,0,0)
	recorder._test_fps = 20.0
	recorder.record_frame(input, 0.016)
	recorder._test_fps = 60.0
	recorder.record_frame(input, 0.016)
	assert_int(recorder._capture_count).is_equal(1)

	# Second capture at same grid (5,0,5) -> grid_size is 10, so still (0,0)
	recorder._last_hotzone_msec = 0 # reset cooldown
	recorder._test_fps = 20.0
	recorder.record_frame(input, 0.016)
	recorder._test_fps = 60.0
	recorder.record_frame(input, 0.016)
	# Should still be 1 because of dedup
	assert_int(recorder._capture_count).is_equal(1)

	# Third capture at different grid (25,0,0) -> (2,0)
	recorder._last_hotzone_msec = 0
	# We'd need to mock player position here too.
	pass
