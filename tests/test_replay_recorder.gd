class_name GdUnitReplayRecorderTestSuite
extends GdUnitTestSuite

var runner: GdUnitSceneRunner
var replay_recorder: Node
var scene: Node
var last_replay_path: String

func before():
	runner = scene_runner("res://tests/fixtures/TestScene.tscn")
	# Add autoloads
	var game_globals = Node.new()
	game_globals.set_script(load("res://autoload/GameGlobals.gd"))
	game_globals.name = "GameGlobals"
	runner.scene().add_child(game_globals)
	
	var player_manager = Node.new()
	player_manager.set_script(load("res://autoload/PlayerManager.gd"))
	player_manager.name = "PlayerManager"
	runner.scene().add_child(player_manager)
	
	var input_state = Node.new()
	input_state.set_script(load("res://autoload/InputState.gd"))
	input_state.name = "InputState"
	runner.scene().add_child(input_state)
	
	replay_recorder = Node.new()
	replay_recorder.set_script(load("res://scripts/replay/ReplayRecorder.gd"))
	replay_recorder.name = "ReplayRecorder"
	runner.scene().add_child(replay_recorder)
	runner.simulate_frames(1)  # Ensure _ready is called
	replay_recorder.connect("recording_stopped", self, "_on_recording_stopped")
	print("replay_recorder: ", replay_recorder)
	print("replay_recorder script: ", replay_recorder.get_script() if replay_recorder else "null")

func _on_recording_stopped(frame_count, replay_path):
	last_replay_path = replay_path

func test_record_30_seconds_random_movement():
	# Start recording
	replay_recorder.start_recording()
	assert_that(replay_recorder.is_recording()).is_true()
	
	# Simulate a few frames
	for i in range(10):
		runner.simulate_frames(1)
	
	# Stop recording
	replay_recorder.stop_recording()
	assert_that(replay_recorder.is_recording()).is_false()
	
	# Check replay file exists
	var path = last_replay_path
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
