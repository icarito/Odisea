extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# test_replay_determinism.gd
# Test de Validación de Determinismo de Movimiento (TVDM)

const FIXED_DELTA = 1.0 / 60.0
const Replay = preload("res://scripts/replay/Replay.gd")
const FixedVec3 = preload("res://scripts/utils/FVec3.gd")  # Load later to avoid autoload issues

var paused = false
var InputState = null

var test_suite = {
	"T1": {
		"description": "Friccion - Frames 0-150: move_forward, 151-300: Idle",
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
		for i in range(300):
			var frame = {
				"inputs": {},
				"axes": {},
				"mouse_delta": Vector2.ZERO,
				"strafing_active": false,
				"strafing_timer": 0.0
			}
			match test_id:
				"T1":
					# T1: 0-150 move_forward, 151-300 idle
					if i < 150:
						frame.inputs["move_forward"] = true
						frame.axes["move_y"] = 1.0
					else:
						frame.inputs["move_forward"] = false
						frame.axes["move_y"] = 0.0
				"T2":
					# T2: idle, salto en frame 60
					frame.inputs["move_forward"] = false
					frame.axes["move_y"] = 0.0
					if i == 60:
						frame.inputs["jump"] = true
					else:
						frame.inputs["jump"] = false
				"T3":
					# T3: 0-120 move_forward + move_right + strafe: True
					if i < 120:
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
					# T4: 0-60 move_right + strafe: False
					if i < 60:
						frame.inputs["move_right"] = true
						frame.axes["move_x"] = 1.0
						frame.strafing_active = false
					else:
						frame.inputs["move_right"] = false
						frame.axes["move_x"] = 0.0
						frame.strafing_active = false
				"T5":
					# T5: 0-60 mouse_delta.x = 10.0
					if i < 60:
						frame.mouse_delta = Vector2(10.0, 0.0)
					else:
						frame.mouse_delta = Vector2.ZERO
			test_suite[test_id].frames.append(frame)

func run_test(test_id):
	var player_scene = null  # Declare to avoid parser error
	var spawn_point = null  # Declare to avoid parser error
	var spawn_transform = Transform.IDENTITY  # Declare to avoid parser error
	print("Running test: ", test_id, " - ", test_suite[test_id].description)

	# Activar modo test para desactivar corrección de deriva
	GameGlobals.is_test_mode = true

	# Crear escena nueva para este test
	var test_scene_local = load("res://tests/fixtures/TestScene.tscn").instance()

	# Remover componentes de replay que interfieren con el test
	if test_scene_local.has_node("ReplayManagementPanel"):
		test_scene_local.get_node("ReplayManagementPanel").queue_free()
	if test_scene_local.has_node("ReplayRecordingOverlay"):
		test_scene_local.get_node("ReplayRecordingOverlay").queue_free()
	# Desactivar ReplayPlayback del autoload
	if ReplayManager.playback:
		ReplayManager.playback.set_process(false)
		ReplayManager.playback.set_physics_process(false)
	ReplayManager.mode = ReplayManager.ReplayMode.NONE

	# Añadir ReplayManager al test_scene para que su _physics_process sea llamado en la simulación
	# var replay_manager = load("res://scripts/replay/ReplayManager.gd").new()
	# replay_manager.name = "ReplayManager"
	# test_scene_local.add_child(replay_manager)

	# Inicializar InputState como autoload
	var input_state = get_node("/root/InputState")

	# Asignar SpawnPoint y Player
	spawn_point = test_scene_local.get_node("CSGBox/SpawnPoint")
	test_scene_local.get_node("CSGBox").remove_child(spawn_point)
	test_scene_local.add_child(spawn_point)
	spawn_transform = spawn_point.transform if spawn_point else Transform.IDENTITY
	player_scene = load("res://players/elias/Pilot.tscn").instance()
	if not player_scene:
		test_scene_local.queue_free()
		return {"passed": false, "error": "Failed to instance player scene", "pos_drift": 0.0, "rot_drift": 0.0}
	test_scene_local.add_child(player_scene)
	player_scene.transform = spawn_transform
	PlayerManager.player_reference = player_scene

	# Reset FixedVec3 variables to 0 at start of test
	player_scene.horizontal_velocity_fixed = FixedVec3.zero()
	player_scene.velocity_fixed = FixedVec3.zero()
	player_scene.platform_velocity_fixed = FixedVec3.zero()
	player_scene.last_platform_velocity_fixed = FixedVec3.zero()
	player_scene.vertical_velocity_fixed = FixedVec3.zero()

	var runner = scene_runner(test_scene_local)

	# Añadir cámara para que get_viewport().get_camera() funcione
	var camera = Camera.new()
	test_scene_local.add_child(camera)
	camera.translation = Vector3(5, 5, 5)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	camera.current = true

	# Fase de asentamiento: simular 5 frames para asegurar is_on_floor True desde frame 0
	for _i in range(5):
		runner.simulate_frames(1)

	# Reset position after settlement
	player_scene.transform = spawn_transform

	# Asignar spawn_point manualmente para el test (como en simulate_session)
	# if replay_manager and replay_manager.has_node("ReplayRecorder"):
	# 	replay_manager.get_node("ReplayRecorder").spawn_point = spawn_point
	# 	replay_manager.get_node("ReplayRecorder").player = player_scene
	# if replay_manager and replay_manager.has_node("ReplayPlayback"):
	# 	replay_manager.get_node("ReplayPlayback").spawn_point = spawn_point

	# FASE 1: GRABACIÓN (Live Run)
	input_state.set_mode(InputState.Mode.RECORD)
	input_state.recorded_frames = []  # Reset
	input_state.manual_playback = true
	for frame in test_suite[test_id].frames:
		input_state.actions = frame.inputs.duplicate()
		input_state.axes = frame.axes.duplicate()
		input_state.mouse_delta = Vector2(frame.mouse_delta.x, frame.mouse_delta.y)
		input_state.is_strafing_mode_active = frame.strafing_active
		input_state.strafing_timer = frame.strafing_timer
		runner.simulate_frames(1)
		input_state._record_current_frame()
	input_state.manual_playback = false

	# Crear y guardar replay
	var replay = load("res://scripts/replay/Replay.gd").new()
	replay.frames = input_state.recorded_frames.duplicate()
	replay.scene_path = "res://tests/fixtures/TestScene.tscn"
	replay.godot_version = Engine.get_version_info()["string"]
	replay.game_version = "dev"
	replay.timestamp = str(OS.get_unix_time())
	replay.initial_states = {
		"player": {
			"position": player_scene.global_transform.origin,
			"rotation": player_scene.rotation
		},
		"camera": {
			"position": camera.global_transform.origin,
			"rotation": camera.global_transform.basis.get_euler()
		}
	}
	# Guardar estado final análogo a initial_states
	replay.final_states = {
		"player": {
			"position": player_scene.global_transform.origin,
			"rotation": player_scene.rotation
		},
		"camera": {
			"position": camera.global_transform.origin,
			"rotation": camera.global_transform.basis.get_euler()
		}
	}
	var replay_path = "user://replays/test_" + test_id + ".json"
	replay.save_to_json(replay_path)

	# Posición final grabada
	var final_pos_rec = input_state.recorded_frames[-1]["pilot_pos"]
	var final_rot_rec = input_state.recorded_frames[-1]["pilot_rot"]

	# FASE 2: REPRODUCCIÓN (Playback Run)
	input_state.recorded_frames = replay.frames.duplicate()
	input_state.mode = InputState.Mode.PLAYBACK
	input_state.replay_frame = 0
	input_state.manual_playback = true
	# Aplicar manualmente los inputs grabados en cada frame durante playback
	for i in range(input_state.recorded_frames.size()):
		var frame = input_state.recorded_frames[i]
		input_state.actions = frame.inputs.duplicate()
		input_state.axes = frame.axes.duplicate()
		input_state.mouse_delta = Vector2(frame.mouse_delta.x, frame.mouse_delta.y)
		input_state.is_strafing_mode_active = frame.has("strafing_active") and frame.strafing_active
		input_state.strafing_timer = frame.strafing_timer if frame.has("strafing_timer") else 0.0
		runner.simulate_frames(1)
	input_state.manual_playback = false

	var final_pos_rep = player_scene.global_transform.origin
	var final_rot_rep = player_scene.rotation.y

	var pos_distance = final_pos_rec.distance_to(final_pos_rep)
	var rot_distance = abs(final_rot_rec.y - final_rot_rep)

	test_scene_local.queue_free()

	# Desactivar modo test
	GameGlobals.is_test_mode = false

	var passed = pos_distance < 0.1 and rot_distance < 0.01
	var result = {
		"passed": passed,
		"pos_drift": pos_distance,
		"rot_drift": rot_distance
	}
	if not passed:
		result["error"] = "Drift too high: pos %.3f (max 0.1), rot %.3f (max 0.01)" % [pos_distance, rot_distance]

	return result


# Test parametrizado para todos los casos de determinismo
func test_replay_determinism(test_id : String, test_parameters := [["T1"], ["T2"], ["T3"], ["T4"], ["T5"]]):
	var result = run_test(test_id)
	assert_that(result.passed).is_true()
	if not result.passed:
		var error_msg = result.get("error", "Unknown error")
		push_error(str(error_msg) + "\n" + to_json(result))
	assert_bool(result.pos_drift < 0.1)
	assert_bool(result.rot_drift < 0.01)

func simulate_session(inputs_or_path, mode, test_id, runner):
	# GameGlobals.determinism_test = true  # Commented out for headless compatibility

	# Load FixedVec3 here to avoid autoload issues
	var FixedVec3 = load("res://scripts/utils/FVec3.gd")

	# TestScene ya está cargada en _setup_scene
	var test_scene = runner.scene()

	# Añadir cámara de test
	var camera = Camera.new()
	test_scene.add_child(camera)
	camera.translation = Vector3(5, 5, 5)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	camera.current = true

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var drift_label = test_scene.get_node("DriftOverlay/DriftLabel")
	if drift_label == null:
		print("DriftLabel not found")
		drift_label = null

	# Asegurar que ReplayManager esté presente
	var replay_manager = null
	if not get_node_or_null("/root/ReplayManager"):
		replay_manager = load("res://scripts/replay/ReplayManager.gd").new()
		replay_manager.name = "ReplayManager"
		get_tree().root.add_child(replay_manager)
	else:
		replay_manager = get_node("/root/ReplayManager")

	# Configurar InputState
	var input_state = null
	if not get_node_or_null("/root/InputState"):
		input_state = load("res://autoload/InputState.gd").new()
		input_state.name = "InputState"
		get_tree().root.add_child(input_state)
	else:
		input_state = get_node("/root/InputState")
	input_state.set_mode(mode)
	input_state.recorded_frames.clear()
	input_state.replay_frame = 0

	# Buscar SpawnPoint en la escena
	var spawn_point = test_scene.find_node("SpawnPoint", true, false)
	var spawn_transform = spawn_point.global_transform if spawn_point else Transform.IDENTITY

	# Instanciar Player en el SpawnPoint
	var player_scene = load("res://players/elias/Pilot.tscn").instance()
	test_scene.add_child(player_scene)
	player_scene.global_transform = spawn_transform
	print("Initial player position (", mode, "): ", player_scene.global_transform.origin)
	PlayerManager.player_reference = player_scene
	if replay_manager and replay_manager.has_node("ReplayRecorder"):
		replay_manager.get_node("ReplayRecorder").player = player_scene
	player_scene.InputState = input_state  # Asignar manualmente

	# Asignar spawn_point manualmente para el test
	if replay_manager and replay_manager.has_node("ReplayRecorder"):
		replay_manager.get_node("ReplayRecorder").spawn_point = spawn_point
	if replay_manager and replay_manager.has_node("ReplayPlayback"):
		replay_manager.get_node("ReplayPlayback").spawn_point = spawn_point

	# Conectar PlayerManager si es necesario (opcional, según arquitectura)

	var frames_recorded = []
	if mode == InputState.Mode.RECORD:
		# Para record, inyectar frames directamente
		var frame_count = 0
		for frame in inputs_or_path:
			var new_frame = frame.duplicate()
			input_state.actions = new_frame.inputs.duplicate()
			input_state.axes = new_frame.axes.duplicate()
			input_state.mouse_delta = Vector2(new_frame.mouse_delta.x, new_frame.mouse_delta.y)
			input_state.is_strafing_mode_active = new_frame.strafing_active
			input_state.strafing_timer = new_frame.strafing_timer
			input_state._record_current_frame()
			runner.simulate_frames(1)
			new_frame["pilot_pos"] = spawn_point.to_local(player_scene.global_transform.origin)
			new_frame["pilot_rot"] = player_scene.global_transform.basis.get_euler().y
			print("Frame %d: Velocity: %s" % [frame_count, FixedVec3.to_vec3(player_scene.velocity_fixed)])
			frames_recorded.append(new_frame)
			frame_count += 1
	else:
		# Cargar replay
		var replay_path = inputs_or_path
		var replay = Replay.new()
		replay.load_from_json(replay_path)
		input_state.recorded_frames = replay.frames
		runner.simulate_frames(300)

	var final_pos = player_scene.global_transform.origin
	var final_rot = player_scene.rotation.y

	test_scene.remove_child(player_scene)
	player_scene.free()  # Uncommented
	test_scene.remove_child(camera)
	camera.free()  # Uncommented
	# Don't free test_scene, it's reused for multiple simulations
	PlayerManager.player_reference = null
	if replay_manager and replay_manager.has_node("ReplayRecorder"):
		replay_manager.get_node("ReplayRecorder").player = null

	return {
		"final_pos": final_pos,
		"final_rot": final_rot,
		"frames": frames_recorded if mode == InputState.Mode.RECORD else []
	}
