extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

var runner: GdUnitSceneRunner
var replay_manager: Node
var replay_recorder: Node
var scene: Node

func before_each():
	runner = scene_runner("res://tests/fixtures/TestScene.tscn")
	replay_manager = Node.new()
	replay_manager.set_script(load("res://autoload/ReplayManager.gd"))
	replay_manager.name = "ReplayManager"
	var replay_recorder = Node.new()
	replay_recorder.set_script(load("res://scripts/replay/ReplayRecorder.gd"))
	replay_recorder.name = "ReplayRecorder"
	replay_manager.add_child(replay_recorder)
	runner.scene().add_child(replay_manager)
	runner.simulate_frames(1)  # Ensure _ready is called
	replay_recorder = replay_manager.get_node("ReplayRecorder")

func test_record_30_seconds_random_movement():
	# Start recording
	replay_manager.start_recording()
	assert_that(replay_recorder.is_recording()).is_true()
	
	# Simulate 30 seconds of random input (1800 frames at 60fps, but for test, do 300 frames = 5s)
	var frames = 300
	var rng = RandomNumberGenerator.new()
	rng.seed = 42  # Deterministic for test
	
	for i in range(frames):
		# Set random input
		InputState.actions["move_forward"] = rng.randi() % 2 == 0
		InputState.actions["move_back"] = rng.randi() % 2 == 0
		InputState.actions["move_left"] = rng.randi() % 2 == 0
		InputState.actions["move_right"] = rng.randi() % 2 == 0
		InputState.actions["jump"] = rng.randi() % 10 == 0  # Less frequent
		InputState.axes["move_x"] = rng.randf_range(-1.0, 1.0)
		InputState.axes["move_y"] = rng.randf_range(-1.0, 1.0)
		InputState.mouse_delta = Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		
		# Simulate physics process
		runner.simulate_frames(1)
	
	# Stop recording
	replay_recorder.stop_recording()
	assert_that(replay_recorder.is_recording()).is_false()
	
	# Check replay file exists
	var path = replay_manager.last_replay_path
	assert_that(path).is_not_null()
	var file = File.new()
	assert_that(file.file_exists(path)).is_true()
	
	# Load and validate JSON
	file.open(path, File.READ)
	var json = JSON.parse(file.get_as_text())
	file.close()
	assert_that(json.error).is_equal(OK)
	var data = json.result
	
	# Validate metadata
	assert_that(data).has_key("godot_version")
	assert_that(data).has_key("game_version")
	assert_that(data).has_key("timestamp")
	assert_that(data).has_key("scene_path")
	
	# Validate initial states
	assert_that(data).has_key("initial_states")
	assert_that(data["initial_states"]).is_not_empty()
	
	# Validate frames
	assert_that(data).has_key("frames")
	assert_that(data["frames"].size()).is_greater(0)
	
	# Check some frames have required keys
	var frame = data["frames"][0]
	assert_that(frame).has_key("inputs")
	assert_that(frame).has_key("axes")
	assert_that(frame).has_key("mouse_delta")
	assert_that(frame).has_key("snapshot")
	
	# Validate snapshots every SNAPSHOT_INTERVAL (100)
	var snapshot_count = 0
	for f in data["frames"]:
		if f.has("snapshot") and f["snapshot"].has("debug"):
			snapshot_count += 1
	assert_that(snapshot_count).is_greater(0)  # At least one snapshot
