#class_name GdUnitReplayRecorderTestSuite
extends GdUnitTestSuite

var runner: GdUnitSceneRunner
var replay_recorder: Node
var scene: Node
var last_replay_path: String

func before():
	runner = scene_runner("res://tests/fixtures/TestScene.tscn")
	get_tree().current_scene = runner.scene()
	# Remove existing ReplayRecorder from ReplayManager
	var replay_manager = get_node("/root/ReplayManager")
	if replay_manager and replay_manager.has_node("ReplayRecorder"):
		replay_manager.get_node("ReplayRecorder").queue_free()
	# Add autoloads
	var game_globals = Node.new()
	game_globals.set_script(load("res://autoload/GameGlobals.gd"))
	game_globals.name = "GameGlobals"
	runner.scene().add_child(game_globals)
	
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

	# Spawn player
	var spawn_point = runner.scene().find_node("SpawnPoint")
	if spawn_point:
		PlayerManager.spawn(spawn_point.global_transform)
	runner.simulate_frames(1)

func _on_recording_stopped(frame_count, replay_path):
	last_replay_path = replay_path

func test_record_30_seconds_random_movement():
	get_tree().current_scene = runner.scene()
	var snapshot_interval = 10 # Should match SNAPSHOT_INTERVAL in ReplayRecorder
	# Ensure player is spawned and physics has settled
	runner.simulate_frames(2)
	var input_state_node = null
	if runner.scene().has_node("InputState"):
		input_state_node = runner.scene().get_node("InputState")
	# Start recording after player is in tree
	replay_recorder.start_recording()
	assert_that(replay_recorder.is_recording()).is_true()

	# Simulate input and let physics process handle recording
	for i in range(10):
		if input_state_node:
			input_state_node.actions["move_forward"] = true
			input_state_node.axes["move_y"] = 1.0
		yield(runner.simulate_frames(1), "completed")
		if input_state_node:
			input_state_node.actions["move_forward"] = false
			input_state_node.axes["move_y"] = 0.0

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
	print("JSON JSON JSON: ", json)
	assert_that(json.error).is_equal(OK)
	var data = json.result

	# Validate metadata
	assert_dict(data).contains_keys(["godot_version"])
	assert_dict(data).contains_keys(["game_version"])
	assert_dict(data).contains_keys(["timestamp"])
	assert_dict(data).contains_keys(["scene_path"])

	# Validate initial states
	assert_dict(data).contains_keys(["initial_states"])
	assert_dict(data).contains_keys(["initial_states_frame"])

	# Validate frames
	assert_dict(data).contains_keys(["frames"])
	assert_that(data["frames"].size()).is_greater(0)

	# Check some frames have required keys
	if data["frames"].size() > 0:
		var frame = data["frames"][0]
		assert_that(frame).contains_keys(["inputs"])
		assert_that(frame).contains_keys(["axes"])
		assert_that(frame).contains_keys(["mouse_delta"])
		assert_that(frame).contains_keys(["frame_index"])
		assert_that(frame).contains_keys(["player_flags"])
	else:
		push_error("No frames recorded")
		assert_that(false).is_true()

	# Validate snapshots stored in `frame_states` every SNAPSHOT_INTERVAL (10)
	var total_frames = data["frames"].size()
	var frame_states_count = data.get("frame_states", []).size()
	if total_frames >= snapshot_interval:
		assert_that(frame_states_count).is_greater(0)
	# Validate final states
	assert_dict(data).contains_keys(["final_states"])
	assert_dict(data).contains_keys(["final_states_frame"])
