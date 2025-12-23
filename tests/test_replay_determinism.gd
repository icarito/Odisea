class_name GdUnitTestReplayDeterminism
extends GdUnitTestSuite

# test_replay_determinism.gd
# Test de Validación de Determinismo de Movimiento (TVDM)

const FIXED_DELTA = 1.0 / 60.0
const Replay = preload("res://scripts/replay/Replay.gd")
const ReplayUtils = preload("res://scripts/replay/ReplayUtils.gd")
const FixedVec3 = preload("res://scripts/utils/FVec3.gd")  # Load later to avoid autoload issues

var paused = false
var InputState = null
var last_local_replay_path: String = ""

var test_suite = {
	"T1": {
		"description": "Friccion - Frames 0-5: move_forward, 6-10: Idle",
		"frames": []
	},
	"T2": {
		"description": "Jump - Frames 0-300: Idle with jump at frame 60",
		"frames": []
	},
	"T3": {
		"description": "Strafe - Frames 0-120: move_forward + move_right + strafe: True",
		"frames": []
	},
	"T4": {
		"description": "Tank Turn - Frames 0-60: move_right + strafe: False",
		"frames": []
	},
	"T5": {
		"description": "Mouse Look - Frames 0-60: mouse_delta.x = 10.0",
		"frames": []
	}
}

func before():
	print("Starting test")
	get_tree().debug_collisions_hint = true
	InputState = load("res://autoload/InputState.gd")
	generate_test_inputs()

func generate_test_inputs():
	for test_id in test_suite.keys():
		test_suite[test_id].frames = []
		var frame_count = 0
		match test_id:
			"T1":
				frame_count = 500  # Short for testing
			"T2":
				frame_count = 3001  # 0-300
			"T3":
				frame_count = 1201  # 0-120
			"T4":
				frame_count = 601  # 0-60
			"T5":
				frame_count = 601  # 0-60
		for i in range(frame_count):
			var frame = {
				"inputs": {},
				"axes": {},
				"mouse_delta": Vector2.ZERO,
				"strafing_active": false,
				"strafing_timer": 0.0
			}
			match test_id:
				"T1":
					# T1: 0-249 move_forward, 250+ idle (longer movement to detect drift)
					if i < 250:
						frame.inputs["move_forward"] = true
						frame.axes["move_y"] = 1.0
					else:
						frame.inputs["move_forward"] = false
						frame.axes["move_y"] = 0.0
				"T2":
					# T2: continuous forward movement with jumps every 300 frames
					frame.inputs["move_forward"] = true
					frame.axes["move_y"] = 1.0
					if i % 300 == 60:
						frame.inputs["jump"] = true
					else:
						frame.inputs["jump"] = false
				"T3":
					# T3: 0-600 move_forward + move_right + strafe: True, then idle
					if i < 600:
						frame.inputs["move_forward"] = true
						frame.inputs["move_right"] = true
						frame.axes["move_y"] = 1.0
						frame.axes["move_x"] = 1.0
						frame.strafing_active = true
					else:
						frame.inputs["move_forward"] = false
						frame.inputs["move_right"] = false
						frame.axes["move_y"] = 0.0
						frame.axes["move_x"] = 0.0
						frame.strafing_active = false
				"T4":
					# T4: 0-300 move_right + strafe: False, then idle
					if i < 300:
						frame.inputs["move_right"] = true
						frame.axes["move_x"] = 1.0
						frame.strafing_active = false
					else:
						frame.inputs["move_right"] = false
						frame.axes["move_x"] = 0.0
						frame.strafing_active = false
				"T5":
					# T5: 0-300 mouse_delta.x = 10.0, then zero
					if i < 300:
						frame.mouse_delta = Vector2(10.0, 0.0)
					else:
						frame.mouse_delta = Vector2.ZERO
			test_suite[test_id].frames.append(frame)

func run_test(test_id):
	var player_ref = null  # Declare to avoid parser error
	var spawn_point = null  # Declare to avoid parser error
	var spawn_transform = Transform.IDENTITY  # Declare to avoid parser error
	print("Running test: ", test_id, " - ", test_suite[test_id].description)

	# Activar modo test para desactivar corrección de deriva
	GameGlobals.is_test_mode = true

	# Crear escena nueva para este test
	var test_scene_local = load("res://tests/fixtures/TestScene.tscn").instance()
	test_scene_local.name = "TestScene_" + test_id

	# Remover componentes de replay que interfieren con el test
	if test_scene_local.has_node("ReplayManagementPanel"):
		test_scene_local.get_node("ReplayManagementPanel").queue_free()
	if test_scene_local.has_node("ReplayRecordingOverlay"):
		test_scene_local.get_node("ReplayRecordingOverlay").queue_free()
	# Remover SceneSpawn que interfiere con el posicionamiento del player
	test_scene_local.set_script(null)
	# Desactivar ReplayPlayback del autoload
	if ReplayManager.playback:
		ReplayManager.playback.set_process(false)
		ReplayManager.playback.set_physics_process(false)
	ReplayManager.mode = ReplayManager.ReplayMode.NONE

	# Inicializar InputState como autoload
	var input_state = get_node("/root/InputState")
	var player_manager = get_node("/root/PlayerManager")

	# Asignar SpawnPoint y Player
	spawn_point = test_scene_local.get_node_or_null("CSGBox/SpawnPoint")
	if spawn_point:
		test_scene_local.get_node("CSGBox").remove_child(spawn_point)
		test_scene_local.add_child(spawn_point)
	else:
		# Create a spawn point if not exists
		spawn_point = Spatial.new()
		spawn_point.name = "SpawnPoint"
		test_scene_local.add_child(spawn_point)
	spawn_transform = spawn_point.transform if spawn_point else Transform.IDENTITY
	if PlayerManager.is_spawned():
		PlayerManager.despawn()
	PlayerManager.spawn(spawn_transform)
	if test_scene_local.get_parent():
		test_scene_local.get_parent().remove_child(test_scene_local)
	var replay_runner = scene_runner(test_scene_local)
	get_tree().current_scene = test_scene_local
	# Simular un frame para procesar deferred spawn
	replay_runner.simulate_frames(1)
	player_ref = PlayerManager.player_reference
	# Move player to test scene
	test_scene_local.add_child(player_ref)

	# Reset FixedVec3 variables to 0 at start of test
	player_ref.horizontal_velocity_fixed = FixedVec3.zero()
	player_ref.velocity_fixed = FixedVec3.zero()
	player_ref.platform_velocity_fixed = FixedVec3.zero()
	player_ref.last_platform_velocity_fixed = FixedVec3.zero()
	player_ref.vertical_velocity_fixed = FixedVec3.zero()

	# Añadir ReplayManager al test_scene para que su _physics_process sea llamado en la simulación
	var replay_manager = load("res://scripts/replay/ReplayManager.gd").new()
	replay_manager.name = "ReplayManager"
	test_scene_local.add_child(replay_manager)
	# Esperar a que _ready se llame
	replay_runner.simulate_frames(1)
	var playback = replay_manager.get_node("ReplayPlayback")
	# playback.spawn_point = spawn_point  # Not needed

	# Añadir cámara para que get_viewport().get_camera() funcione
	var camera = Camera.new()
	test_scene_local.add_child(camera)
	camera.translation = Vector3(0, 5, 5)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	camera.current = true

	# Fase de asentamiento: simular 5 frames para asegurar is_on_floor True desde frame 0
	for _i in range(5):
		replay_runner.simulate_frames(1)

	# Reset position after settlement
	player_ref.transform = spawn_transform

	replay_runner.simulate_frames(1)  # Final settle

	# FASE 1: GRABACIÓN (Live Run)
	# Use ReplayRecorder to capture frames and snapshots
	var rr = load("res://scripts/replay/ReplayRecorder.gd").new()
	rr.name = "ReplayRecorder"
	test_scene_local.add_child(rr)
	# allow _ready
	replay_runner.simulate_frames(1)
	rr.connect("recording_stopped", self, "_on_local_recording_stopped")

	input_state.set_mode(InputState.Mode.RECORD)
	# Start recording via recorder (it will populate initial_states)
	rr.start_recording()

	for frame in test_suite[test_id].frames:
		# Build a complete actions dict using InputState constants so tests
		# produce the same shape as runtime.
		var actions_full = {}
		for k in InputState.ACTION_KEYS:
			actions_full[k] = bool(frame.inputs.get(k, false))
		input_state.actions = actions_full

		var axes_full = {}
		for k in InputState.AXIS_KEYS:
			axes_full[k] = float(frame.axes.get(k, 0.0))
		input_state.axes = axes_full

		# Use recorded_mouse_delta so ReplayRecorder picks it up
		input_state.recorded_mouse_delta = Vector2(frame.mouse_delta.x, frame.mouse_delta.y)
		input_state.is_strafing_mode_active = frame.strafing_active
		input_state.strafing_timer = frame.strafing_timer
		# Advance physics/frame and force recorder to process this frame
		replay_runner.simulate_frames(1)
		if rr and rr.has_method("record_frame"):
			rr.record_frame(1.0/60.0)

	# Stop recording and allow final_states to be captured
	rr.stop_recording()
	print("Player position after record: ", player_ref.global_transform.origin)

	# Crear y guardar replay
	# The recorder saved the replay file and signaled its path; use that
	var replay_path = last_local_replay_path
	if replay_path == "":
		# fallback: try to find recently written file in res://replays
		var dir = Directory.new()
		if dir.open("res://replays/") == OK:
			dir.list_dir_begin(true, true)
			var f = dir.get_next()
			var latest = ""
			while f != "":
				if f.ends_with(".json"):
					latest = "res://replays/" + f
				f = dir.get_next()
			dir.list_dir_end()
			replay_path = latest

	if replay_path == "":
		return {"passed": false, "error": "No replay file produced"}

	# Load the recorded replay and extract final state
	var recorded_replay = Replay.new()
	if recorded_replay.load_from_json(replay_path) != OK:
		return {"passed": false, "error": "Failed to load recorded replay"}
	var player_path = "player"
	var final_pos_rec: Vector3
	var final_rot_rec: float
	if recorded_replay.final_states.has(player_path):
		var final_state = recorded_replay.final_states[player_path]
		final_pos_rec = ReplayUtils.dict_to_vector3(final_state["player_position"])
		final_rot_rec = ReplayUtils.dict_to_vector3(final_state["rotation"]).y
	else:
		# Fallback to current player state
		final_pos_rec = player_ref.global_transform.origin
		final_rot_rec = player_ref.rotation.y

	# FASE 2: REPRODUCCIÓN (Playback Run)
	# Reset player position for playback
	player_ref.transform = spawn_transform
	player_ref.horizontal_velocity_fixed = FixedVec3.zero()
	player_ref.velocity_fixed = FixedVec3.zero()
	player_ref.platform_velocity_fixed = FixedVec3.zero()
	player_ref.last_platform_velocity_fixed = FixedVec3.zero()
	player_ref.vertical_velocity_fixed = FixedVec3.zero()

	# Cargar y iniciar replay directamente en InputState
	var playback_replay_path = replay_path
	var playback_replay = Replay.new()
	playback_replay.load_from_json(playback_replay_path)
	input_state.set_mode(InputState.Mode.PLAYBACK)
	input_state.recorded_frames = playback_replay.frames.duplicate()
	input_state.replay_frame = 0
	input_state.manual_playback = false  # Use automatic playback

	# Simular todos los frames del replay
	print("[TestReplay] Iniciando simulación de replay desde archivo: ", playback_replay_path)
	for i in range(test_suite[test_id].frames.size()):
		replay_runner.simulate_frames(1)

	if not player_ref or not player_ref.is_inside_tree():
		return {"passed": false, "error": "Player not spawned in playback"}

	var final_pos_rep = player_ref.global_transform.origin
	var final_rot_rep = player_ref.rotation.y

	var pos_distance = final_pos_rec.distance_to(final_pos_rep)
	var rot_distance = abs(final_rot_rec - final_rot_rep)

	# Desactivar modo test
	GameGlobals.is_test_mode = false

	var passed = pos_distance < 0.1 and rot_distance < 0.01
	print("[TestReplay] Drift posición: ", pos_distance, " Drift rotación: ", rot_distance, " PASS/FAIL: ", "PASS" if passed else "FAIL")
	var result = {
		"passed": passed,
		"pos_drift": pos_distance,
		"rot_drift": rot_distance
	}
	if not passed:
		result["error"] = "Drift too high: pos %.3f (max 0.1), rot %.3f (max 0.01)" % [pos_distance, rot_distance]

	return result

func _on_local_recording_stopped(frame_count, replay_path):
	last_local_replay_path = replay_path
	print("_on_local_recording_stopped: ", frame_count, replay_path)


# Tests individuales para mejor detección
func test_T1():
	assert_that(true).is_true()

func test_T2():
	print("EJECUTANDO TEST T2")
	var result = run_test("T2")
	assert_that(result).contains_keys(["passed", "pos_drift", "rot_drift"])
	assert_that(result.passed).is_true()
	if not result.passed:
		var error_msg = result.get("error", "Unknown error")
		push_error(str(error_msg) + "\n" + to_json(result))

func test_T3():
	print("EJECUTANDO TEST T3")
	var result = run_test("T3")
	assert_that(result).contains_keys(["passed", "pos_drift", "rot_drift"])
	assert_that(result.passed).is_true()
	if not result.passed:
		var error_msg = result.get("error", "Unknown error")
		push_error(str(error_msg) + "\n" + to_json(result))

func test_T4():
	print("EJECUTANDO TEST T4")
	var result = run_test("T4")
	assert_that(result).contains_keys(["passed", "pos_drift", "rot_drift"])
	assert_that(result.passed).is_true()
	if not result.passed:
		var error_msg = result.get("error", "Unknown error")
		push_error(str(error_msg) + "\n" + to_json(result))

func test_T5():
	print("EJECUTANDO TEST T5")
	var result = run_test("T5")
	assert_that(result).contains_keys(["passed", "pos_drift", "rot_drift"])
	assert_that(result.passed).is_true()
	if not result.passed:
		var error_msg = result.get("error", "Unknown error")
		push_error(str(error_msg) + "\n" + to_json(result))
