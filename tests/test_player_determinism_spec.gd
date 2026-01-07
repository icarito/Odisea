# /tests/test_player_determinism_spec.gd
extends GdUnitTestSuite

const TEST_REPLAY_PATH = "res://tests/fixtures/reference.json"
const FIXED_DELTA = 1.0 / 60.0
const FixedVec3 = preload("res://scripts/utils/FVec3.gd")

var _test_player: KinematicBody
var _test_scene: Node = null
var _player_manager: Node = null
var _original_player_scene_path: String = ""
var _recorder_removed: bool = false
var _original_debug_mode: bool = false
var replay_data: Dictionary
var frames: Array
var frame_states_dict: Dictionary
var yaw_node: Spatial
var _camera_instance: Node = null

func before():
	# 1. Cargar el archivo de referencia
	var file = File.new()
	if file.open(TEST_REPLAY_PATH, File.READ) == OK:
		var json_result = JSON.parse(file.get_as_text())
		if json_result.error == OK:
			replay_data = json_result.result
		file.close()
	
	if replay_data.empty():
		print("Error: El archivo JSON está vacío o no se cargó correctamente.")
		return
	
	assert_bool(replay_data.empty()).is_false()

	# Asegurarse de que las claves existen en replay_data
	assert_bool(replay_data.has("frames")).is_true()
	assert_bool(replay_data.has("frame_states")).is_true()
	assert_bool(replay_data.has("initial_states")).is_true()
	assert_bool(replay_data.initial_states.has("player")).is_true()

	frames = replay_data.frames
	var frame_states = replay_data.frame_states
	frame_states_dict = {}
	for fs in frame_states:
		frame_states_dict[fs.frame_index] = fs

	# 2. Cargar la escena de test con suelo y colisiones
	_test_scene = load("res://tests/fixtures/TestScene.tscn").instance()
	add_child(_test_scene)

	# 3. Instanciar al jugador para el test
	var scene = load("res://players/elias/Pilot.tscn")
	_test_player = scene.instance()
	# CRÍTICO: Desactivar físicas ANTES de añadir al árbol para evitar el "frame fantasma".
	_test_player.set_physics_process(false)
	_test_scene.add_child(_test_player)

	# Disable debug flags on the instantiated player and children to avoid debug prints
	if _has_prop(_test_player, "debug_enabled"):
		_test_player.debug_enabled = false
	for c in _test_player.get_children():
		if _has_prop(c, "debug_enabled"):
			c.debug_enabled = false
	# If PlayerManager exists, tell it about our player instance to avoid duplicate spawns
	if has_node("/root/PlayerManager"):
		_player_manager = get_node("/root/PlayerManager")
		# store original scene path so we can restore it
		_original_player_scene_path = _player_manager.player_scene_path
		_player_manager.player_reference = _test_player
		# Prevent PlayerManager from instancing its own player during the test
		_player_manager.player_scene_path = ""
		_player_manager._initial_spawn_transform = _test_player.global_transform
	
	# 4. Obtener el CameraRig que ya es parte de la escena del jugador.
	var camera_rig = _test_player.get_node_or_null("CameraRig")
	assert_object(camera_rig).is_not_null()
	# Guardar una referencia para usar en el bucle de frames
	_camera_instance = camera_rig
	# No setear propiedades dinámicas en PlayerController (no existen 'camera_rig' ni 'player_camera')
	# Asegurarse de que exista un InputState local en el jugador para inyección por frame
	if not _test_player.has_node("InputState"):
		var player_input_state = preload("res://autoload/InputState.gd").new()
		player_input_state.name = "InputState"
		player_input_state.manual_playback = true
		player_input_state.set_mode(player_input_state.Mode.PLAYBACK)
		_test_player.add_child(player_input_state)
	yaw_node = _camera_instance.get_node("Yaw")
	# Apply absolute initial camera state deterministically
	if replay_data.initial_states.has("camera") and _camera_instance and _camera_instance.has_method("set_replay_state"):
		_camera_instance.set_replay_state(replay_data.initial_states.camera)
	else:
		yaw_node.rotation.y = replay_data.initial_states.camera_yaw

	# Signal test mode to GameGlobals so PlayerController disables gravity when appropriate
	if GameGlobals:
		# Preserve and disable debug logs during tests to avoid noisy output
		_original_debug_mode = GameGlobals.debug_mode if GameGlobals.has_method("get") or true else false
		GameGlobals.debug_mode = false
		GameGlobals.is_test_mode = true
	# Remove active ReplayRecorder (if any) to avoid it holding resources during test
	if has_node("/root/ReplayManager"):
		var rm = get_node("/root/ReplayManager")
		if rm and rm.has_node("ReplayRecorder"):
			rm.get_node("ReplayRecorder").queue_free()
			_recorder_removed = true

func test_full_determinism_cycle():
	# 3-FASES: 1) Live usando referencia (generar grabación), 2) Playback de la grabación, 3) Comparaciones
	var recording_frames = []
	var found_first_divergence = false
	var first_divergence = -1

	# --- FASE REFERENCE (aplicar frame_states del JSON) ---
	# Instanciar un jugador de referencia y aplicar por frame los estados grabados en el JSON.
	# Esto reproduce exactamente la secuencia de estados original y da una posición "Reference" para comparar.
	var scene_ref = load("res://players/elias/Pilot.tscn")
	var ref_player = scene_ref.instance()
	_test_scene.add_child(ref_player)
	var ref_camera = ref_player.get_node_or_null("CameraRig")
	# Apply initial states (safely)
	if replay_data.initial_states.has("player") and ref_player.has_method("set_replay_state"):
		ref_player.set_replay_state(replay_data.initial_states.player)
	if replay_data.initial_states.has("camera") and ref_camera and ref_camera.has_method("set_replay_state"):
		ref_camera.set_replay_state(replay_data.initial_states.camera)
	# Run the reference sequence using frame_states
	if GameGlobals:
		GameGlobals.is_replaying = true
		GameGlobals.is_test_mode = false
	for frame in frames:
		var fidx = frame.frame_index if typeof(frame) == TYPE_DICTIONARY and frame.has("frame_index") else -1
		if frame_states_dict.has(fidx):
			var fs = frame_states_dict[fidx]
			if fs.has("player") and ref_player.has_method("set_replay_state"):
				ref_player.set_replay_state(fs.player)
			if fs.has("camera") and ref_camera and ref_camera.has_method("set_replay_state"):
				ref_camera.set_replay_state(fs.camera)
		# Avanzar física
		ref_player._physics_process(FIXED_DELTA)
		if ref_camera != null and ref_camera.has_method("_physics_process"):
			ref_camera._physics_process(FIXED_DELTA)
	var final_pos_ref_sim = ref_player.global_transform.origin
	# Limpiar referencia
	if is_instance_valid(ref_player):
		ref_player.free()
	# Restaurar flags para LIVE
	if GameGlobals:
		GameGlobals.is_replaying = false
		GameGlobals.is_test_mode = true

	# --- FASE LIVE (generar grabación) ---
	# --- INICIO: Inyección de Estado Inicial Forzada (Hard-State Injection) ---
	# Desactivar física automática y sincronizar estado inicial completo
	_test_player.set_physics_process(false) # CRÍTICO: evitar frame fantasma
	if replay_data.initial_states.has("player"):
		_test_player.set_replay_state(replay_data.initial_states.player)
	# Forzar el cronómetro del InputState para que coincida con la referencia
	if _test_player.has_node("PlayerInput"):
		var pi = _test_player.get_node("PlayerInput")
		if replay_data.initial_states.player.has("time_since_input"):
			pi.time_since_input = replay_data.initial_states.player.time_since_input
	if replay_data.initial_states.has("camera") and _camera_instance and _camera_instance.has_method("set_replay_state"):
		_camera_instance.set_replay_state(replay_data.initial_states.camera)
	# IMPORTANTE: No se llama a _physics_process ni move_and_slide aquí.
	# La simulación comienza dentro del bucle para asegurar la sincronización del frame 0.
	printerr("[INFO] Injected initial state. Waiting for loop to start physics.")

	if GameGlobals:
		GameGlobals.is_replaying = false
		GameGlobals.is_test_mode = true
	var input_state = get_node("/root/InputState")
	if input_state:
		# Usar modo PLAYBACK+manual para que los mouse_delta sean aplicados exactamente como en la grabación
		input_state.set_mode(input_state.Mode.PLAYBACK)
		input_state.manual_playback = true
	# Asegurar que PlayerInput NO esté en modo replay durante LIVE
	if _test_player.has_node("PlayerInput"):
		_test_player.get_node("PlayerInput").is_replay_mode = false

	for frame in frames:
		# 1. Inyectar inputs
		var inputs = frame.inputs
		var axes = frame.get("axes", {"move_x": 0.0, "move_y": 0.0})
		if input_state:
			input_state.axes["move_x"] = axes.get("move_x", 0.0)
			input_state.axes["move_y"] = axes.get("move_y", 0.0)
			input_state.actions["jump"] = inputs.get("jump", false)
			input_state.actions["run"] = inputs.get("run", false) if inputs.has("run") else inputs.get("sprint", false)
			input_state.actions["roll"] = inputs.get("roll", false)
			var md = Vector2.ZERO
			if frame.has("mouse_delta"):
				md = Vector2(FixedPoint.from_fixed(frame.mouse_delta.x), FixedPoint.from_fixed(frame.mouse_delta.y))
				input_state.mouse_delta = md
				if _test_player.has_node("InputState"):
					_test_player.get_node("InputState").mouse_delta = md
		# Inyectar a PlayerInput para que las consultas de estado internas respeten inputs
		if _test_player.has_node("PlayerInput"):
			_test_player.get_node("PlayerInput").inject_input(inputs)

		# 2. PROCESAR MANUALMENTE física y cámara
		_test_player._physics_process(FIXED_DELTA)
		if is_instance_valid(_camera_instance):
			_camera_instance._physics_process(FIXED_DELTA)

		# 3. CAPTURAR EL ESTADO (debe ser idéntico al JSON)
		var rec_player = _test_player.get_replay_state() if _test_player.has_method("get_replay_state") else {}
		var rec_camera = _camera_instance.get_replay_state() if _camera_instance and _camera_instance.has_method("get_replay_state") else {}
		recording_frames.append({"player": rec_player, "camera": rec_camera, "inputs": inputs})

		# --- Per-frame divergence check (Reference vs Live): log first differing frame
		if not found_first_divergence and frame_states_dict.has(frame.frame_index):
			var ref_fs = frame_states_dict[frame.frame_index]
			# reference position (fixed point -> float) - guard keys/types
			var pos_diff = 0.0
			var ref_pos_str = "null"
			if ref_fs.has("player") and typeof(ref_fs.player) == TYPE_DICTIONARY and ref_fs.player.has("position"):
				var p = ref_fs.player["position"]
				if p != null and typeof(p) == TYPE_ARRAY and p.size() >= 3:
					var ref_pos = Vector3(FixedPoint.from_fixed(p[0]), FixedPoint.from_fixed(p[1]), FixedPoint.from_fixed(p[2]))
					var sim_pos = _test_player.global_transform.origin
					pos_diff = sim_pos.distance_to(ref_pos)
					ref_pos_str = str(ref_pos)
			# camera yaw (guard keys)
			var yaw_diff = 0.0
			var ref_yaw_str = "null"
			if ref_fs.has("camera") and typeof(ref_fs.camera) == TYPE_DICTIONARY and ref_fs.camera.has("yaw"):
				var ref_yaw = FixedPoint.from_fixed(ref_fs.camera["yaw"])
				var sim_yaw = null
				if _camera_instance != null and _camera_instance.has_method("get_yaw"):
					sim_yaw = _camera_instance.get_yaw()
				if sim_yaw != null:
					yaw_diff = abs(sim_yaw - ref_yaw)
					ref_yaw_str = str(ref_yaw)
			if pos_diff > 0.001 or yaw_diff > 0.001:
				var sim_pos_str = str(_test_player.global_transform.origin)
				var sim_yaw_str = "null"
				if _camera_instance != null and _camera_instance.has_method("get_yaw"):
					sim_yaw_str = str(_camera_instance.get_yaw())
				
				# --- INICIO: Volcado de estado detallado para diagnóstico ---
				var ref_state_dump = ref_fs.player if ref_fs.has("player") else {}
				var live_state_dump = _test_player.dump_state() if _test_player.has_method("dump_state") else {}
				
				printerr("======================================================================")
				printerr("[DIVERGENCE DETECTED] Frame: %d" % frame.frame_index)
				printerr("------------------ REFERENCE STATE ------------------")
				printerr(ref_state_dump)
				printerr("-------------------- LIVE STATE ---------------------")
				printerr(live_state_dump)
				printerr("======================================================================")
				printerr("[DIVERGENCE] frame=%d pos_diff=%f yaw_diff=%f ref_pos=%s sim_pos=%s ref_yaw=%s sim_yaw=%s" % [frame.frame_index, pos_diff, yaw_diff, ref_pos_str, sim_pos_str, ref_yaw_str, sim_yaw_str])
				found_first_divergence = true
				first_divergence = frame.frame_index
	# After live loop: capture final live position
	var final_pos_live = _test_player.global_transform.origin
	# Prefer the simulated Reference final position, fallback to the stored final_state in JSON
	var final_pos_ref = final_pos_ref_sim if (typeof(final_pos_ref_sim) != TYPE_NIL) else ReplayUtils.dict_to_vector3(replay_data.final_states.player.player_position)
	var drift_live_vs_ref = final_pos_live.distance_to(final_pos_ref)
	print("[REPORT] Drift Live vs Reference:", drift_live_vs_ref)
	# report frame counts
	var last_frame_index = -1
	if frames.size() > 0:
		var lf = frames[frames.size()-1]
		if typeof(lf) == TYPE_DICTIONARY and lf.has("frame_index"):
			last_frame_index = lf["frame_index"]
	print("[INFO] frames_count=", frames.size(), " last_frame_index_processed=", last_frame_index)
	# If we found a first divergence record it, otherwise attempt to find approx first by looser threshold
	if found_first_divergence:
		print("[REPORT] First divergence frame:", first_divergence)
	else:
		# Dump keys for the first few frames to inspect shaping of recorded vs reference frames
		for k in range(0, min(6, min(recording_frames.size(), frames.size()))):
			var rec = recording_frames[k]
			var reff = frames[k]
			var rec_keys = []
			var ref_keys = []
			if rec and rec.has("player") and typeof(rec.player) == TYPE_DICTIONARY:
				rec_keys = rec.player.keys()
			if reff and typeof(reff) == TYPE_DICTIONARY and reff.has("player") and typeof(reff.player) == TYPE_DICTIONARY:
				ref_keys = reff.player.keys()
			print("[KEYS] idx=", k, " rec_keys=", rec_keys, " ref_keys=", ref_keys)
		# Try detect with looser threshold scanning recorded snapshots
		for i in range(0, recording_frames.size()):
			var rf = recording_frames[i]
			# Do not assume rf.inputs has frame_index; defensive only
			if rf.has("player"):
				# placeholder for future heuristics
				pass
		# Print a minimal scan for the first frame where abs difference exceeds 0.01
		for j in range(0, min(recording_frames.size(), frames.size())):
			var rec = recording_frames[j]
			var meta = frames[j]
			var frame_index = -1
			if typeof(meta) == TYPE_DICTIONARY and meta.has("frame_index"):
				frame_index = meta["frame_index"]
			var ref_frame = null
			if frame_states_dict.has(frame_index):
				ref_frame = frame_states_dict[frame_index]
			if rec.has("player") and ref_frame != null and ref_frame.has("player"):
				var rec_pos = null
				if rec.player.has("player_position"):
					var rp = rec.player.player_position
					if rp != null:
						rec_pos = Vector3(rp.x, rp.y, rp.z)
				var ref_v = null
				if typeof(ref_frame) == TYPE_DICTIONARY and ref_frame.has("player") and typeof(ref_frame.player) == TYPE_DICTIONARY and ref_frame.player.has("player_position"):
					var p2 = ref_frame.player["player_position"]
					if p2 != null:
						ref_v = Vector3(p2.x, p2.y, p2.z)
				if ref_v != null and rec_pos != null and rec_pos.distance_to(ref_v) > 0.01:
					var idx = frame_index
					print("[SCAN] approx_first_diff_frame=", idx, " diff=", rec_pos.distance_to(ref_v))
					break
		# If the drift is still large, run a fine-grained scan comparing pos, yaw and pre_move_velocity to locate earliest differing frame
		if drift_live_vs_ref > 0.5:
			for i in range(0, min(recording_frames.size(), frames.size())):
				var meta = frames[i]
				var frame_index = -1
				if typeof(meta) == TYPE_DICTIONARY and meta.has("frame_index"):
					frame_index = meta["frame_index"]
				var ref_frame = null
				if frame_states_dict.has(frame_index):
					ref_frame = frame_states_dict[frame_index]
				var live_frame = recording_frames[i]
				# ensure required keys exist
				if ref_frame == null or not (ref_frame.has("player") and typeof(ref_frame.player) == TYPE_DICTIONARY) or not (live_frame.has("player") and typeof(live_frame.player) == TYPE_DICTIONARY):
					continue
				# extract
				var ref_pos = null
				var live_pos = null
				var ref_yaw = null
				var live_yaw = null
				var ref_pmv = null
				var live_pmv = null
				if ref_frame.player.has("player_position"):
					var p = ref_frame.player["player_position"]
					if p != null:
						ref_pos = Vector3(p.x, p.y, p.z)
					if ref_frame.player.has("rotation"):
						ref_yaw = ref_frame.player["rotation"].y if ref_frame.player["rotation"] != null else null
					if ref_frame.player.has("pre_move_velocity"):
						var rpv = ref_frame.player["pre_move_velocity"]
						if rpv != null:
							ref_pmv = Vector3(rpv.x, rpv.y, rpv.z)
				if live_frame.player.has("player_position"):
					var lp = live_frame.player["player_position"]
					if lp != null:
						live_pos = Vector3(lp.x, lp.y, lp.z)
					if live_frame.player.has("rotation"):
						live_yaw = live_frame.player["rotation"].y if live_frame.player["rotation"] != null else null
					if live_frame.player.has("pre_move_velocity"):
						var lpv = live_frame.player["pre_move_velocity"]
						if lpv != null:
							live_pmv = Vector3(lpv.x, lpv.y, lpv.z)
				# compare with tight thresholds
				if ref_pos != null and live_pos != null:
					var pos_diff = ref_pos.distance_to(live_pos)
					var yaw_diff = 0.0
					if ref_yaw != null and live_yaw != null:
						yaw_diff = abs(ref_yaw - live_yaw)
					var pmv_diff = 0.0
					if ref_pmv != null and live_pmv != null:
						pmv_diff = ref_pmv.distance_to(live_pmv)
					if pos_diff > 0.001 or yaw_diff > 0.01 or pmv_diff > 0.001:
						print("[SCAN-FINE] first_approx_diff_frame=", i, " pos=", pos_diff, " yaw=", yaw_diff, " pmv=", pmv_diff)
					print("[SCAN-FINE] ref_pos=", str(ref_pos), " live_pos=", str(live_pos))
					# Dump full player dictionaries for deeper inspection
					print("[SCAN-FINE] ref_player=", str(ref_frame.player))
					print("[SCAN-FINE] live_player=", str(live_frame.player))
					if ref_frame.has("camera"):
						print("[SCAN-FINE] ref_camera=", str(ref_frame.camera))
					if live_frame.has("camera"):
						print("[SCAN-FINE] live_camera=", str(live_frame.camera))
					# Dump a small window of nearby frames to observe how the divergence grows
					var start_idx = max(0, i - 3)
					var end_idx = min(recording_frames.size() - 1, i + 3)
					print("[SCAN-FINE] Nearby frames window: ", start_idx, "..", end_idx)
					for k in range(start_idx, end_idx + 1):
						var meta_k = frames[k]
						var fk_idx = -1
						if typeof(meta_k) == TYPE_DICTIONARY and meta_k.has("frame_index"):
							fk_idx = meta_k["frame_index"]
						var r_k = frame_states_dict[fk_idx] if frame_states_dict.has(fk_idx) else null
						var l_k = recording_frames[k]
						var r_pos = Vector3(r_k.player["player_position"].x, r_k.player["player_position"].y, r_k.player["player_position"].z) if r_k != null and r_k.has("player") and r_k.player.has("player_position") and r_k.player["player_position"] != null else null
						var l_pos = Vector3(l_k.player["player_position"].x, l_k.player["player_position"].y, l_k.player["player_position"].z) if l_k != null and l_k.has("player") and l_k.player.has("player_position") and l_k.player["player_position"] != null else null
						var r_yaw = r_k.player["rotation"].y if r_k != null and r_k.has("player") and r_k.player.has("rotation") and r_k.player["rotation"] != null else null
						var l_yaw = l_k.player["rotation"].y if l_k != null and l_k.has("player") and l_k.player.has("rotation") and l_k.player["rotation"] != null else null
						var r_floor = r_k.player["was_on_floor"] if r_k != null and r_k.has("player") and r_k.player.has("was_on_floor") else null
						var l_floor = l_k.player["was_on_floor"] if l_k != null and l_k.has("player") and l_k.player.has("was_on_floor") else null
						var r_tsi = r_k.player["time_since_input"] if r_k != null and r_k.has("player") and r_k.player.has("time_since_input") else null
						var l_tsi = l_k.player["time_since_input"] if l_k != null and l_k.has("player") and l_k.player.has("time_since_input") else null
						var r_cam = r_k.camera if r_k != null and r_k.has("camera") else null
						var l_cam = l_k.camera if l_k != null and l_k.has("camera") else null
						print("[WIND] frame_idx=", fk_idx, " r_pos=", str(r_pos), " l_pos=", str(l_pos), " r_yaw=", str(r_yaw), " l_yaw=", str(l_yaw), " r_floor=", str(r_floor), " l_floor=", str(l_floor), " r_tsi=", str(r_tsi), " l_tsi=", str(l_tsi), " r_cam=", str(r_cam), " l_cam=", str(l_cam))
					break
	assert_float(drift_live_vs_ref).is_less_equal(0.05)

	# --- FASE PLAYBACK (usar la grabación generada) ---
	# Resetear: instanciar jugador limpio para simular escenario de playback
	if is_instance_valid(_test_player):
		_test_player.free()
	# Reinstanciar y preparar
	var scene = load("res://players/elias/Pilot.tscn")
	_test_player = scene.instance()
	# Añadir como hijo del test node para evitar dependencias de current_scene
	add_child(_test_player)
	# Actualizar referencia a cámara
	_camera_instance = _test_player.get_node_or_null("CameraRig")
	yaw_node = _camera_instance.get_node("Yaw") if _camera_instance else null

	# Activar modo playback de reproducción interna
	if GameGlobals:
		GameGlobals.is_replaying = true
		# Permitir que playback_process aplique transforms
		GameGlobals.is_test_mode = false
	# InputState en modo playback para compatibilidad
	if input_state:
		input_state.set_mode(input_state.Mode.PLAYBACK)
		input_state.manual_playback = true
	# PlayerInput en modo replay
	if _test_player.has_node("PlayerInput"):
		_test_player.get_node("PlayerInput").is_replay_mode = true

	for saved in recording_frames:
		# Aplicar snapshot que grabamos en Live
		if saved.has("player"):
			_test_player.playback_process(saved.player, FIXED_DELTA)
		# Aplicar cámara grabada
		if saved.has("camera") and _camera_instance and _camera_instance.has_method("set_replay_state"):
			_camera_instance.set_replay_state(saved.camera)
		# Avanzar física
		_test_player._physics_process(FIXED_DELTA)

	var final_pos_playback = _test_player.global_transform.origin

	# --- COMPARACIONES ---
	var drift_playback_vs_live = final_pos_playback.distance_to(final_pos_live)
	print("[REPORT] Drift Playback vs Live:", drift_playback_vs_live)
	assert_float(drift_playback_vs_live).is_less_equal(0.001)  # Playback debería reproducir exactamente el Live
	# Restaurar test flags
	if GameGlobals:
		GameGlobals.is_test_mode = true
		GameGlobals.is_replaying = false


func after():
	# 1. Liberar la escena de prueba y la cámara explícitamente para evitar orphans.
	if is_instance_valid(_test_scene):
		_test_scene.free() # Usar free() para limpieza inmediata
		_test_scene = null
	if is_instance_valid(_camera_instance):
		_camera_instance.free()

	# 2. Restaurar el estado de PlayerManager si fue modificado.
	if is_instance_valid(_player_manager):
		_player_manager.player_reference = null
		_player_manager.player_scene_path = _original_player_scene_path

	# Restore GameGlobals test flags and restore debug_mode
	if GameGlobals:
		GameGlobals.is_test_mode = false
		GameGlobals.is_replaying = false
		GameGlobals.debug_mode = _original_debug_mode
	# Recreate ReplayRecorder if we removed it in before()
	if _recorder_removed and has_node("/root/ReplayManager"):
		var rm = get_node("/root/ReplayManager")
		var rr_script = load("res://scripts/replay/ReplayRecorder.gd")
		if rr_script:
			var rr = rr_script.new()
			rr.name = "ReplayRecorder"
			rm.add_child(rr)
			_recorder_removed = false
	# Restore global InputState to LIVE
	var input_state = get_node_or_null("/root/InputState")
	if input_state:
		input_state.manual_playback = false
		input_state.set_mode(input_state.Mode.LIVE)

# Prefijar variables no utilizadas con un guion bajo
var _mouse_motion = Vector2.ZERO
var _replay_manager = null
var _h_rot = 0.0
var _game_globals = null
var _scaled_motion = Vector3.ZERO
var _recorded_state = {}
var _vertical_divergence = 0.0
var _on_floor = false

# Resolver conflictos de nombres
var player_instance = _test_player

# Corregir tipos de datos
export(float) var example_float = 0.0
export(float) var another_float = 0.0

# Prefijar argumentos no utilizados con un guion bajo
func _on_capture_changed(_is_captured):
	pass

func _on_replay_mode_changed(_new_mode):
	pass

func _apply_rotation(_delta):
	pass

func spawn_network_player(_spawn_point):
	pass

func record_frame(_delta):
	pass

func check_for_drift(_frame_data):
	pass

func _apply_velocity_drift_correction(_frame_data):
	pass

func _has_prop(obj, prop_name):
	# Safe property existence check via get_property_list()
	var pls = obj.get_property_list()
	for p in pls:
		if typeof(p) == TYPE_DICTIONARY and p.has("name") and p.name == prop_name:
			return true
	return false
