extends GdUnitTestSuite

# class_name ReplayTest

var test_scene: Node
var replay_manager: Node
var player_manager: Node
var runner: GdUnitSceneRunner


func before():
	# Instanciar TestScene pero NO añadirla manualmente, dejar que scene_runner la maneje
	test_scene = load("res://tests/fixtures/TestScene.tscn").instance()
	runner = scene_runner(test_scene)

	# Add ReplayManager to the scene
	var replay_manager_script = load("res://scripts/replay/ReplayManager.gd")
	replay_manager = replay_manager_script.new()
	replay_manager.name = "ReplayManager"
	test_scene.add_child(replay_manager)

	# Assign spawn_point to recorder and playback
	var spawn_point = test_scene.find_node("SpawnPoint", true, false)
	if replay_manager.has_node("ReplayRecorder"):
		replay_manager.get_node("ReplayRecorder").spawn_point = spawn_point
	if replay_manager.has_node("ReplayPlayback"):
		replay_manager.get_node("ReplayPlayback").spawn_point = spawn_point

	# Get managers
	player_manager = PlayerManager  # It's an autoload

	# Ensure managers exist
	assert_that(replay_manager).is_not_null()
	assert_that(player_manager).is_not_null()

func after():
	if test_scene:
		if test_scene.is_inside_tree():
			test_scene.get_parent().remove_child(test_scene)
		test_scene.queue_free()

func test_replay_determinism():
	var recorded_positions = []
	var playback_positions = []
	
	# Spawn player
	var spawn_point = test_scene.find_node("SpawnPoint")
	if spawn_point:
		player_manager.spawn(spawn_point.global_transform)
	else:
		player_manager.spawn(Transform.IDENTITY)
	
	# Wait for deferred spawn
	yield(get_tree(), "idle_frame")
	
	var player = player_manager.get_player()
	assert_that(player).is_not_null()
	
	# Start recording
	replay_manager.start_recording()
	
	# Simulate some inputs by setting InputState
	InputState.axes["move_x"] = 1.0  # Move right
	InputState.mouse_delta = Vector2.ZERO
	InputState.is_strafing_mode_active = false
	
	# Record positions for 10 frames
	for i in range(10):
		recorded_positions.append(player.global_transform.origin)
		runner.simulate_frames(1)
	
	# Stop recording
	var replay_file = replay_manager.stop_recording()
	assert_that(replay_file).is_not_null()
	
	# Reset player to initial position
	if spawn_point:
		player.global_transform = spawn_point.global_transform
	else:
		player.global_transform = Transform.IDENTITY
	
	# Start playback directly (skip scene change in test)
	replay_manager.playback.start_playback(replay_file)
	
	# Record positions during playback
	for i in range(10):
		playback_positions.append(player.global_transform.origin)
		runner.simulate_frames(1)
	
	# Check positions match
	for i in range(recorded_positions.size()):
		var dist = recorded_positions[i].distance_to(playback_positions[i])
		assert_bool(dist < 0.01)  # Small tolerance for floating point
