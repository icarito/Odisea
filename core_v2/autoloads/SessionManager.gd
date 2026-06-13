extends Node
const FIXED_DT := 1.0 / 60.0
const REPLAY_WATCHDOG_STALL_FRAMES := 900
var _is_validating := false # Re-entry protection
var _replay_watchdog_frames := 0 # Safety counter for stalled replays/tests
var _replay_watchdog_last_input_index := -1
const EARLY_WEAK_HINT_ENV := "ODISEA_EARLY_WEAK_HARDWARE"
const EARLY_WEAK_RAM_GB_CAP := 1.05
const EARLY_WEAK_DEVICE_HINTS := [
	"anbernic",
	"rg351",
	"rk3326",
	"mali",
]

signal replay_finished(success, drift, frames)
signal oys_registry_reset
signal startup_gate_opened(reason, waited_frames)

var player: KinematicBody = null
var _player_searched = false
var buffer := []
var is_recording := false
var is_manual_mode := false # Flag para tests (desactiva auto-scene loading)
var is_replaying := false
var replay_meta := {} # Metadatos del replay
var final_expected_state = null
var is_cli_mode := false
var _drift_validated := false
var _is_replaying_fail_loop := false # Flag para evitar loops infinitos si falla
var _should_snapshot := false
var _current_replay_path := ""
var _current_replay_data := {} # To persist data from OYS or JSON during execution
var event_timeline := {}
var oys_variables := {}
var _peak_y := -999.0
var _active_input_provider = null
var _replay_input_provider = null
var _replay_input_buffer := []
var oys_interpreter = null
var oys_assert_failed = false
var _pending_asserts := []
var _pending_setters := []
var _monitored_signals = {}
var _env_vars := {}
var _session_spawned_nodes := []
const SESSION_SPAWN_GROUP := "_oys_session_spawned"

var ghost_manager = null

# Optimization: Cache for replay_sync group
var _replay_sync_cache := []
var _replay_sync_cache_dirty := true

# Optimization: Cache for node lookups
var _node_cache := {}

# Drift correction: checkpoint pendiente para guardar en el próximo frame
var _pending_drift_checkpoint := false
# Drift correction: frame en el que guardar un checkpoint "settle" (15 frames después del contacto)
var _pending_settle_checkpoint_frame := -1
# Drift correction en replay: diccionario {frame_index: position}
var _drift_checkpoints := {}
# Contador de frames durante grabación
var _recording_frame := 0
# Sobrecarga de input para OYS Live execution
var _oys_input_override := {}
# Escena solicitada por OYS para guardar en meta
var _oys_requested_scene := ""
# Flag para indicar que estamos esperando el fin de un respawn para validar
var _is_waiting_for_respawn_validation := false
# Flag para indicar que estamos en proceso de respawn (los triggers no deben ejecutarse)
var is_respawning := false
var _session_run_id := 0
var _system_launch_counter := 1000
var _rl_mode := false
var _rl_bypass_session_manager := true
const ALLOW_ANNA_IN_REMOTE_DEBUG_ENV := "ODISEA_ALLOW_ANNA_REMOTE_DEBUG"
const REMOTE_DEBUG_FLAGS := ["--remote-debug"]
const ANNA_ENABLED_ENV := "ANNA_ENABLED"
const ANNA_PORT_ENV := "ANNA_PORT"
const SWITCH_ANNA_CONFIG_CANDIDATES := [
	"user://anna.env",
	"user://enable_anna.txt",
	"sdmc:/switch/Odisea/anna.env",
	"sdmc:/switch/Odisea/enable_anna.txt",
]
const STARTUP_GATE_FRAMES_FAST := 2
const STARTUP_GATE_FRAMES_WEAK := 18
const STARTUP_GATE_MAX_WAIT_FRAMES := 720
const STARTUP_GATE_FRAMES_ENV := "ODISEA_STARTUP_GATE_FRAMES"
const MOBILE_WEB_SAFETY_ENV := "ODISEA_MOBILE_WEB_SAFETY"
const MOBILE_WEB_WEAK_ENV := "ODISEA_WEB_WEAK_DEVICE"
const MOBILE_WEB_RENDER_SCALE_ENV := "ODISEA_MOBILE_WEB_RENDER_SCALE"
const MOBILE_WEB_RENDER_SCALE_DEFAULT := 0.67
const MOBILE_WEB_RENDER_SCALE_MIN := 0.5
const MOBILE_WEB_RENDER_SCALE_MAX := 1.0
const MOBILE_WEB_GRAPHICS_PROFILE_DEFAULT := "medium"
const MOBILE_WEB_TARGET_FPS_DEFAULT := "30"
const MOBILE_WEB_TRANSPARENCY_ENV := "ODISEA_DIAG_DISABLE_TRANSPARENCIES"
const DISABLE_GLOW_ENV := "ODISEA_DISABLE_GLOW"
const DISABLE_FXAA_ENV := "ODISEA_DISABLE_FXAA"
const MOBILE_WEB_MIN_RENDER_SIZE := Vector2(320, 180)
var _early_weak_hardware := false
var _mobile_web_safety_enabled := false
var _startup_gate_open := false
var _startup_gate_started := false
var _startup_gate_waited_frames := 0
var _startup_gate_reason := ""
var _performance_mitigation_active := false

func _enter_tree() -> void:
	_mobile_web_safety_enabled = _should_enable_mobile_web_safety(
		OS.get_name(),
		OS.has_touchscreen_ui_hint(),
		OS.get_environment(MOBILE_WEB_SAFETY_ENV)
	)
	_early_weak_hardware = _detect_weak_hardware_early()
	if _early_weak_hardware:
		_apply_early_weak_hardware_hints()
	if _mobile_web_safety_enabled:
		_apply_mobile_web_safety_hints()

func _normalize_negative_zero_in_place(value):
	var t = typeof(value)
	if t == TYPE_DICTIONARY:
		for key in value.keys():
			value[key] = _normalize_negative_zero_in_place(value[key])
		return value
	if t == TYPE_ARRAY:
		for i in range(value.size()):
			value[i] = _normalize_negative_zero_in_place(value[i])
		return value
	if t == TYPE_REAL and abs(value) < 0.0000001:
		return 0
	return value

func _json_print_normalized(data, indent := "") -> String:
	var normalized = data
	if typeof(data) in [TYPE_DICTIONARY, TYPE_ARRAY]:
		normalized = data.duplicate(true)
	normalized = _normalize_negative_zero_in_place(normalized)
	return JSON.print(normalized, indent)

func _get_replay_sync_nodes() -> Array:
	if _replay_sync_cache_dirty:
		var all_nodes = get_tree().get_nodes_in_group("replay_sync")
		var active_scene = _get_active_scene_root()
		var filtered = []
		for node in all_nodes:
			if not is_instance_valid(node):
				continue
			if not is_instance_valid(active_scene) or active_scene.is_a_parent_of(node):
				filtered.append(node)
		filtered.sort_custom(self , "_sort_nodes_by_path")
		_replay_sync_cache = filtered
		_replay_sync_cache_dirty = false
	return _replay_sync_cache

func _sort_nodes_by_path(a: Node, b: Node) -> bool:
	if not is_instance_valid(a):
		return false
	if not is_instance_valid(b):
		return true
	return str(a.get_path()) < str(b.get_path())

func _on_node_added(node: Node):
	if node.is_in_group("replay_sync"):
		_replay_sync_cache_dirty = true

func _on_node_removed(node: Node):
	if node.is_in_group("replay_sync"):
		_replay_sync_cache_dirty = true

func _find_player():
	# Prioridad 0: Si ya tenemos una instancia válida y no está siendo borrada, usarla
	if _is_player_candidate_valid(player):
		_initialize_player_for_session(player)
		return

	# Prioridad 1: Buscar en el grupo 'player' (más robusto contra renombrados (@Pilot@...))
	var pilots = get_tree().get_nodes_in_group("player")
	for p in pilots:
		if _is_player_candidate_valid(p):
			player = p
			_initialize_player_for_session(player)
			return

	# Backup recursive search removed for performance.
	# Rely on 'player' group registration.

	if not is_respawning and not _is_waiting_for_respawn_validation:
		# Solo loguear si no estamos esperando activamente un respawn
		# print("[SessionManager] _find_player: No se encontró al jugador.")
		pass
	player = null
	
func _is_player_candidate_valid(p) -> bool:
	if not is_instance_valid(p):
		return false
	if p.is_queued_for_deletion():
		return false
	if not p.is_inside_tree():
		return false
	var scene = get_tree().current_scene
	if is_instance_valid(scene) and not scene.is_a_parent_of(p):
		return false
	return true

func _initialize_player_for_session(p):
	if is_recording or is_replaying:
		if not p.is_replay_mode:
			p.is_replay_mode = true
			print("[SessionManager] Player initialized for session: is_replay_mode=true")
		p.set_physics_process(false)


var _live_export_on_exit := false
var _video_export_mode := false
var _live_export_launch_in_progress := false

func _on_tree_changed_for_live_recording():
	get_tree().set_auto_accept_quit(false)
	_prepare_live_video_export_recording_runtime()
	var attempts := 0
	while attempts < 90:
		_find_player()
		if is_instance_valid(player):
			start_recording()
			return
		attempts += 1
		yield (get_tree(), "idle_frame")
	printerr("[SessionManager] Live export: could not find player to start recording.")

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		if _live_export_on_exit:
			if _live_export_launch_in_progress:
				print("[LiveExport] Export launch already in progress. Waiting before quitting.")
				return
			if is_recording:
				call_deferred("_finalize_live_recording_with_video_export", true)
				return
			get_tree().quit(0)

func _prepare_live_video_export_recording_runtime() -> void:
	# Live export should not alter gameplay audio; silence is applied in the spawned export process.
	OS.set_environment("ODISEA_DISABLE_SHADER_WARMUP", "1")
	OS.set_environment("ODISEA_MUTE_AUDIO_HEADLESS", "0")
	OS.set_environment("ODISEA_FORCE_MUTE_AUDIO", "0")

func _log_live_export_status(message: String) -> void:
	print("[LiveExport] ", message)

func _build_live_export_process_args(saved_path: String) -> Array:
	var args = ["--no-window", "--fixed-fps", "60", "--video-export", saved_path]
	var export_audio_driver = OS.get_environment("ODISEA_VIDEO_EXPORT_AUDIO_DRIVER").strip_edges()
	if export_audio_driver == "":
		export_audio_driver = "Dummy"
	args.append("--audio-driver")
	args.append(export_audio_driver)
	return args

func _spawn_live_video_export_async(saved_path: String) -> bool:
	var exec_path = OS.get_executable_path()
	OS.set_environment("ODISEA_DISABLE_SHADER_WARMUP", "1")
	OS.set_environment("ODISEA_MUTE_AUDIO_HEADLESS", "0")
	OS.set_environment("ODISEA_FORCE_MUTE_AUDIO", "0")
	var args = _build_live_export_process_args(saved_path)
	print("\n=======================================================")
	print("🎥 [LiveExport] Launching async video export...")
	print("📂 Replay source: ", saved_path)
	print("🧵 Gameplay will continue while export runs in a separate process.")
	print("=======================================================\n")
	var ret = OS.execute(exec_path, args, false)
	if ret < 0:
		printerr("[LiveExport] Failed to launch export process: ", ret)
		return false
	_log_live_export_status("Export process launched. Replay save is done; screenshots and ffmpeg continue in background.")
	return true

func _finalize_live_recording_with_video_export(quit_after_export: bool = false) -> void:
	if _live_export_launch_in_progress:
		return
	_live_export_launch_in_progress = true
	_log_live_export_status("Saving live replay...")
	var saved_path = stop_and_save_recording()
	if saved_path == "":
		_live_export_launch_in_progress = false
		printerr("[LiveExport] Could not save live replay.")
		if quit_after_export:
			get_tree().quit(1)
		return
	var success = _spawn_live_video_export_async(saved_path)
	_live_export_launch_in_progress = false
	if not success:
		printerr("[LiveExport] Video export launch failed.")
	if quit_after_export:
		get_tree().quit(0 if success else 1)

func _reset_replay_watchdog(provider = null) -> void:
	_replay_watchdog_frames = 0
	_replay_watchdog_last_input_index = -1
	if is_instance_valid(provider):
		_replay_watchdog_last_input_index = int(provider.playback_index)

func _tick_replay_watchdog(provider) -> void:
	if not is_replaying or _is_waiting_for_respawn_validation:
		_reset_replay_watchdog(provider)
		return

	var is_progressing := false
	var current_index := _replay_watchdog_last_input_index
	var buffer_size := -1

	if is_instance_valid(provider) and provider.mode == provider.Mode.REPLAY:
		current_index = int(provider.playback_index)
		buffer_size = provider.playback_buffer.size()
		if current_index >= buffer_size:
			_reset_replay_watchdog(provider)
			return
		is_progressing = current_index != _replay_watchdog_last_input_index

	if is_progressing:
		_replay_watchdog_last_input_index = current_index
		_replay_watchdog_frames = 0
		return

	_replay_watchdog_frames += 1
	if _replay_watchdog_frames > REPLAY_WATCHDOG_STALL_FRAMES:
		printerr("[SessionManager] WATCHDOG: Replay stalled at input %d/%d. Forcing termination." % [current_index, buffer_size])
		_finish_and_validate()

func _ready():
	_rl_mode = OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]
	var bypass_env = OS.get_environment("ANNA_RL_BYPASS_SESSION_MANAGER").to_lower()
	if bypass_env != "":
		_rl_bypass_session_manager = bypass_env in ["1", "true", "yes", "on"]
	if _mobile_web_safety_enabled:
		_apply_mobile_web_render_scale()
		call_deferred("_apply_mobile_web_render_scale")
	# Initialize Ghost Manager
	var ghost_script = load("res://core_v2/ghost/GhostManager.gd")
	if ghost_script:
		ghost_manager = ghost_script.new()
		add_child(ghost_manager)

	# Listen for node additions to update cached group
	get_tree().connect("node_added", self , "_on_node_added")
	get_tree().connect("node_removed", self , "_on_node_removed")
	# --- Environment Variables (Prop Validation Pipeline) ---
	_env_vars["$sys_env_prop_path"] = OS.get_environment("OYS_PROP_PATH")
	_env_vars["$sys_env_auto_run"] = OS.get_environment("OYS_AUTO_RUN")

	# --- Project A.N.N.A Integration ---
	var anna_runtime = _resolve_anna_runtime_config()
	if bool(anna_runtime.get("enabled", false)):
		var allow_remote_anna = OS.get_environment(ALLOW_ANNA_IN_REMOTE_DEBUG_ENV).to_lower() in ["1", "true", "yes", "on"]
		if _is_vscode_remote_debug_session():
			allow_remote_anna = true
		if _is_remote_debug_session() and not allow_remote_anna:
			print("[SessionManager] Skipping AnnaBridge in remote-debug session for stability (%s=1 to override)." % ALLOW_ANNA_IN_REMOTE_DEBUG_ENV)
		else:
			var anna_port = String(anna_runtime.get("port", "")).strip_edges()
			if anna_port != "":
				OS.set_environment(ANNA_PORT_ENV, anna_port)
			var reason = String(anna_runtime.get("reason", "")).strip_edges()
			var source = String(anna_runtime.get("source", "")).strip_edges()
			if source != "" and source != "env" and source != "vscode":
				reason += " (%s)" % source
			_ensure_anna_bridge_enabled(reason)

	# Detección de parámetro --replay
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--snapshot":
			_should_snapshot = true
		if arg == "--replay" and i + 1 < args.size():
			is_cli_mode = true
			var replay_path = args[i + 1]
			# NO llamamos a load_and_play aquí. La escena aún no está lista.
			# En su lugar, nos conectamos a la señal 'tree_changed'.
			# Se disparará cuando la escena principal se cargue, y entonces ejecutaremos el replay.
			get_tree().connect("tree_changed", self , "_on_tree_changed_for_replay", [replay_path], CONNECT_ONESHOT)
			return
		
		if arg == "--run-script" and i + 1 < args.size():
			is_cli_mode = true
			var script_path = args[i + 1]
			get_tree().connect("tree_changed", self , "_on_tree_changed_for_script", [script_path], CONNECT_ONESHOT)
			return

		if arg == "--video-export" or arg == "--export-video":
			_video_export_mode = true
			if i + 1 < args.size() and not args[i + 1].begins_with("--") and (args[i + 1].ends_with(".json") or args[i + 1].ends_with(".oys")):
				_prepare_video_export_runtime()
				is_cli_mode = true
				var replay_path = args[i + 1]
				get_tree().connect("tree_changed", self , "_on_tree_changed_for_replay", [replay_path, true], CONNECT_ONESHOT)
				return
			else:
				_prepare_live_video_export_recording_runtime()
				_live_export_on_exit = true
				get_tree().connect("tree_changed", self , "_on_tree_changed_for_live_recording", [], CONNECT_ONESHOT)
				continue

	# --- Instanciar y conectar TeleportSystem (instanciación robusta) ---
	if not has_node("TeleportSystem"):
		var ts_res = load("res://core_v2/systems/TeleportSystem.gd")
		if ts_res == null:
			printerr("SessionManager: Could not load TeleportSystem resource: res://core_v2/systems/TeleportSystem.gd")
		else:
			var teleport_system = null
			# If it's a PackedScene, instance it; if it's a Script, call new(); otherwise try both safely
			if ts_res is PackedScene:
				teleport_system = ts_res.instance()
			elif ts_res is GDScript or ts_res is Script:
				# Some Godot versions return GDScript; handle both.
				# Attempt to call new(), but if it's not available, attach the script to a plain Node.
				if ts_res.has_method("new"):
					teleport_system = ts_res.new()
				else:
					teleport_system = Node.new()
					teleport_system.set_script(ts_res)
			else:
				# Attempt to instance or new with defensive checks
				if ts_res.has_method("instance"):
					teleport_system = ts_res.instance()
				elif ts_res.has_method("new"):
					teleport_system = ts_res.new()
				else:
					# Last resort: attach script to a generic Node
					teleport_system = Node.new()
					teleport_system.set_script(ts_res)

			if teleport_system == null:
				printerr("SessionManager: Failed to instantiate TeleportSystem (resource type: ", typeof(ts_res), ").")
			else:
				teleport_system.name = "TeleportSystem"
				add_child(teleport_system)
				# Buscar nodos relevantes tras un pequeño delay para asegurar que la escena está lista
				call_deferred("_connect_teleport_system")

	# --- Auto Run (Prop Validation Pipeline) ---
	if _env_vars["$sys_env_auto_run"] != "":
		var script_path = _env_vars["$sys_env_auto_run"]
		is_cli_mode = true
		get_tree().connect("tree_changed", self , "_on_tree_changed_for_script", [script_path], CONNECT_ONESHOT)

	_begin_startup_gate_monitor()
	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace and startup_trace.has_method("mark"):
		startup_trace.mark("session_manager_ready", {
			"cli_mode": is_cli_mode,
			"video_export_mode": _video_export_mode,
			"early_weak_hardware": _early_weak_hardware
		})

func is_startup_gate_open() -> bool:
	return _startup_gate_open

func get_startup_gate_status() -> Dictionary:
	return {
		"open": _startup_gate_open,
		"started": _startup_gate_started,
		"reason": _startup_gate_reason,
		"waited_frames": _startup_gate_waited_frames
	}

func wait_until_startup_gate_open(max_frames := STARTUP_GATE_MAX_WAIT_FRAMES):
	_begin_startup_gate_monitor()
	var frame_cap = max(0, int(max_frames))
	var waited := 0
	while not _startup_gate_open and waited < frame_cap:
		waited += 1
		yield(get_tree(), "idle_frame")

func _begin_startup_gate_monitor() -> void:
	if _startup_gate_open or _startup_gate_started:
		return
	_startup_gate_started = true
	call_deferred("_resolve_startup_gate_deferred")

func _resolve_startup_gate_deferred() -> void:
	var required_stable_frames = _get_startup_gate_required_stable_frames()
	if required_stable_frames <= 0:
		_open_startup_gate("disabled", 0)
		return
	var stable_frames := 0
	var waited_frames := 0
	while waited_frames < STARTUP_GATE_MAX_WAIT_FRAMES:
		if _is_startup_gate_ready_now():
			stable_frames += 1
			if stable_frames >= required_stable_frames:
				_open_startup_gate("ready", waited_frames)
				return
		else:
			stable_frames = 0
		waited_frames += 1
		yield(get_tree(), "idle_frame")
	_open_startup_gate("timeout", waited_frames)

func _get_startup_gate_required_stable_frames() -> int:
	var required = STARTUP_GATE_FRAMES_WEAK if _early_weak_hardware else STARTUP_GATE_FRAMES_FAST
	var env_value = OS.get_environment(STARTUP_GATE_FRAMES_ENV).strip_edges()
	if env_value.is_valid_integer():
		required = int(env_value)
	return int(clamp(required, 0, STARTUP_GATE_MAX_WAIT_FRAMES))

func _is_startup_gate_ready_now() -> bool:
	var tree = get_tree()
	if tree == null:
		return false
	var scene = tree.current_scene
	if not is_instance_valid(scene):
		return false

	# Verify that VisualServer has actually rendered something
	# This ensures we don't start logic before the first frame is visible.
	# Bypass for tests to avoid breaking determinism logic that relies on immediate start.
	var is_testing = Engine.has_singleton("GdUnit3") and Engine.get_singleton("GdUnit3").is_test_suite()
	if not OS.has_feature("Server") and not is_testing:
		# Gate opens once *either* pipeline has drawn. INFO_OBJECTS_IN_FRAME alone
		# misses 2D-only scenes (e.g. menus), which would stall the gate until timeout.
		var objects_3d = VisualServer.get_render_info(VisualServer.INFO_OBJECTS_IN_FRAME)
		var items_2d = VisualServer.get_render_info(VisualServer.INFO_2D_ITEMS_IN_FRAME)
		if objects_3d <= 0 and items_2d <= 0:
			return false

	if _is_scene_transition_busy():
		return false
	if _startup_gate_requires_player(scene):
		return _has_valid_startup_player()
	return true

func _is_scene_transition_busy() -> bool:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("is_transitioning"):
		return bool(scene_manager.is_transitioning())
	return false

func _startup_gate_requires_player(scene: Node) -> bool:
	if is_cli_mode:
		return false
	if OS.has_feature("Server"):
		return false
	if Engine.has_singleton("GdUnit3") and Engine.get_singleton("GdUnit3").is_test_suite():
		return false
	if not is_instance_valid(scene):
		return false
	var scene_path = String(scene.filename)
	if scene_path.find("Menu.tscn") != -1:
		return false
	if get_tree().get_nodes_in_group("player").empty():
		return false
	return true

func _has_valid_startup_player() -> bool:
	if _is_player_candidate_valid(player):
		return true
	var pilots = get_tree().get_nodes_in_group("player")
	for p in pilots:
		if _is_player_candidate_valid(p):
			player = p
			return true
	return false

func _open_startup_gate(reason: String, waited_frames: int) -> void:
	if _startup_gate_open:
		return
	_startup_gate_open = true
	_startup_gate_reason = reason
	var waited_frames_i: int = int(waited_frames)
	if waited_frames_i > 0:
		_startup_gate_waited_frames = waited_frames_i
	else:
		_startup_gate_waited_frames = 0
	if reason == "timeout":
		printerr("[SessionManager] Startup gate opened by timeout after %d idle frames." % _startup_gate_waited_frames)
	elif _startup_gate_waited_frames > 0:
		print("[SessionManager] Startup gate opened after %d idle frames." % _startup_gate_waited_frames)
	emit_signal("startup_gate_opened", _startup_gate_reason, _startup_gate_waited_frames)

func _ensure_anna_bridge_enabled(reason: String = "") -> Node:
	var existing = get_node_or_null("AnnaBridge")
	if not (existing and is_instance_valid(existing)):
		var tree = get_tree()
		if tree and tree.get_root():
			existing = tree.get_root().find_node("AnnaBridge", true, false)
	if existing and is_instance_valid(existing):
		return existing

	print("[SessionManager] Enabling A.N.N.A Agent Interface...", (" reason=%s" % reason) if reason != "" else "")
	var bridge_res = load("res://core_v2/anna/AnnaBridge.gd")
	if bridge_res == null:
		printerr("[SessionManager] Failed to load AnnaBridge.")
		return null

	var bridge = bridge_res.new()
	bridge.name = "AnnaBridge"
	add_child(bridge)
	return bridge

func perf_capture_start(tag: String = "default") -> void:
	var pm = get_node_or_null("/root/PerformanceMonitor")
	if pm and pm.has_method("start_capture"):
		pm.start_capture(tag)
		return
	printerr("[SessionManager] PerformanceMonitor not available for perf_capture_start().")

func perf_capture_stop(tag: String = "") -> Dictionary:
	var pm = get_node_or_null("/root/PerformanceMonitor")
	if pm and pm.has_method("stop_capture"):
		return pm.stop_capture(tag)
	printerr("[SessionManager] PerformanceMonitor not available for perf_capture_stop().")
	return {}

func _script_requires_anna(script_content: String) -> bool:
	for raw_line in script_content.split("\n"):
		var line = raw_line.strip_edges()
		if line == "":
			continue
		if (line.begins_with("#") or line.begins_with("//")) and line.findn("REQUIRE_ANNA=1") != -1:
			return true
	return false

func _load_switch_anna_config() -> Dictionary:
	var cfg := {
		"enabled": false,
		"port": "",
		"source": "",
	}
	if OS.get_name() != "Switch":
		return cfg
	var file := File.new()
	for path in SWITCH_ANNA_CONFIG_CANDIDATES:
		if not file.file_exists(path):
			continue
		cfg["source"] = path
		if path.ends_with(".txt"):
			cfg["enabled"] = true
			return cfg
		if file.open(path, File.READ) != OK:
			printerr("[SessionManager] Could not open Switch ANNA config: %s" % path)
			return cfg
		while not file.eof_reached():
			var raw_line = file.get_line()
			var line = raw_line.strip_edges()
			if line == "" or line.begins_with("#") or line.begins_with(";"):
				continue
			var eq_idx = line.find("=")
			if eq_idx == -1:
				continue
			var key = line.substr(0, eq_idx).strip_edges()
			var value = line.substr(eq_idx + 1, line.length()).strip_edges()
			if key == ANNA_ENABLED_ENV:
				cfg["enabled"] = value.to_lower() in ["1", "true", "yes", "on"]
			elif key == ANNA_PORT_ENV and value.is_valid_integer():
				cfg["port"] = value
		file.close()
		return cfg
	return cfg

func _resolve_anna_runtime_config() -> Dictionary:
	var config := {
		"enabled": false,
		"port": "",
		"reason": "",
		"source": "",
	}
	var env_enabled = OS.get_environment(ANNA_ENABLED_ENV).strip_edges()
	if env_enabled != "":
		config["enabled"] = env_enabled.to_lower() in ["1", "true", "yes", "on"]
		config["port"] = OS.get_environment(ANNA_PORT_ENV).strip_edges()
		config["reason"] = "%s=%s" % [ANNA_ENABLED_ENV, env_enabled]
		config["source"] = "env"
		return config
	var switch_cfg = _load_switch_anna_config()
	if bool(switch_cfg.get("enabled", false)):
		config["enabled"] = true
		config["port"] = String(switch_cfg.get("port", "")).strip_edges()
		config["reason"] = "Switch ANNA config"
		config["source"] = String(switch_cfg.get("source", ""))
	return config

func _should_enable_anna_bridge() -> bool:
	return bool(_resolve_anna_runtime_config().get("enabled", false))

func _is_vscode_remote_debug_session() -> bool:
	if not _is_remote_debug_session():
		return false
	var vscode_pid = OS.get_environment("VSCODE_PID").strip_edges()
	return vscode_pid != ""

func _is_remote_debug_session() -> bool:
	var args = OS.get_cmdline_args()
	for arg in args:
		if str(arg) in REMOTE_DEBUG_FLAGS:
			return true
	return _proc_cmdline_has_any(REMOTE_DEBUG_FLAGS)

func _proc_cmdline_has_any(flags: Array) -> bool:
	if not OS.get_name() in ["X11", "Linux", "Server"]:
		return false
	var cmdline = _read_process_cmdline()
	if cmdline == "":
		return false
	for flag in flags:
		if String(flag) in cmdline:
			return true
	return false

func _read_process_cmdline() -> String:
	var pid = OS.get_process_id()
	var proc_path = "/proc/%d/cmdline" % pid
	var file = File.new()
	if not file.file_exists(proc_path):
		return ""
	if file.open(proc_path, File.READ) != OK:
		return ""
	var raw := ""
	var guard := 0
	while not file.eof_reached() and guard < 32768:
		var b = int(file.get_8())
		if b == 0:
			raw += " "
		else:
			raw += char(b)
		guard += 1
	file.close()
	return raw

func _detect_weak_hardware_early() -> bool:
	var forced_device = OS.get_environment("ODISEA_DEVICE").to_lower()
	if _contains_any_hint(forced_device, EARLY_WEAK_DEVICE_HINTS):
		return true
	var explicit_hint = OS.get_environment(EARLY_WEAK_HINT_ENV).to_lower()
	if explicit_hint in ["1", "true", "yes", "on"]:
		return true
	if explicit_hint in ["0", "false", "no", "off"]:
		return false
	if not OS.get_name() in ["X11", "Linux", "Server"]:
		return false
	var device_fingerprint = (
		_read_text_file("/proc/cpuinfo")
		+ " "
		+ _read_text_file("/sys/firmware/devicetree/base/model")
		+ " "
		+ _read_text_file("/sys/class/graphics/fb0/device/modalias")
	).to_lower()
	var is_arm = "arm" in device_fingerprint or "aarch64" in device_fingerprint
	if not is_arm and not _contains_any_hint(device_fingerprint, EARLY_WEAK_DEVICE_HINTS):
		return false
	var mem_total_gb = _read_mem_total_gb()
	if mem_total_gb > 0.0 and mem_total_gb <= EARLY_WEAK_RAM_GB_CAP:
		return true
	return _contains_any_hint(device_fingerprint, EARLY_WEAK_DEVICE_HINTS)

func _apply_early_weak_hardware_hints() -> void:
	OS.set_environment(EARLY_WEAK_HINT_ENV, "1")
	OS.set_environment("ODISEA_GRAPHICS_PROFILE", "low")
	OS.set_environment("ODISEA_DISABLE_TERRACE_SCATTER", "1")
	OS.set_environment("ODISEA_THREAD_SCATTER_LAZY", "0")
	OS.set_environment("ODISEA_DECOR_RB_CULL", "0")
	OS.set_environment("ODISEA_DISABLE_SHADER_WARMUP", "1")
	print("[SessionManager] Early weak-hardware fast-path enabled.")

func _should_enable_mobile_web_safety(os_name: String, has_touchscreen: bool, override_value: String = "") -> bool:
	var normalized = override_value.to_lower().strip_edges()
	if normalized in ["1", "true", "yes", "on"]:
		return true
	if normalized in ["0", "false", "no", "off"]:
		return false
	return os_name == "HTML5" and has_touchscreen

func _apply_mobile_web_safety_hints() -> void:
	OS.set_environment(MOBILE_WEB_WEAK_ENV, "1")
	_set_env_default("ODISEA_GRAPHICS_PROFILE", MOBILE_WEB_GRAPHICS_PROFILE_DEFAULT)
	_set_env_default("ODISEA_DISABLE_TERRACE_SCATTER", "1")
	_set_env_default("ODISEA_THREAD_SCATTER_LAZY", "0")
	_set_env_default("ODISEA_DECOR_RB_CULL", "0")
	_set_env_default("ODISEA_DISABLE_SHADER_WARMUP", "1")
	_set_env_default("ODISEA_TARGET_FPS", MOBILE_WEB_TARGET_FPS_DEFAULT)
	_set_env_default(MOBILE_WEB_TRANSPARENCY_ENV, "1")
	_set_env_default(DISABLE_GLOW_ENV, "1")
	_set_env_default(DISABLE_FXAA_ENV, "1")
	print("[SessionManager] Mobile web safety mode enabled.")
	_apply_rendering_optimizations()

func _apply_rendering_optimizations() -> void:
	var disable_glow = OS.get_environment(DISABLE_GLOW_ENV) in ["1", "true", "yes", "on"]
	var disable_fxaa = OS.get_environment(DISABLE_FXAA_ENV) in ["1", "true", "yes", "on"]

	if disable_glow:
		var default_env_path = ProjectSettings.get_setting("rendering/environment/default_environment")
		if default_env_path != "":
			var env = load(default_env_path)
			if env is Environment:
				env.glow_enabled = false
				print("[SessionManager] Rendering: Glow DISABLED (forced)")

	if disable_fxaa:
		ProjectSettings.set_setting("rendering/quality/filters/use_fxaa", false)
		# Note: FXAA change might require restart to take full effect in some Godot versions,
		# but setting it early in _enter_tree/ready helps.

func _apply_mobile_web_render_scale() -> void:
	if not _mobile_web_safety_enabled:
		return
	var tree = get_tree()
	if not tree:
		return
	var root = tree.root
	if not root:
		return
	var base_size = OS.window_size
	if base_size.x <= 0.0 or base_size.y <= 0.0:
		base_size = Vector2(
			float(ProjectSettings.get_setting("display/window/size/width")),
			float(ProjectSettings.get_setting("display/window/size/height"))
		)
	var render_scale = _read_clamped_mobile_web_scale(OS.get_environment(MOBILE_WEB_RENDER_SCALE_ENV))
	if render_scale >= 0.999:
		return
	var target_size = _compute_mobile_web_render_size(base_size, render_scale)
	root.set_size_override_stretch(true)
	root.set_size_override(true, target_size)
	print("[SessionManager] Mobile web render scale %.2f -> %s" % [render_scale, target_size])

func _read_clamped_mobile_web_scale(raw_value: String) -> float:
	if raw_value.strip_edges() == "":
		return MOBILE_WEB_RENDER_SCALE_DEFAULT
	var parsed = float(raw_value)
	if parsed <= 0.0:
		return MOBILE_WEB_RENDER_SCALE_DEFAULT
	return clamp(parsed, MOBILE_WEB_RENDER_SCALE_MIN, MOBILE_WEB_RENDER_SCALE_MAX)

func _compute_mobile_web_render_size(base_size: Vector2, render_scale: float) -> Vector2:
	var safe_base = Vector2(max(1.0, base_size.x), max(1.0, base_size.y))
	var scaled = Vector2(
		floor(safe_base.x * render_scale),
		floor(safe_base.y * render_scale)
	)
	return Vector2(
		min(safe_base.x, max(MOBILE_WEB_MIN_RENDER_SIZE.x, scaled.x)),
		min(safe_base.y, max(MOBILE_WEB_MIN_RENDER_SIZE.y, scaled.y))
	)

func _set_env_default(name: String, value: String) -> void:
	if OS.get_environment(name).strip_edges() == "":
		OS.set_environment(name, value)

func _contains_any_hint(text: String, hints: Array) -> bool:
	for hint in hints:
		var needle = String(hint)
		if needle != "" and needle in text:
			return true
	return false

func _read_text_file(path: String) -> String:
	var file = File.new()
	if not file.file_exists(path):
		return ""
	if file.open(path, File.READ) != OK:
		return ""
	var data := ""
	var guard := 0
	var max_bytes := 65536
	while not file.eof_reached() and guard < max_bytes:
		var b = int(file.get_8())
		if b == 0:
			data += " "
		else:
			data += char(b)
		guard += 1
	file.close()
	return data

func _read_mem_total_gb() -> float:
	var meminfo = _read_text_file("/proc/meminfo")
	if meminfo == "":
		return 0.0
	for raw_line in meminfo.split("\n"):
		var line = String(raw_line).strip_edges()
		if not line.begins_with("MemTotal"):
			continue
		var parts = line.split(":")
		if parts.size() < 2:
			continue
		var kb = _parse_first_int(parts[1])
		if kb <= 0:
			return 0.0
		return float(kb) / 1024.0 / 1024.0
	return 0.0


const PROCESS_MEMORY_CACHE_INTERVAL_MS := 2000
var _cached_process_memory_mb: float = -1.0
var _last_process_memory_read_ms: int = 0
var _process_memory_available: bool = true

func read_process_memory_mb() -> float:
	var now_ms: int = OS.get_ticks_msec()
	if _cached_process_memory_mb >= 0.0 and (now_ms - _last_process_memory_read_ms) < PROCESS_MEMORY_CACHE_INTERVAL_MS:
		return _cached_process_memory_mb
	if not _process_memory_available:
		return -1.0

	_last_process_memory_read_ms = now_ms

	var os_name := OS.get_name()

	# Windows: use tasklist /FI to get process Working Set
	if os_name == "Windows" or os_name == "UWP":
		_cached_process_memory_mb = _read_windows_process_memory_mb(OS.get_process_id())
		return _cached_process_memory_mb

	# Linux/X11/Server: read /proc/self/status -> VmRSS
	if os_name in ["X11", "Linux", "Server"]:
		_cached_process_memory_mb = _read_linux_process_memory_mb()
		return _cached_process_memory_mb

	# macOS: use ps (forking a shell command is the simplest option)
	if os_name == "OSX":
		_cached_process_memory_mb = _read_macos_process_memory_mb(OS.get_process_id())
		return _cached_process_memory_mb

	_process_memory_available = false
	return -1.0


func _read_windows_process_memory_mb(pid: int) -> float:
	var output: Array = []
	var exit_code: int = OS.execute(
		"tasklist",
		["/FI", "PID eq " + str(pid), "/FO", "CSV", "/NH"],
		true,
		output,
		false
	)
	if exit_code != 0:
		return -1.0
	var raw_output: String = ""
	for line in output:
		raw_output += str(line) + "\n"
	# tasklist CSV output: "name.exe","pid","SessionName","Session#","Mem Usage"
	# We need the last field "Mem Usage" which looks like "123,456 K"
	var raw_lines: Array = raw_output.split("\n", false)
	for raw_line in raw_lines:
		var line: String = String(raw_line).strip_edges()
		if line == "":
			continue
		var fields: Array = line.split(",", false)
		if fields.size() < 5:
			continue
		# Last field: "123,456 K" or "123.456 K"
		var mem_str: String = String(fields[fields.size() - 1]).replace("\"", "").strip_edges()
		# Remove " K" suffix and thousand separators
		var kb_str: String = mem_str.replace(" K", "").replace("K", "").replace(".", "").replace(",", "").strip_edges()
		if kb_str.is_valid_integer():
			var kb: int = int(kb_str)
			return float(kb) / 1024.0
	return -1.0


func _read_linux_process_memory_mb() -> float:
	var status: String = _read_text_file("/proc/self/status")
	if status == "":
		return -1.0
	var raw_lines: Array = status.split("\n")
	for raw_line in raw_lines:
		var line: String = String(raw_line).strip_edges()
		if line.begins_with("VmRSS:"):
			var parts: Array = line.split(":")
			if parts.size() >= 2:
				var kb: int = _parse_first_int(parts[1])
				if kb > 0:
					return float(kb) / 1024.0
	return -1.0


func _read_macos_process_memory_mb(pid: int) -> float:
	var output: Array = []
	var exit_code: int = OS.execute(
		"ps",
		["-o", "rss=", "-p", str(pid)],
		true,
		output,
		false
	)
	if exit_code != 0:
		return -1.0
	var raw_output: String = ""
	for line in output:
		raw_output += str(line)
	var trimmed: String = String(raw_output).strip_edges()
	if trimmed.length() == 0:
		return -1.0
	# macOS ps -o rss= returns RSS in KB
	if trimmed.is_valid_integer():
		var kb: int = int(trimmed)
		if kb > 0:
			return float(kb) / 1024.0
	return -1.0


func _parse_first_int(raw: String) -> int:
	var digits := ""
	for i in range(raw.length()):
		var ch = raw.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	if digits == "":
		return 0
	return int(digits)

func _prepare_video_export_runtime() -> void:
	# Reduce first-frame stalls during export runs.
	OS.set_environment("ODISEA_DISABLE_SHADER_WARMUP", "1")
	# Replay export still needs audible buses internally so VideoExporter can capture/mux audio.
	OS.set_environment("ODISEA_MUTE_AUDIO_HEADLESS", "0")
	OS.set_environment("ODISEA_FORCE_MUTE_AUDIO", "0")


# Conexión automática de TeleportSystem con Player, Camera y zonas
func _connect_teleport_system():
	var teleport_system = get_node_or_null("TeleportSystem")
	if not teleport_system:
		return

	# Buscar PlayerControllerV2 (Pilot)
	_find_player()
	var player_node = player
	teleport_system.player_controller = player_node

	# Validar y reconectar InputProviderV2
	if is_instance_valid(player_node):
		var _unused_provider = player_node.get_node_or_null("InputProviderV2")

	# Buscar CameraRig dentro del player
	var camera_rig = player_node.get_node_or_null("CameraRig") if player_node else null
	if camera_rig:
		teleport_system.camera_controller = camera_rig
		# Force player camera to be the current one at startup
		if player_node.has_method("force_camera_current"):
			player_node.force_camera_current()
		if player_node.has_method("sync_camera_to_rig"):
			player_node.sync_camera_to_rig()

	# (Conexión de señales eliminada: ahora se realiza solo en _ready() de TeleportSystem)

	
	# Capturar el mouse solo si no estamos en un entorno de test.
	# Hacemos la llamada de forma segura para evitar un error de compilación
	# cuando GdUnit3 no está presente (ej. en una ejecución normal).
	var is_testing = false
	if Engine.has_singleton("GdUnit3"):
		is_testing = Engine.get_singleton("GdUnit3").is_test_suite()
	
	# Do not capture mouse in CLI mode, during tests, or in menú principal.
	var current_scene = get_tree().current_scene
	var is_menu = false
	if current_scene and current_scene.filename.find("Menu.tscn") != -1:
		is_menu = true
	if not is_testing and not is_cli_mode and not is_menu and not OS.has_feature("Server"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_tree_changed_for_replay(replay_path: String, export_video = false):
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	
	print("[SessionManager] _on_tree_changed_for_replay called! path=", replay_path, " export=", export_video)
	
	if export_video:
		var exporter = get_node_or_null("/root/VideoExporter")
		if exporter:
			print("[SessionManager] Calling start_export...")
			exporter.start_export(replay_path)
		else:
			printerr("[SessionManager] ERROR: VideoExporter node not found!")
			
	_find_player()
	if player:
		player.is_replay_mode = true
	load_and_play(replay_path)

func _on_tree_changed_for_script(script_path: String):
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	
	print("[SessionManager] Running script: ", script_path)
	var scripted_player = null
	var restore_replay_mode := false
	var restore_hardware_input := true
	
	var file = File.new()
	if not file.file_exists(script_path):
		printerr("Script not found: ", script_path)
		get_tree().quit(1)
		return
		
	file.open(script_path, File.READ)
	var content = file.get_as_text()
	file.close()
	
	# Load scene if LEVEL command exists (simple parse)
	for line in content.split("\n"):
		if line.begins_with("LEVEL "):
			var scene_path = line.replace("LEVEL ", "").strip_edges()
			var current_scene = get_tree().current_scene
			var needs_load = true
			if is_instance_valid(current_scene):
				if current_scene.filename == scene_path:
					needs_load = false

			if needs_load:
				print("Loading scene: ", scene_path)
				var scene = load(scene_path).instance()
				get_tree().root.add_child(scene)
				if is_instance_valid(current_scene):
					current_scene.queue_free()
				get_tree().current_scene = scene
				yield (get_tree(), "idle_frame")
				yield (get_tree(), "idle_frame")
			break

	_find_player()
	scripted_player = player
	if is_instance_valid(scripted_player):
		restore_replay_mode = scripted_player.is_replay_mode
		if "input_provider" in scripted_player and is_instance_valid(scripted_player.input_provider):
			restore_hardware_input = scripted_player.input_provider.hardware_input_enabled
			scripted_player.input_provider.hardware_input_enabled = false
		# Ensure OYS scripted mouse_delta can rotate camera even when mouse isn't captured.
		scripted_player.is_replay_mode = true
	
	var OYS_Interpreter = load("res://core_v2/systems/OYS_Interpreter.gd")
	var interpreter = OYS_Interpreter.new(self ) # Use SessionManager as host
	interpreter.parse(content)
	# Inject environment variables
	for k in _env_vars:
		interpreter.variables[k] = _env_vars[k]
		
	oys_interpreter = interpreter
	var run_state = interpreter.run()
	if run_state is GDScriptFunctionState:
		yield (run_state, "completed")
	
	if is_instance_valid(scripted_player):
		scripted_player.is_replay_mode = restore_replay_mode
		if "input_provider" in scripted_player and is_instance_valid(scripted_player.input_provider):
			scripted_player.input_provider.hardware_input_enabled = restore_hardware_input
	
	print("[SessionManager] Script finished.")
	get_tree().quit(0)

func _unhandled_input(event):
	# Gestionamos la captura y liberación del mouse de forma centralizada.
	# Esto evita que el PlayerController tenga que saber sobre el estado del UI.
	var is_testing = false
	if Engine.has_singleton("GdUnit3"):
		is_testing = Engine.get_singleton("GdUnit3").is_test_suite()

	# Do not manage mouse input in CLI mode, during tests, or in menú principal.
	var current_scene = get_tree().current_scene
	var is_menu = false
	if current_scene and current_scene.filename.find("Menu.tscn") != -1:
		is_menu = true
	if not is_testing and not is_cli_mode and not is_menu:
		if event.is_action_pressed("ui_cancel"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# Re-capturar al hacer click en la pantalla, solo si el cursor está visible.
		if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			if not OS.has_feature("Server"):
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


var _replay_frame := 0
var _total_replay_frames := 0

func _physics_process(_dt):
	var pm = get_node_or_null("/root/PerformanceMonitor")
	if pm and pm.has_method("profiling_start"): pm.profiling_start("SessionManager")

	# In RL lock-step runs, AnnaBridge drives the simulation and SessionManager
	# bookkeeping becomes pure overhead.
	if _rl_mode and _rl_bypass_session_manager and not is_recording and not is_replaying and not is_cli_mode:
		if pm and pm.has_method("profiling_end"): pm.profiling_end("SessionManager")
		return

	if is_recording or is_replaying:
		if not _is_player_candidate_valid(player):
			_find_player()
	else:
		_find_player()

	# Check for Skip Cinematic (Fast Forward)
	if is_instance_valid(oys_interpreter) and oys_interpreter.is_running:
		if Input.is_action_just_pressed("ui_accept") \
		or Input.is_action_just_pressed("jump") \
		or Input.is_action_just_pressed("interact") \
		or Input.is_action_just_pressed("ui_cancel"):
			# Only fast forward if player input is actually disabled (Cinematic Mode)
			# We check hardware_input_enabled on input_provider
			if is_instance_valid(player) and "input_provider" in player and player.input_provider:
				if not player.input_provider.hardware_input_enabled:
					# print("[SessionManager] Input detected during CINEMATIC. Requesting Fast Forward.")
					oys_interpreter.request_fast_forward()
					if is_instance_valid(CinematicManager) and CinematicManager.has_method("force_finish_transition"):
						CinematicManager.force_finish_transition()

	if Input.is_action_just_pressed("record-toggle"):
		if _live_export_launch_in_progress:
			_log_live_export_status("Export launch already in progress. Ignoring toggle.")
			return
		if not is_recording:
			start_recording()
			_log_live_export_status("Grabacion iniciada. Pulsa de nuevo para guardar y exportar.")
		else:
			call_deferred("_finalize_live_recording_with_video_export", false)

	if is_recording:
		# Consumir input desde el provider una única vez y usar ese mismo input
		var input_data = null
		if not _oys_input_override.empty():
			input_data = InputDataV2.new()
			input_data.from_dict(_oys_input_override)
		elif player and "input_provider" in player and player.input_provider:
			input_data = player.input_provider.get_input()
		else:
			input_data = null
		if input_data == null:
			input_data = InputDataV2.new()
		
		var frame_entry = {"input": input_data.to_dict()}

		if ghost_manager and ghost_manager.is_ghost_recording:
			var g_data = ghost_manager.capture_frame(player)
			if not g_data.empty():
				frame_entry["ghost_data"] = g_data
		
		# Guardar drift checkpoint si el player dejó de tocar un RigidBody
		if _pending_drift_checkpoint and is_instance_valid(player):
			frame_entry["drift_checkpoint"] = {
				"position": var2str(player.global_transform.origin)
			}
			_pending_drift_checkpoint = false
			# Programar un checkpoint "settle" 15 frames después
			_pending_settle_checkpoint_frame = _recording_frame + 15
		
		# Guardar checkpoint "settle" si llegamos al frame programado
		if _recording_frame == _pending_settle_checkpoint_frame and is_instance_valid(player):
			frame_entry["drift_checkpoint"] = {
				"position": var2str(player.global_transform.origin)
			}
			_pending_settle_checkpoint_frame = -1
		
		buffer.append(frame_entry)
		
		if is_instance_valid(player) and player.global_transform.origin.y > _peak_y:
			_peak_y = player.global_transform.origin.y
		# Step player: prefer SessionManager.player (set by TeleportSystem) to avoid
		# timing races with name-based lookup. Fall back to _find_player if needed.
		var pilot_node = null
		if is_instance_valid(player):
			pilot_node = player
		else:
			_find_player()
			if is_instance_valid(player):
				pilot_node = player

		# Apply Time Scale to our manual fixed step
		var step_dt = FIXED_DT * Engine.time_scale

		if pilot_node and pilot_node.has_method("step"):
			# Set external input for potential consumers but also step directly
			pilot_node.external_input = input_data
			pilot_node.external_input_provided = true
			pilot_node.step(step_dt, input_data)
			player = pilot_node # keep SessionManager.player in sync
		
		_recording_frame += 1
		
		# Step plataformas TAMBIÉN durante grabación para determinismo
		var sync_nodes = _get_replay_sync_nodes()
		for node in sync_nodes:
			if node != player and node.has_method("step"):
				node.step(step_dt)
		
		# Step CinematicManager if active
		if is_instance_valid(CinematicManager) and CinematicManager.has_method("is_active") and CinematicManager.is_active():
			CinematicManager.step(step_dt)
		
		# Sync total frames if we are also in "replaying" mode (for tests)
		if is_replaying:
			_total_replay_frames = _recording_frame

		# Clear override after use to allow OYS commands to accumulate fresh each frame
		_oys_input_override.clear()

	elif is_replaying:
		# Supresor de inercia mandatorio en Frame 0 para eliminar drift de preparación
		if _replay_frame == 0 and is_instance_valid(player) and "velocity" in player:
			player.velocity = Vector3.ZERO

		# Execute Logic Events (SET, MATH, ASSERT) for this frame (PRE-STEP)
		_check_events_for_frame(_replay_frame)

		if _replay_frame % 120 == 0 and _replay_frame >= 5:
			print("[SessionManager] Frame %d: pos=%s" % [_replay_frame, player.global_transform.origin])

		if is_instance_valid(player) and player.global_transform.origin.y > _peak_y:
			_peak_y = player.global_transform.origin.y

		# Obtener input primero para verificar si hay más inputs disponibles
		var input = null
		var provider = null
		if is_instance_valid(_replay_input_provider):
			provider = _replay_input_provider
		elif is_instance_valid(player) and "input_provider" in player and is_instance_valid(player.input_provider):
			provider = player.input_provider
		elif is_instance_valid(_active_input_provider):
			provider = _active_input_provider

		if is_instance_valid(provider):
			input = provider.get_input()
			_active_input_provider = provider
			if is_instance_valid(player) and "input_provider" in player and player.input_provider != provider:
				player.input_provider = provider
		
		if input == null:
			# Log once per second
			if _replay_frame % 60 == 0:
				print("[SessionManager] Frame %d: input is null. is_replaying=%s is_respawning=%s waiting_validation=%s" %
					[_replay_frame, is_replaying, is_respawning, _is_waiting_for_respawn_validation])

		# Intermittent guard: if frame 0 starts with a cleared replay provider,
		# rearm from the cached input buffer once before terminating playback.
		if input == null and _replay_frame == 0 and not _replay_input_buffer.empty():
			var rearm_provider = provider
			if not is_instance_valid(rearm_provider) and is_instance_valid(player):
				if player.has_method("ensure_input_provider"):
					player.ensure_input_provider()
				if "input_provider" in player and is_instance_valid(player.input_provider):
					rearm_provider = player.input_provider
			if is_instance_valid(rearm_provider) and rearm_provider.has_method("set_replay_data"):
				rearm_provider.set_replay_data(_replay_input_buffer)
				_replay_input_provider = rearm_provider
				_active_input_provider = rearm_provider
				if is_instance_valid(player) and "input_provider" in player and player.input_provider != rearm_provider:
					player.input_provider = rearm_provider
				input = rearm_provider.get_input()
		
		# Si no hay más inputs, terminar
		if input == null:
			if not _is_waiting_for_respawn_validation:
				print("[SessionManager] No more inputs, calling run_playback")
				run_playback()
			return

		# Step player con el input si es válido
		if is_instance_valid(player) and player.has_method("step"):
			player.step(FIXED_DT, input)
		
		# Step plataformas
		var sync_nodes = _get_replay_sync_nodes()
		for node in sync_nodes:
			if node != player and node.has_method("step"):
				node.step(FIXED_DT)
		
		# Step CinematicManager if active
		if is_instance_valid(CinematicManager) and CinematicManager.has_method("is_active") and CinematicManager.is_active():
			CinematicManager.step(FIXED_DT)

		_replay_frame += 1
		_total_replay_frames = _replay_frame
		
		# Proactiva validación de fin de buffer para evitar desfase de 1 frame en el reporte
		if is_instance_valid(_active_input_provider) and _active_input_provider.mode == _active_input_provider.Mode.REPLAY and _active_input_provider.playback_index >= _active_input_provider.playback_buffer.size():
			if not _is_waiting_for_respawn_validation:
				run_playback()
				
		# WATCHDOG: termina solo si el playback deja de avanzar, no por duración total del replay.
		_tick_replay_watchdog(_active_input_provider)
	
	else:
		# Normal gameplay (Not recording, Not replaying)
		if is_instance_valid(CinematicManager) and CinematicManager.has_method("is_active") and CinematicManager.is_active():
			CinematicManager.step(FIXED_DT)

		if ghost_manager and ghost_manager.is_playing_ghost:
			ghost_manager.step(FIXED_DT)

	# Capture explicit global physics step if live exporting or exporting!
	var __ext_exporter = get_node_or_null("/root/VideoExporter")
	if __ext_exporter != null and __ext_exporter.is_exporting:
		__ext_exporter.capture_frame(get_viewport())

	if _mobile_web_safety_enabled and Engine.get_idle_frames() % 60 == 0:
		_check_performance_mitigation()

	if pm and pm.has_method("profiling_end"): pm.profiling_end("SessionManager")

func _check_performance_mitigation() -> void:
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	if fps < 30.0 and not _performance_mitigation_active:
		_apply_dynamic_performance_mitigation()
	elif fps > 45.0 and _performance_mitigation_active:
		# Optionally restore settings if performance improves significantly?
		# For stability, maybe better to stay in mitigation mode.
		pass

func _apply_dynamic_performance_mitigation() -> void:
	_performance_mitigation_active = true
	print("[SessionManager] LOW FPS DETECTED (%.1f). Applying dynamic mitigation." % Performance.get_monitor(Performance.TIME_FPS))

	# 1. Reduce render scale further
	var current_scale = _read_clamped_mobile_web_scale(OS.get_environment(MOBILE_WEB_RENDER_SCALE_ENV))
	var mitigated_scale = current_scale * 0.8
	OS.set_environment(MOBILE_WEB_RENDER_SCALE_ENV, str(mitigated_scale))
	_apply_mobile_web_render_scale()

	# 2. Force Viewport Clear Mode to stabilize framebuffers
	# VisualServer.viewport_set_clear_mode(get_tree().root.get_viewport_rid(), VisualServer.CLEAR_MODE_ALWAYS)
	# In Godot 3.x, accessing root viewport directly:
	get_tree().root.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS

	# 3. Disable high-cost effects if not already
	var env_path = ProjectSettings.get_setting("rendering/environment/default_environment")
	if env_path != "":
		var env = load(env_path)
		if env is Environment:
			env.glow_enabled = false
			env.adjustment_enabled = false

func start_recording():
	if not is_instance_valid(player):
		printerr("SessionManager: No se puede iniciar la grabación, no se encontró al jugador.")
		return
	buffer.clear()
	_current_replay_data = {
		"events": {}
	}
	is_recording = true
	_active_input_provider = player.input_provider if is_instance_valid(player) else null
	_pending_drift_checkpoint = false
	_pending_settle_checkpoint_frame = -1
	_recording_frame = 0
	replay_meta = {
		"date": OS.get_datetime(),
		"unix_time": OS.get_unix_time(),
		"scene": get_tree().current_scene.filename,
		"world_snapshot": {}
	}

	# --- Resetear nodos replay_sync a estado inicial ---
	var sync_nodes = _get_replay_sync_nodes()
	# Desactivar _physics_process en plataformas durante grabación para usar step centralizado
	for node in sync_nodes:
		if node != player and node.has_method("step"):
			node.set_physics_process(false)
	
	# Marcar player como "controlado externamente" para evitar doble step
	if player:
		player.is_replay_mode = true # Usamos esta bandera para indicar control externo
		player.set_physics_process(false)

		# Supresor de inercia inicial para garantizar limpieza en el snapshot de grabación
		if "velocity" in player:
			player.velocity = Vector3.ZERO

		# Conectar señal de drift correction
		if player.has_signal("rigid_contact_ended") and not player.is_connected("rigid_contact_ended", self , "_on_rigid_contact_ended"):
			player.connect("rigid_contact_ended", self , "_on_rigid_contact_ended")
	
	# --- Capturar estado inicial del mundo (nodos en 'replay_sync') ---
	var world_start_state = _get_world_state_snapshot()
	replay_meta["world_start_state"] = world_start_state

	# Guardamos el estado inicial como primer elemento del buffer
	if is_instance_valid(player):
		buffer.append({"snapshot": player.get_full_snapshot()})
		var cam = player.get_node_or_null("CameraRig")
		print("GRAB_START\nrotation:", player.yaw, player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin if cam else "null")

func _get_world_state_snapshot() -> Dictionary:
	var snapshot = {}
	var sync_nodes = _get_replay_sync_nodes()
	for node in sync_nodes:
		if node.has_method("get_snapshot"):
			snapshot[node.get_path()] = node.get_snapshot()
		else:
			print("Warning: Node %s in group 'replay_sync' does not have get_snapshot() method." % node.name)
	# Include CinematicManager
	if is_instance_valid(CinematicManager) and CinematicManager.has_method("get_full_snapshot"):
		snapshot["CinematicManager"] = CinematicManager.get_full_snapshot()
	return snapshot

func _restore_world_state_snapshot(snapshot: Dictionary) -> void:
	for path in snapshot:
		if path == "CinematicManager":
			if is_instance_valid(CinematicManager) and CinematicManager.has_method("restore_snapshot"):
				CinematicManager.restore_snapshot(snapshot[path])
			continue
		var node = get_node(path)
		if node and node.has_method("restore_snapshot"):
			node.restore_snapshot(snapshot[path])

func _on_rigid_contact_ended():
	# Marcar que debemos guardar un checkpoint en el próximo frame del buffer
	_pending_drift_checkpoint = true

func stop_and_save_recording(force_path: String = "") -> String:
	if not is_instance_valid(player):
		printerr("SessionManager: No se puede detener la grabación, no se encontró al jugador.")
		return ""
	is_recording = false
	
	# Restaurar control normal del player
	if player:
		player.is_replay_mode = false
		player.set_physics_process(true)
	
	# Reactivar _physics_process en plataformas
	var sync_nodes = _get_replay_sync_nodes()
	for node in sync_nodes:
		if node != player and node.has_method("step"):
			node.set_physics_process(true)
	
	var cam = player.get_node_or_null("CameraRig")
	print("GRAB_END\nrotation:", player.yaw, player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)

	if ghost_manager and ghost_manager.is_ghost_recording:
		ghost_manager.save_recording_override(buffer, replay_meta)
		return ""
	else:
		var file_path = force_path
		if file_path == "":
			file_path = "user://replay_" + str(OS.get_unix_time()) + ".json"
		var file = File.new()
		file.open(file_path, File.WRITE)
		var out = {
			"meta": replay_meta,
			"buffer": buffer,
			"final_expected_state": player.get_full_snapshot()
		}
		if _current_replay_data.has("events"):
			out["events"] = _current_replay_data["events"]
		file.store_string(_json_print_normalized(out))
		file.close()
		print("💾 Replay guardado en: ", file_path)
		return file_path

var _playback_printed_start := false
var _playback_printed_end := false

func load_and_play(path: String):
	print("[SessionManager] load_and_play called with: ", path)
	_session_run_id += 1
	var my_run_id = _session_run_id
	if is_instance_valid(CinematicManager) and CinematicManager.has_method("reset"):
		CinematicManager.reset()
	if oys_interpreter:
		oys_interpreter.stop_requested = true
	is_replaying = false
	_is_waiting_for_respawn_validation = false
	_is_validating = false
	_reset_replay_watchdog()
	is_recording = false
	is_respawning = false
	_is_waiting_for_respawn_validation = false
	oys_assert_failed = false
	event_timeline = {}
	oys_variables = {}
	_replay_frame = 0
	_recording_frame = 0
	_total_replay_frames = 0
	_drift_validated = false
	_oys_input_override = {}
	final_expected_state = null
	_current_replay_data = {}
	_oys_requested_scene = ""
	_peak_y = -999.0
	_oys_actors = {}
	emit_signal("oys_registry_reset")
	_replay_input_provider = null
	_replay_input_buffer.clear()
	_node_cache.clear()
	_cleanup_session_spawned_nodes()
	Engine.time_scale = 1.0
	
	var _ts_reload = get_node_or_null("TeleportSystem")
	if _ts_reload and _ts_reload.has_method("reset"):
		_ts_reload.reset()
	
	_find_player()
	if is_instance_valid(player):
		if player.has_method("full_reset"):
			player.full_reset()
		if player.has_method("force_camera_current"):
			player.force_camera_current()
	
	_current_replay_path = path
	var ext = path.get_extension().to_lower()
	if ext == "oys" or ext == "json":
		is_replaying = true
	if ext == "oys":
		var file = File.new()
		if not file.file_exists(path):
			printerr("❌ Error: El archivo OYS no existe: ", path)
			is_replaying = false
			call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
			return
		file.open(path, File.READ)
		var script_content = file.get_as_text()
		file.close()
		if _script_requires_anna(script_content):
			_ensure_anna_bridge_enabled("REQUIRE_ANNA=1 in %s" % path)

		# Initialize for Live Script Execution (SETUP MODE)
		_recording_frame = 0
		_current_replay_data = {"buffer": [], "events": {}}
		buffer.clear()
		oys_variables = {}
		_monitored_signals = {}
		oys_assert_failed = false

		# Find/Load Level
		var scene_path = "res://core_v2/levels/TestScene_v2.tscn"
		var has_level_directive := false
		for line in script_content.split("\n"):
			var l = line.strip_edges()
			if l.begins_with("LEVEL"):
				has_level_directive = true
				var parts = l.split(" ", false)
				if parts.size() > 1:
					scene_path = String(parts[1]).strip_edges().replace("\"", "")
				break
		
		_oys_requested_scene = scene_path
		
		_find_player()
		if not is_manual_mode and player == null:
			if get_tree().current_scene == null or get_tree().current_scene.filename != scene_path:
				var packed = load(scene_path)
				if packed:
					var inst = packed.instance()
					get_tree().root.add_child(inst)
					get_tree().current_scene = inst
					yield (get_tree(), "idle_frame")
					if my_run_id != _session_run_id:
						return
					_find_player()
		
		# Enforce input inhibition for OYS live execution
		if is_instance_valid(player):
			player.is_replay_mode = true
			player.set_physics_process(false)
			if "input_provider" in player and is_instance_valid(player.input_provider):
				player.input_provider.hardware_input_enabled = false
		
		# NOW start the run
		is_recording = true
		
		if _should_snapshot:
			if not _current_replay_data.has("meta"): _current_replay_data["meta"] = {}
			_current_replay_data["meta"]["world_start_state"] = _get_world_state_snapshot()
		
		# Desactivar _physics_process en plataformas durante grabación
		var sync_nodes = _get_replay_sync_nodes()
		for node in sync_nodes:
			if node != player:
				node.set_physics_process(false)

		# Run Interpreter
		var OYS_Interpreter = load("res://core_v2/systems/OYS_Interpreter.gd")
		var host = get_tree().current_scene
		if not host:
			host = get_tree().root
		var interpreter = OYS_Interpreter.new(host)
		interpreter.parse(script_content)
		interpreter.connect("instruction_executed", self , "_on_oys_instruction_executed")
		interpreter.connect("instruction_completed", self , "_on_oys_instruction_completed")
		# Inject environment variables
		for k in _env_vars:
			interpreter.variables[k] = _env_vars[k]

		oys_interpreter = interpreter

		# Default initial state if player exists
		if player:
			# Check if script has a SET pos at the very beginning (simplistic)
			var has_initial_setup = false
			for inst in interpreter.instructions:
				if inst.command == "SET" and inst.get("var") == "pos":
					has_initial_setup = true
					break
				if inst.command in ["FW", "BW", "LEFT", "RIGHT", "WAIT", "JUMP"]:
					break # Stop looking after first time-consuming command
			
			if not has_initial_setup:
				# Preserve scene-authored spawn when script defines LEVEL.
				# Keep legacy origin fallback only for scripts without LEVEL.
				if has_level_directive:
					var ts = get_node_or_null("TeleportSystem")
					if ts and ts.has_method("force_initial_spawn"):
						ts.force_initial_spawn(player.global_transform)
				else:
					var start_tf = Transform(Basis.IDENTITY, Vector3(0, 0.5, 0))
					player.teleport_to(start_tf)
					var ts = get_node_or_null("TeleportSystem")
					if ts and ts.has_method("force_initial_spawn"):
						ts.force_initial_spawn(start_tf)
					# Record this as an event too so it's in the JSON
					_on_oys_instruction_executed({"command": "SET", "var": "pos", "value": "(0, 0.5, 0)"}, {})
			
			# Capture initial player state
			buffer.append({"snapshot": player.get_full_snapshot()})
			print("[SessionManager] OYS Initial Snapshot captured at pos=%s yaw=%.4f" % [player.global_transform.origin, player.yaw])

		# Start the run
		var run_state = interpreter.run()
		if run_state is GDScriptFunctionState:
			yield (run_state, "completed")
			if my_run_id != _session_run_id:
				return
		
		# CRITICAL: Stop recording BEFORE any yields to ensure consistent frame counts
		is_recording = false
		_total_replay_frames = _recording_frame
		_replay_frame = _recording_frame
		
		# Transfer recorded buffer to replay data for saving
		_current_replay_data["buffer"] = []
		for frame_input in buffer:
			_current_replay_data["buffer"].append(frame_input)
		
		# Wait for any pending respawn to complete to avoid race conditions during validation
		var timeout = 60 # Max 1 second
		while is_respawning and timeout > 0:
			yield (get_tree(), "physics_frame")
			if my_run_id != _session_run_id:
				return
			timeout -= 1
		
		if interpreter.test_failed:
			oys_assert_failed = true

		# Defensive snapshot save for OYS runs to avoid stale JSON if finish validation
		# is skipped by edge conditions in test harness.
		if _should_snapshot and is_instance_valid(player):
			var target_save_path = _current_replay_path.get_basename() + ".json"
			var final_data = _current_replay_data.duplicate(true)
			final_data["final_expected_state"] = player.get_full_snapshot()
			if not final_data.has("meta"):
				final_data["meta"] = {}
			if _oys_requested_scene != "":
				final_data["meta"]["scene_path"] = _oys_requested_scene
			if oys_interpreter:
				final_data["oys_variables"] = oys_interpreter.variables
				if oys_interpreter.variables.has("$drift_threshold"):
					final_data["meta"]["drift_threshold"] = float(oys_interpreter.variables["$drift_threshold"])
				elif oys_interpreter.variables.has("$sys_drift_threshold"):
					final_data["meta"]["drift_threshold"] = float(oys_interpreter.variables["$sys_drift_threshold"])
			if not final_data.has("buffer") and _current_replay_data.has("buffer"):
				final_data["buffer"] = _current_replay_data["buffer"]
			var sf = File.new()
			if sf.open(target_save_path, File.WRITE) == OK:
				sf.store_string(_json_print_normalized(final_data, "  "))
				sf.close()
		
		if my_run_id != _session_run_id:
			return
		_finish_and_validate()
		return

	# JSON tradicional
	var file = File.new()
	if not file.file_exists(path):
		printerr("❌ Error: El archivo de replay no existe: ", path)
		is_replaying = false
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return
	file.open(path, File.READ)
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if typeof(parsed.result) != TYPE_DICTIONARY:
		printerr("❌ Formato de replay inválido")
		is_replaying = false
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return
	var data = parsed.result
	var input_buffer_raw = data.get("buffer", [])
	var input_buffer = []
	for entry in input_buffer_raw:
		if typeof(entry) == TYPE_DICTIONARY:
			if entry.has("snapshot"):
				continue # Skip initial snapshot, it's used elsewhere
			
			if entry.has("input"):
				input_buffer.append(entry["input"])
			else:
				# It is a raw input dictionary (e.g. from OYS)
				input_buffer.append(entry)
	_current_replay_data = data
	
	# Fix: In headless mode, the engine boots into the default scene. We MUST change to the recorded scene.
	var meta = data.get("meta", {})
	var meta_scene = meta.get("scene", "")
	if meta_scene == "":
		meta_scene = meta.get("scene_path", "")
		
	if meta_scene != "":
		_oys_requested_scene = meta_scene
		if get_tree().current_scene == null or get_tree().current_scene.filename != meta_scene:
			var packed = load(meta_scene)
			if packed:
				if is_instance_valid(get_tree().current_scene):
					get_tree().current_scene.queue_free()
				var inst = packed.instance()
				get_tree().root.add_child(inst)
				get_tree().current_scene = inst
				yield (get_tree(), "idle_frame")
				if my_run_id != _session_run_id:
					return
				
				# CRITICAL: Since we just deleted the default scene and loaded a new one,
				# we must refresh autoload references to the new scene's nodes.
				if is_instance_valid(CinematicManager) and CinematicManager.has_method("reset"):
					CinematicManager.reset()
				var _ts = get_node_or_null("TeleportSystem")
				if _ts and _ts.has_method("reset"):
					_ts.reset()
				_find_player()
				if is_instance_valid(player):
					if player.has_method("full_reset"):
						player.full_reset()
					if player.has_method("force_camera_current"):
						player.force_camera_current()
	
	# Restore world state for JSON replays
	if data.has("world_snapshot"):
		_restore_world_state_snapshot(data.world_snapshot)
	# Migrate legacy setup if necessary (SETTERS/ASSERTS to EVENTS)
	if not data.has("events"):
		data["events"] = {}
		
		for s in data.get("setters", []):
			var f = int(s.get("frame", 0))
			if not data.events.has(f): data.events[f] = []
			var c = s.duplicate()
			c["command"] = "SET"
			c["var"] = s.get("property")
			data.events[f].append(c)
			
		for a in data.get("asserts", []):
			var f = int(a.get("frame", 0))
			if not data.events.has(f): data.events[f] = []
			var c = a.duplicate()
			c["command"] = "ASSERT"
			data.events[f].append(c)
	
	play_buffer(input_buffer, data)

func _log_to_oys_console(tag: String, text: String, color: String = ""):
	var root = get_tree().root
	if not root: return
	
	var console = root.get_node_or_null("OYS_Console")
	if console and console.has_method("add_log"):
		console.add_log(tag, text, color)

func _on_oys_instruction_executed(inst: Dictionary, _vars: Dictionary):
	if not is_recording: return
	
	var frame = _recording_frame
	if not _current_replay_data["events"].has(frame):
		_current_replay_data["events"][frame] = []
	
	var cmd = inst.get("command", "")
	match cmd:
		"ASSERT", "SET", "MATH", "PRINT", "CLS", "HINT", "HINT_CLEAR", "GET_NODES_IN_GROUP", "CALL", "LOAD_PROP", "SPAWN", "ANNA_ENABLE", "ANNA_DISABLE", "ANNA_SET_TARGET", "PLAY_ANIM", "SET_TIME_SCALE", "CINEMATIC_START", "CINEMATIC_STOP", "OPEN", "CHANGE_SCENE", "TELEPORT":
			_current_replay_data["events"][frame].append(OYS_Parser.serialize_instruction(inst))
		"ASSERT_SIGNAL":
			var start_evt = OYS_Parser.serialize_instruction(inst)
			start_evt["phase"] = "start"
			_current_replay_data["events"][frame].append(start_evt)

func record_event(inst: Dictionary):
	if not is_recording: return
	
	var frame = _recording_frame
	if not _current_replay_data.has("events"):
		_current_replay_data["events"] = {}
	if not _current_replay_data["events"].has(frame):
		_current_replay_data["events"][frame] = []
	
	_current_replay_data["events"][frame].append(inst)

func _on_oys_instruction_completed(inst: Dictionary, _vars: Dictionary):
	if not is_recording: return
	
	var cmd = inst.get("command", "")
	if cmd == "ASSERT_SIGNAL":
		var frame = _recording_frame
		if not _current_replay_data["events"].has(frame):
			_current_replay_data["events"][frame] = []
		
		var check_evt = OYS_Parser.serialize_instruction(inst)
		check_evt["phase"] = "check"
		_current_replay_data["events"][frame].append(check_evt)


func _apply_setters(setters: Array):
	# Legacy helper, kept for compatibility if called directly, but prefer generic event system
	for s in setters:
		var cmd = s.duplicate()
		cmd["command"] = "SET"
		cmd["var"] = s.get("property")
		_execute_event(cmd)

func _play_buffer_internal(input_buffer: Array, replay_data: Dictionary):
	# Internal call often used by tests directly
	_find_player()

	if not is_instance_valid(player):
		printerr("❌ SessionManager: Player no encontrado para iniciar replay.")
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return

	var meta = replay_data.get("meta", {})

	# Restaurar estado inicial del mundo ANTES del player
	if meta.has("world_start_state"):
		var world_start_state = meta["world_start_state"]
		for path in world_start_state.keys():
			var node = get_tree().get_root().get_node_or_null(path)
			if node and node.has_method("restore_snapshot"):
				node.restore_snapshot(world_start_state[path])

	# Restaurar snapshot inicial del player si existe
	var replay_buffer = replay_data.get("buffer", [])
	if replay_buffer.size() > 0 and replay_buffer[0].has("snapshot"):
		player.restore_snapshot(replay_buffer[0]["snapshot"])

	# Desactivar _physics_process en plataformas
	var sync_nodes = _get_replay_sync_nodes()
	for node in sync_nodes:
		if node != player:
			node.set_physics_process(false)

	player.is_replay_mode = true
	player.set_physics_process(false)
	if player.has_method("ensure_input_provider"):
		player.ensure_input_provider()
	if not ("input_provider" in player) or not is_instance_valid(player.input_provider):
		printerr("❌ SessionManager: Player sin input_provider válido para replay interno.")
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return
	player.input_provider.set_replay_data(input_buffer)
	_active_input_provider = player.input_provider
	_replay_input_provider = player.input_provider
	_replay_input_buffer = input_buffer.duplicate(true)
	_reset_replay_watchdog(player.input_provider)
	if "velocity" in player:
		player.velocity = Vector3.ZERO

	var _b_size = input_buffer.size()
	# print("[SessionManager] Starting _play_buffer_internal with %d frames" % b_size)

	# Initialize Event Runtime
	event_timeline = {}
	oys_variables = {}
	
	var raw_events = replay_data.get("events", {})
	# Ensure integer keys
	for f in raw_events:
		event_timeline[int(f)] = raw_events[f]

	_pending_asserts = replay_data.get("asserts", [])
	_pending_setters = replay_data.get("setters", [])
	_peak_y = player.global_transform.origin.y if is_instance_valid(player) else 0.0
	final_expected_state = replay_data.get("final_expected_state", null)

	_drift_validated = false
	_replay_frame = 0
	_total_replay_frames = input_buffer.size()
	is_replaying = true
	
	print("▶️ Reproduciendo replay desde buffer con %d frames..." % _total_replay_frames)

func play_buffer(input_buffer: Array, replay_data: Dictionary):
	_find_player()

	if not is_instance_valid(player):
		printerr("❌ SessionManager: Player no encontrado para iniciar replay.")
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return

	var meta = replay_data.get("meta", {})

	# Restaurar estado inicial del mundo ANTES del player
	if meta.has("world_start_state"):
		var world_start_state = meta["world_start_state"]
		for path in world_start_state.keys():
			var node = get_tree().get_root().get_node_or_null(path)
			if node and node.has_method("restore_snapshot"):
				node.restore_snapshot(world_start_state[path])

	# Restaurar snapshot inicial del player si existe
	var replay_buffer = replay_data.get("buffer", [])
	if replay_buffer.size() > 0 and replay_buffer[0].has("snapshot"):
		player.restore_snapshot(replay_buffer[0]["snapshot"])

	# Desactivar _physics_process en plataformas
	var sync_nodes = _get_replay_sync_nodes()
	for node in sync_nodes:
		if node != player:
			node.set_physics_process(false)

	player.is_replay_mode = true
	player.set_physics_process(false)
	if player.has_method("ensure_input_provider"):
		player.ensure_input_provider()
	if not ("input_provider" in player) or not is_instance_valid(player.input_provider):
		printerr("❌ SessionManager: Player sin input_provider válido para replay.")
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return
	player.input_provider.set_replay_data(input_buffer)
	_active_input_provider = player.input_provider
	_replay_input_provider = player.input_provider
	_replay_input_buffer = input_buffer.duplicate(true)
	_reset_replay_watchdog(player.input_provider)

	# Initialize Event Runtime
	event_timeline = {}
	oys_variables = {}
	_monitored_signals = {}
	
	var raw_events = replay_data.get("events", {})
	# Ensure integer keys
	for f in raw_events:
		event_timeline[int(f)] = raw_events[f]

	_peak_y = player.global_transform.origin.y if is_instance_valid(player) else 0.0
	final_expected_state = replay_data.get("final_expected_state", null)

	_drift_validated = false
	_replay_frame = 0
	is_replaying = true
	
	print("▶️ Reproduciendo replay desde buffer...")


func _finish_and_validate():
	if _is_validating or _drift_validated:
		return
	_is_validating = true
	var run_id = _session_run_id
	print("[SessionManager] Starting _finish_and_validate. run_id=", run_id)
	
	if is_respawning:
		# MANTENER is_replaying = true para que el test runner no termine prematuramente
		# y para que los nuevos pilotos sepan que siguen en replay mode.
		_is_waiting_for_respawn_validation = true
		var timeout_frames = 300 # ~5 segundos a 60fps
		while is_respawning and timeout_frames > 0:
			yield (get_tree(), "physics_frame")
			timeout_frames -= 1
			
			# Si otro test empezó, abortamos esta validación silenciosamente
			if run_id != _session_run_id:
				print("[SessionManager] _finish_and_validate aborted: run_id changed")
				return
			
			if timeout_frames <= 0:
				printerr("[SessionManager] WARNING: Timeout esperando a que is_respawning se limpie en _finish_and_validate!")
				is_respawning = false # Forzar limpieza para permitir que el test termine

	_is_waiting_for_respawn_validation = false
	_drift_validated = true
	is_replaying = false
	is_recording = false
	_reset_replay_watchdog()
	Engine.time_scale = 1.0
	
	if is_instance_valid(CinematicManager) and CinematicManager.has_method("reset"):
		CinematicManager.reset()
		
	_replay_input_provider = null
	_replay_input_buffer.clear()
	
	_find_player()
	if is_instance_valid(player):
		player.is_replay_mode = false
		player.set_physics_process(true)
	
	_is_validating = false
	print("[SessionManager] _finish_and_validate COMPLETED. is_replaying set to false.")
	
	# Una última comprobación de aserciones que puedan haber quedado en el último frame
	# Prevenir doble ejecución de eventos en el frame final
	# _check_events_for_frame(_replay_frame)
	
	var success = true
	var dist = -1.0
	var frames = _total_replay_frames

	print("[SessionManager] Peak Y reached during replay: %.4f" % _peak_y)
	
	if oys_assert_failed:
		success = false
		printerr("❌ REPLAY VALIDATION FAILED: OYS Assertions failed during execution.")

	# 1. Imprimir estado final
	if is_instance_valid(player):
		var cam = player.get_node_or_null("CameraRig") if is_instance_valid(player) else null
		var cam_pos = cam.global_transform.origin if is_instance_valid(cam) else "null"
		print("[SessionManager] Replay snapshot: rotation=(%s,%s) pos=%s cam=%s" % [str(player.yaw), str(player.pitch), str(player.global_transform.origin), str(cam_pos)])

	# 2. Validar drift
	if final_expected_state == null:
		# No-op: avoid noisy warning logs when expected state is intentionally absent.
		pass
	else:
		var exp_pos_arr = final_expected_state.get("position", null)
		if exp_pos_arr == null or typeof(exp_pos_arr) != TYPE_ARRAY:
			print("⚠️ final_expected_state inválido (sin posición)")
		else:
			var expected_pos = Vector3(exp_pos_arr[0], exp_pos_arr[1], exp_pos_arr[2])
			var current_pos = player.global_transform.origin if is_instance_valid(player) else Vector3()
			dist = current_pos.distance_to(expected_pos)
			var expected_yaw = final_expected_state.get("yaw", 0.0)
			var expected_pitch = final_expected_state.get("pitch", 0.0)
			var yaw_diff = abs(player.yaw - expected_yaw) if is_instance_valid(player) else 0.0
			var pitch_diff = abs(player.pitch - expected_pitch) if is_instance_valid(player) else 0.0
			
			print("DRIFT_CHECK: dist=%.6f, expected=%s, actual=%s" % [dist, expected_pos, current_pos])
			print("DRIFT_CHECK: yaw_diff=%.6f, pitch_diff=%.6f" % [yaw_diff, pitch_diff])
			
			var pos_threshold = _get_runtime_drift_threshold()
			var ang_threshold = 0.01
			if dist > pos_threshold:
				printerr("❌ DRIFT ERROR: Positional drift = %.6f > %.6f" % [dist, pos_threshold])
				success = false
			else:
				print("✅ Positional drift dentro del umbral")
			
			if yaw_diff > ang_threshold or pitch_diff > ang_threshold:
				printerr("❌ ROTATION DRIFT: yaw=%.6f, pitch=%.6f > %.6f" % [yaw_diff, pitch_diff, ang_threshold])
				success = false
			else:
				print("✅ Rotational drift dentro del umbral")
	
	# 2.5 Snapshot override if requested
	if _should_snapshot and player:
		var target_save_path = _current_replay_path
		if _current_replay_path.ends_with(".oys"):
			target_save_path = _current_replay_path.get_basename() + ".json"
		
		print("[SessionManager] --snapshot focus: Saving/Updating final_expected_state in ", target_save_path)
		
		var final_data = _current_replay_data.duplicate(true)
		if is_instance_valid(player):
			final_data["final_expected_state"] = player.get_full_snapshot()
		else:
			printerr("[SessionManager] ERROR: player instance is invalid/freed when saving final_expected_state!")
			return
		if not final_data.has("meta"):
			final_data["meta"] = {}
		if _oys_requested_scene != "":
			final_data["meta"]["scene_path"] = _oys_requested_scene
		
		if oys_interpreter:
			final_data["oys_variables"] = oys_interpreter.variables
			if oys_interpreter.variables.has("$drift_threshold"):
				final_data["meta"]["drift_threshold"] = float(oys_interpreter.variables["$drift_threshold"])
			elif oys_interpreter.variables.has("$sys_drift_threshold"):
				final_data["meta"]["drift_threshold"] = float(oys_interpreter.variables["$sys_drift_threshold"])
		
		# Ensure buffer is present if it's missing (e.g. from OYS data sometimes needing structure adjustment)
		if not final_data.has("buffer") and _current_replay_data.has("buffer"):
			final_data["buffer"] = _current_replay_data["buffer"]
		
		# If we found a JSON with different structure (e.g. nested buffer with 'input' keys), 
		# we already have it in _current_replay_data because of how load_and_play works.
		
		var f = File.new()
		if f.open(target_save_path, File.WRITE) == OK:
			f.store_string(_json_print_normalized(final_data, "  "))
			f.close()
			print("✅ Snapshot saved/updated successfully in ", target_save_path)
		else:
			printerr("❌ Could not open file for writing: ", target_save_path)

	# Emit signal for external listeners/tests regardless of snapshot mode.
	# Final defensive cleanup: make sure no session SPAWN nodes bleed into next run.
	_cleanup_session_spawned_nodes()
	print("[SessionManager] EMITTING replay_finished: ", success, ", ", dist, ", ", frames)
	emit_signal("replay_finished", success, dist, frames)

	# 3. Salir si estamos en modo CLI
	if is_cli_mode:
		var exporter = get_node_or_null("/root/VideoExporter")
		if exporter and exporter.is_exporting:
			print("[SessionManager] Deferring CLI exit to VideoExporter")
		else:
			print("[SessionManager] Exiting CLI mode")
			get_tree().quit(0 if success else 1)

func _check_events_for_frame(frame_idx: int):
	if event_timeline.has(frame_idx):
		var commands = event_timeline[frame_idx]
		for cmd in commands:
			_execute_event(cmd)

func _get_runtime_drift_threshold() -> float:
	var fallback = 0.01
	if typeof(_current_replay_data) != TYPE_DICTIONARY:
		return fallback
	
	if _current_replay_data.has("drift_threshold"):
		var top = float(_current_replay_data.get("drift_threshold", fallback))
		if top > 0.0:
			return top
	
	var meta = _current_replay_data.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY and meta.has("drift_threshold"):
		var meta_v = float(meta.get("drift_threshold", fallback))
		if meta_v > 0.0:
			return meta_v
	
	var vars = _current_replay_data.get("oys_variables", {})
	if typeof(vars) == TYPE_DICTIONARY:
		if vars.has("$drift_threshold"):
			var v = float(vars.get("$drift_threshold", fallback))
			if v > 0.0:
				return v
		if vars.has("$sys_drift_threshold"):
			var sv = float(vars.get("$sys_drift_threshold", fallback))
			if sv > 0.0:
				return sv
	
	return fallback

func _execute_event(cmd: Dictionary):
	var type = cmd.get("command", "")
	match type:
		"SET":
			_handle_set_command(cmd)
		"MATH":
			_handle_math_command(cmd)
		"ASSERT":
			_handle_assert_command(cmd)
		"PRINT":
			var msg = cmd.get("message", "")
			# Simple variable substitution
			msg = _resolve_variables_in_string(msg)
			print("[OYS] ", msg)
			_show_subtitle(msg, Color.white, 2.5)
		"CLS":
			_clear_subtitles(false)
		"HINT":
			var hint_msg = _resolve_variables_in_string(cmd.get("message", ""))
			_show_player_hint(hint_msg, float(cmd.get("duration", 30.0)))
		"HINT_CLEAR":
			_clear_player_hint()
		"ASSERT_SIGNAL":
			_handle_assert_signal(cmd)
		"GET_NODES_IN_GROUP":
			_handle_get_nodes_in_group(cmd)
		"CALL":
			_handle_call_command(cmd)
		"LOAD_PROP":
			var path = cmd.get("path", "")
			if path != "":
				load_prop(path)
			else:
				printerr("[SessionManager] Replay Error: LOAD_PROP with empty path")
		"SPAWN":
			_handle_spawn_command(cmd)
		"ANNA_ENABLE", "ANNA_DISABLE", "ANNA_SET_TARGET":
			_handle_anna_command(cmd)
		"PLAY_ANIM":
			_handle_play_anim(cmd)
		"PLAY_SOUND":
			_handle_play_sound_event(cmd)
		"SET_TIME_SCALE":
			Engine.time_scale = float(cmd.get("value", 1.0))
		"CINEMATIC":
			_set_player_hints_interactive(false)
			_set_script_cinematic_input_block(true)
		"INTERACTIVE":
			_set_script_cinematic_input_block(false)
			_set_player_hints_interactive(true)
		"CINEMATIC_START":
			_set_player_hints_interactive(false)
			_handle_cinematic_start_event(cmd)
		"CINEMATIC_STOP":
			_handle_cinematic_stop_event()
			_set_player_hints_interactive(true)
		"VCAMERA":
			_handle_vcamera_activate_event(cmd)
		"VCAMERA_BLEND":
			_handle_vcamera_blend_event(cmd)
		"VCAMERA_RETURN":
			_handle_vcamera_return_event(cmd)
		"VCAMERA_SHAKE", "CAMERA_SHAKE":
			_handle_camera_shake_event(cmd)
		"CAMERA_SHAKE_STOP":
			_stop_camera_shake_event()
		"LATCH_BASIS":
			var b_arr = cmd.get("basis")
			if b_arr and b_arr.size() == 3:
				var bx = Vector3(b_arr[0][0], b_arr[0][1], b_arr[0][2])
				var by = Vector3(b_arr[1][0], b_arr[1][1], b_arr[1][2])
				var bz = Vector3(b_arr[2][0], b_arr[2][1], b_arr[2][2])
				if is_instance_valid(CinematicManager):
					CinematicManager.latched_camera_basis = Basis(bx, by, bz)
					CinematicManager.latched_control_mode = int(cmd.get("mode", 0))
					CinematicManager.latch_active = true
					print("[SessionManager] RESTORED LATCHED BASIS from Event")

func _set_script_cinematic_input_block(enabled: bool) -> void:
	var screen_fx = get_node_or_null("/root/ScreenEffectsManager")
	if screen_fx:
		if enabled and screen_fx.has_method("show_script_cinematic_bars"):
			screen_fx.show_script_cinematic_bars()
		elif not enabled and screen_fx.has_method("hide_script_cinematic_bars"):
			screen_fx.hide_script_cinematic_bars()
	_find_player()
	if is_instance_valid(player) and "input_provider" in player and is_instance_valid(player.input_provider):
		player.input_provider.hardware_input_enabled = not enabled

func _handle_cinematic_start_event(cmd: Dictionary) -> void:
	_set_script_cinematic_input_block(true)
	var manager = get_node_or_null("/root/CinematicManager")
	if manager and manager.has_method("activate_rig"):
		var rig_id = String(cmd.get("rig_id", ""))
		var mode_str = String(cmd.get("mode", "FREE")).to_upper()
		var mode = 0
		match mode_str:
			"SIDESCROLL":
				mode = 1
			"LOCKED_VIEW":
				mode = 2
			"FIXED_AXIS":
				mode = 3
			_:
				mode = 0
		manager.activate_rig(rig_id, mode)

func _handle_cinematic_stop_event() -> void:
	_set_script_cinematic_input_block(false)
	var manager = get_node_or_null("/root/CinematicManager")
	if manager and manager.has_method("deactivate_rig"):
		manager.deactivate_rig()

func _find_vcamera_for_event(name: String):
	var manager = get_node_or_null("/root/CinematicManager")
	if not manager or not manager.has_method("find_vcamera"):
		return null
	var vcam_name = name.strip_edges().replace("\"", "")
	if vcam_name == "":
		return null
	return manager.find_vcamera(vcam_name)

func _handle_vcamera_activate_event(cmd: Dictionary) -> void:
	var manager = get_node_or_null("/root/CinematicManager")
	if not manager:
		return
	var vcam = _find_vcamera_for_event(String(cmd.get("name", "")))
	if not is_instance_valid(vcam):
		printerr("[SessionManager] Replay VCAMERA failed: camera not found: ", cmd.get("name", ""))
		return
	var duration = float(cmd.get("duration", 1.0))
	var ease_type = float(cmd.get("ease", -2.0))
	manager.activate_vcamera(vcam, duration, ease_type)

func _handle_vcamera_blend_event(cmd: Dictionary) -> void:
	var manager = get_node_or_null("/root/CinematicManager")
	if not manager or not manager.has_method("blend_to_vcamera"):
		return
	var vcam = _find_vcamera_for_event(String(cmd.get("name", "")))
	if not is_instance_valid(vcam):
		printerr("[SessionManager] Replay VCAMERA_BLEND failed: camera not found: ", cmd.get("name", ""))
		return
	var duration = float(cmd.get("duration", 1.0))
	manager.blend_to_vcamera(vcam, duration)

func _handle_vcamera_return_event(cmd: Dictionary) -> void:
	var manager = get_node_or_null("/root/CinematicManager")
	if manager and manager.has_method("deactivate_vcamera"):
		manager.deactivate_vcamera(float(cmd.get("duration", 1.0)))

func _handle_camera_shake_event(cmd: Dictionary) -> void:
	var manager = get_node_or_null("/root/CinematicManager")
	if not manager or not manager.has_method("trigger_camera_shake"):
		return
	var duration = float(cmd.get("duration", 0.35))
	var frequency = float(cmd.get("frequency", 28.0))
	if cmd.has("translation") or cmd.has("rotation"):
		var trans = _parse_vector3(String(cmd.get("translation", "(0,0,0)")))
		var rot = _parse_vector3(String(cmd.get("rotation", "(0,0,0)")))
		var intensity = float(cmd.get("intensity", 1.0))
		var amplitude = max(abs(trans.x), max(abs(trans.y), abs(trans.z))) * intensity
		var roll_deg = max(abs(rot.x), max(abs(rot.y), abs(rot.z))) * intensity
		manager.trigger_camera_shake(duration, amplitude, frequency, roll_deg)
		return
	manager.trigger_camera_shake(
		duration,
		float(cmd.get("amplitude", 0.08)),
		frequency,
		float(cmd.get("roll", 1.0))
	)

func _stop_camera_shake_event() -> void:
	var manager = get_node_or_null("/root/CinematicManager")
	if manager and manager.has_method("stop_camera_shake"):
		manager.stop_camera_shake()

func _handle_play_sound_event(cmd: Dictionary) -> void:
	var sfx_target = String(cmd.get("sfx", "")).strip_edges()
	if sfx_target != "":
		var node = _find_node_recursive(sfx_target)
		if node and is_instance_valid(node) and node.has_method("play"):
			node.play()
			return

	var audio = get_node_or_null("/root/AudioManager")
	if not audio or not audio.has_method("play_sound"):
		return
	var sound_name = String(cmd.get("sound", ""))
	if sound_name == "":
		sound_name = sfx_target
	if sound_name == "":
		return
	audio.play_sound(sound_name, Vector3.ZERO)

func record_custom_event(cmd_name: String, data: Dictionary):
	if not is_recording: return
	var frame = _recording_frame
	if not _current_replay_data["events"].has(frame):
		_current_replay_data["events"][frame] = []
	
	var evt = data.duplicate(true)
	evt["command"] = cmd_name
	_current_replay_data["events"][frame].append(evt)
	print("[SessionManager] RECORDED Custom Event: ", cmd_name, " at frame ", frame)

func _resolve_variables_in_string(msg: String) -> String:
	if "$" in msg:
		for key in oys_variables:
			var placeholder = key # e.g. "$start_x"
			if placeholder in msg:
				msg = msg.replace(placeholder, str(oys_variables[key]))
	return msg

func _show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
	var subtitles = get_node_or_null("/root/SubtitlesOverlayManager")
	if subtitles and subtitles.has_method("show_subtitle"):
		subtitles.show_subtitle(text, color, duration)

func _clear_subtitles(immediate: bool = false) -> void:
	var subtitles = get_node_or_null("/root/SubtitlesOverlayManager")
	if subtitles and subtitles.has_method("clear_subtitles"):
		subtitles.clear_subtitles(immediate)

func _show_player_hint(text: String, duration: float = 30.0) -> void:
	var hints = get_node_or_null("/root/PlayerHintManager")
	if hints and hints.has_method("show_manual_hint"):
		hints.show_manual_hint(text, duration)

func _clear_player_hint() -> void:
	var hints = get_node_or_null("/root/PlayerHintManager")
	if hints and hints.has_method("clear_manual_hint"):
		hints.clear_manual_hint()

func _set_player_hints_interactive(enabled: bool) -> void:
	var hints = get_node_or_null("/root/PlayerHintManager")
	if hints and hints.has_method("set_interactive"):
		hints.set_interactive(enabled)

func _handle_assert_signal(cmd: Dictionary):
	var phase = cmd.get("phase", "start")
	var signal_name = cmd.get("signal", "")
	var target_name = cmd.get("path", "")
	
	if signal_name == "": return

	var key = target_name + "::" + signal_name

	if phase == "start":
		# Reset state
		_monitored_signals[key] = false
		
		# Find target node
		var target_node = _find_node_recursive(target_name)
		
		if target_node:
			if not target_node.is_connected(signal_name, self , "_on_monitored_signal"):
				target_node.connect(signal_name, self , "_on_monitored_signal", [key])
			print("[OYS] Listening for signal '%s' on %s" % [signal_name, target_node.name])
		else:
			printerr("[OYS] ASSERT_SIGNAL ERROR: Could not find node '%s'" % target_name)
			
	elif phase == "check":
		if _monitored_signals.get(key, false):
			var msg = "Signal '%s' was emitted." % signal_name
			print("[OYS] ✅ ASSERT_SIGNAL SUCCESS: ", msg)
			_log_to_oys_console("ASSERT_OK", msg)
			_show_subtitle("ASSERT OK: %s" % msg, Color(0.35, 1.0, 0.35), 2.5)
		else:
			var fail_msg = "'%s' was NOT emitted on '%s' within timeout." % [signal_name, target_name]
			printerr("❌ [OYS] ASSERT_SIGNAL FAILED: ", fail_msg)
			_log_to_oys_console("ASSERT_FAIL", "ASSERT_SIGNAL FAILED: " + fail_msg)
			_show_subtitle("ASSERT FAIL: " + fail_msg, Color(1.0, 0.35, 0.35), 3.0)
			oys_assert_failed = true

func _handle_get_nodes_in_group(cmd: Dictionary):
	var group = cmd.get("group", "")
	var target_var = cmd.get("target", "")
	if group == "": return
	
	var nodes = get_tree().get_nodes_in_group(group)
	var count = nodes.size()
	
	if target_var != "":
		oys_variables[target_var] = count
		print("[OYS] GET_NODES_IN_GROUP '%s' -> %d (saved to %s)" % [group, count, target_var])

func _on_monitored_signal(p1 = null, p2 = null, p3 = null, p4 = null, p5 = null):
	var args = [p1, p2, p3, p4, p5]
	var key = ""
	# Find the LAST non-null argument which is likely our bound key
	for i in range(4, -1, -1):
		if args[i] != null:
			if typeof(args[i]) == TYPE_STRING and "::" in args[i]:
				key = args[i]
				break
	
	if key != "":
		_monitored_signals[key] = true


func _handle_set_command(cmd: Dictionary):
	var target_var = cmd.get("var", "")
	var value = null
	
	# Determine value (Literal, Variable, or Function Call)
	if cmd.has("func"):
		var func_name = cmd.get("func")
		var args = cmd.get("args", [])
		value = _execute_helper_func(func_name, args)
	elif cmd.has("value"):
		value = _resolve_value(cmd.get("value"))
	
	if target_var.begins_with("$"):
		# Runtime variable
		oys_variables[target_var] = value
		# print("SET VAR ", target_var, " = ", value)
	else:
		# Player property (Legacy/Standard property set)
		_set_player_prop(target_var, value)

func _get_camera_relative_axis_sm(axis: String) -> float:
	if not is_instance_valid(player) or not (player is Spatial):
		return 0.0
	var rig := player.get_node_or_null("CameraRig") as Spatial
	if not is_instance_valid(rig):
		return 0.0
	# Find camera via preferred paths
	var cam: Camera = null
	for path in ["CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera", "CameraRig/Yaw/Pitch/SpringArm/Camera", "CameraRig/SpringArm/Camera", "CameraRig/Camera"]:
		var c = player.get_node_or_null(path)
		if c and c is Camera:
			cam = c as Camera
			break
	if not is_instance_valid(cam):
		return 0.0
	var rel: Vector3 = cam.global_transform.origin - player.global_transform.origin
	match axis:
		"right": return rel.dot(rig.global_transform.basis.x.normalized())
		"up": return rel.dot(player.global_transform.basis.y.normalized())
		"back": return rel.dot(rig.global_transform.basis.z.normalized())
		"distance": return rel.length()
	return 0.0

func _evaluate_expr_tokens_sm(tokens: Array):
	if tokens.size() == 0:
		return 0.0
	var result := float(_resolve_value(tokens[0]))
	var i := 1
	while i + 1 < tokens.size():
		var arith_op: String = str(tokens[i])
		var next_val := float(_resolve_value(tokens[i + 1]))
		match arith_op:
			"+": result += next_val
			"-": result -= next_val
			"*": result *= next_val
			"/":
				if next_val != 0.0:
					result /= next_val
		i += 2
	return result

func _execute_helper_func(func_name: String, args: Array):
	match func_name:
		"CAMERA_REL_RIGHT":
			return _get_camera_relative_axis_sm("right")
		"CAMERA_REL_UP":
			return _get_camera_relative_axis_sm("up")
		"CAMERA_REL_BACK":
			return _get_camera_relative_axis_sm("back")
		"CAMERA_REL_DISTANCE":
			return _get_camera_relative_axis_sm("distance")
		"GET_NODE_POS_X":
			var node_name = args[0] if args.size() > 0 else ""
			var node = _find_node_recursive(node_name)
			if node: return node.global_transform.origin.x
			return 0.0
		"GET_NODE_POS_Y":
			var node_name = args[0] if args.size() > 0 else ""
			var node = _find_node_recursive(node_name)
			if node: return node.global_transform.origin.y
			return 0.0
		"GET_NODE_POS_Z":
			var node_name = args[0] if args.size() > 0 else ""
			var node = _find_node_recursive(node_name)
			if node: return node.global_transform.origin.z
			return 0.0
		"GET_NODE_ROT_X":
			var node_name = args[0] if args.size() > 0 else ""
			var node = _find_node_recursive(node_name)
			if node: return rad2deg(node.global_transform.basis.get_euler().x)
			return 0.0
		"GET_NODE_ROT_Y":
			var node_name = args[0] if args.size() > 0 else ""
			var node = _find_node_recursive(node_name)
			if node: return rad2deg(node.global_transform.basis.get_euler().y)
			return 0.0
		"GET_NODE_ROT_Z":
			var node_name = args[0] if args.size() > 0 else ""
			var node = _find_node_recursive(node_name)
			if node: return rad2deg(node.global_transform.basis.get_euler().z)
			return 0.0
		"SYSTEM":
			var parsed = _parse_system_helper_args(args)
			if not bool(parsed.get("ok", false)):
				printerr("[SessionManager][OYS SYSTEM] Invalid args: ", parsed.get("error", "unknown"))
				return -1
			if is_replaying and not is_recording:
				print("[SessionManager][OYS SYSTEM] Skipped during deterministic replay: %s %s" % [
					str(parsed.get("exec", "")),
					str(parsed.get("args", []))
				])
				return 0
			var result = _run_system_helper_command(
				str(parsed.get("exec", "")),
				parsed.get("args", []),
				bool(parsed.get("blocking", false))
			)
			if not bool(result.get("ok", false)):
				printerr("[SessionManager][OYS SYSTEM] Command failed: ", result.get("error", "unknown"))
				return -1
			return int(result.get("value", -1))
	return 0.0

func _parse_system_helper_args(args: Array) -> Dictionary:
	var tokens := []
	for raw in args:
		tokens.append(str(raw).strip_edges())
	if tokens.empty():
		return {"ok": false, "error": "missing command"}

	var blocking := false
	var mode = tokens[0].to_lower()
	if mode == "sync":
		blocking = true
		tokens.pop_front()
	elif mode == "async":
		blocking = false
		tokens.pop_front()

	if tokens.empty():
		return {"ok": false, "error": "missing executable"}

	var exec_path = String(tokens[0]).strip_edges()
	if exec_path == "":
		return {"ok": false, "error": "empty executable"}
	tokens.pop_front()

	return {
		"ok": true,
		"exec": exec_path,
		"args": tokens,
		"blocking": blocking
	}

func _run_system_helper_command(exec_path: String, exec_args: Array, blocking: bool) -> Dictionary:
	if exec_path.strip_edges() == "":
		return {"ok": false, "error": "empty executable", "value": - 1, "blocking": blocking}

	var output := []
	var ret = OS.execute(exec_path, exec_args, blocking, output, true)

	if blocking:
		return {"ok": true, "value": int(ret), "blocking": true}

	if int(ret) >= 0:
		var pid = int(ret)
		if pid <= 0:
			_system_launch_counter += 1
			pid = _system_launch_counter
		return {"ok": true, "value": pid, "blocking": false}
	return {"ok": false, "error": "could not start process", "value": - 1, "blocking": false}

func _find_node_recursive(name: String) -> Node:
	if name == "Pilot" or name == "Player":
		_find_player()
		return player
	
	if _node_cache.has(name):
		var cached_node = _node_cache[name]
		if is_instance_valid(cached_node) and cached_node.is_inside_tree() and cached_node.name == name:
			return cached_node
		else:
			_node_cache.erase(name)

	var found_node = null
	if get_tree().current_scene:
		found_node = get_tree().current_scene.find_node(name, true, false)
	else:
		# Fallback: Search from root
		found_node = get_tree().get_root().find_node(name, true, false)

	if found_node:
		_node_cache[name] = found_node

	return found_node

func _handle_math_command(cmd: Dictionary):
	var target_var = cmd.get("var", "")
	var expression = cmd.get("expression", "")
	var result = 0.0
	
	if target_var == "": return
	
	var expr_parts = expression.split(" ", false)
	if expr_parts.size() == 1:
		result = _resolve_value(expr_parts[0])
	elif expr_parts.size() == 2:
		var left = oys_variables.get(target_var, 0.0)
		var inner_op = expr_parts[0]
		var right = _resolve_value(expr_parts[1])
		match inner_op:
			"+": result = float(left) + float(right)
			"-": result = float(left) - float(right)
			"*": result = float(left) * float(right)
			"/": if float(right) != 0: result = float(left) / float(right)
	elif expr_parts.size() == 3:
		var left = _resolve_value(expr_parts[0])
		var inner_op = expr_parts[1]
		var right = _resolve_value(expr_parts[2])
		match inner_op:
			"+": result = float(left) + float(right)
			"-": result = float(left) - float(right)
			"*": result = float(left) * float(right)
			"/": if float(right) != 0: result = float(left) / float(right)
	
	oys_variables[target_var] = result

func _handle_assert_command(cmd: Dictionary):
	if not player: return
	
	var condition = cmd.get("condition", "")
	# print("[SessionManager] Evaluating ASSERT: ", condition, " at frame ", _replay_frame)
	if condition == "": return
	
	# Basic parse: "$var OP value" OR "prop OP value" with optional arithmetic on right side
	# condition string example: "$delta_x < 0.05 \"Message\""
	
	var parts = condition.split("\"", 2)
	var expression = parts[0].strip_edges()
	var msg = parts[1] if parts.size() > 1 else "Assertion failed"
	
	var expr_parts = expression.split(" ", false)
	if expr_parts.size() < 3:
		printerr("❌ Assertion malformed at frame %d: %s" % [_replay_frame, condition])
		_show_subtitle("ASSERT FAIL: malformed assertion", Color(1.0, 0.35, 0.35), 3.0)
		oys_assert_failed = true
		if is_cli_mode:
			get_tree().quit(1)
		return
		
	var left_key = expr_parts[0]
	var op = expr_parts[1]
	# Collect all tokens after op as the right-side expression (supports arithmetic like $var - 0.35)
	var right_tokens := []
	for _ri in range(2, expr_parts.size()):
		right_tokens.append(expr_parts[_ri])
	
	var left_val = _resolve_value(left_key)
	var right_val = _evaluate_expr_tokens_sm(right_tokens)
	
	# Compare
	var passed = false
	
	# Use float comparison if numbers
	if typeof(left_val) in [TYPE_REAL, TYPE_INT] and typeof(right_val) in [TYPE_REAL, TYPE_INT]:
		left_val = float(left_val)
		right_val = float(right_val)
		match op:
			">": passed = left_val > right_val
			"<": passed = left_val < right_val
			"==": passed = left_val == right_val
			"!=": passed = left_val != right_val
			">=": passed = left_val >= right_val
			"<=": passed = left_val <= right_val
	else:
		# String/Bool comparison
		match op:
			"==": passed = str(left_val) == str(right_val)
			"!=": passed = str(left_val) != str(right_val)
	
	if passed:
		_log_to_oys_console("ASSERT_OK", msg)
		_show_subtitle("ASSERT OK: %s" % msg, Color(0.35, 1.0, 0.35), 2.5)
	else:
		var fail_text = "ASSERT FAILED: %s (Actual: %s %s %s)" % [msg, left_val, op, right_val]
		print("❌ ", fail_text)
		_log_to_oys_console("ASSERT_FAIL", fail_text)
		_show_subtitle(fail_text, Color(1.0, 0.35, 0.35), 3.0)
		oys_assert_failed = true
		if is_cli_mode:
			get_tree().quit(1)

func _resolve_value(key_or_val):
	if typeof(key_or_val) == TYPE_STRING:
		if key_or_val.begins_with("$"):
			return oys_variables.get(key_or_val, 0.0)
		if key_or_val.is_valid_float():
			return key_or_val.to_float()
		if key_or_val == "true": return true
		if key_or_val == "false": return false
		
		# Could be a player property?
		# Try to fetch from player if it looks like a property path
		if player and not key_or_val.begins_with("\""):
			var prop_val = _get_nested_prop(player, key_or_val)
			if prop_val != null:
				return prop_val
				
	return key_or_val

func _set_player_prop(prop, val):
	if not player: return
	# Support basic pos/rot shortcuts
	if prop == "pos":
		var pos_vec = val
		if typeof(val) == TYPE_STRING:
			pos_vec = _parse_vector3(val)
		elif typeof(val) == TYPE_VECTOR3:
			pos_vec = val
		
		if typeof(pos_vec) == TYPE_VECTOR3:
			player.global_transform.origin = pos_vec
			if "velocity" in player: player.velocity = Vector3.ZERO
			
			var ts = get_node_or_null("TeleportSystem")
			if ts and ts.has_method("force_initial_spawn"):
				ts.force_initial_spawn(player.global_transform)
	elif prop == "rot":
		var r = float(val)
		player.rotation_degrees.y = r
		if "yaw" in player:
			player.yaw = deg2rad(r)
	else:
		# Generic property set not fully implemented safely, assume standard props
		pass

func _parse_vector3(s: String) -> Vector3:
	var cleaned = s.replace("(", "").replace(")", "").strip_edges()
	var components = cleaned.split(",")
	if components.size() >= 3:
		return Vector3(
			components[0].strip_edges().to_float(),
			components[1].strip_edges().to_float(),
			components[2].strip_edges().to_float()
		)
	return Vector3.ZERO

func _get_nested_prop(obj, prop_path):
	# Soporte para alias comunes
	var real_path = prop_path
	if prop_path == "pos" or prop_path.begins_with("pos."):
		real_path = prop_path.replace("pos", "global_transform.origin")
	
	# Usar get_indexed de Godot que es mucho más robusto para esto
	# Transforma "global_transform.origin.y" en "global_transform:origin:y" para get_indexed
	
	# Verificamos si existe antes de llamar (evita crashes)
	# Nota: get_indexed no tiene una forma fácil de checkear existencia sin try-catch 
	# (que no existe en GDScript). Usamos un enfoque híbrido.
	
	var parts = real_path.split(".")
	var current = obj
	for part in parts:
		if typeof(current) == TYPE_OBJECT:
			if part in current:
				current = current.get(part)
			else:
				return null
		elif typeof(current) == TYPE_VECTOR3:
			if part == "x": current = current.x
			elif part == "y": current = current.y
			elif part == "z": current = current.z
			else: return null
		elif typeof(current) == TYPE_TRANSFORM:
			if part == "origin": current = current.origin
			elif part == "basis": current = current.basis
			else: return null
		elif typeof(current) == TYPE_BASIS:
			if part == "x": current = current.x
			elif part == "y": current = current.y
			elif part == "z": current = current.z
			else: return null
		else:
			return null
			
	return current

func run_playback():
	_find_player()

	# Detectar cuando el provider llega al final del buffer y validar
	var prov = null
	if is_instance_valid(_replay_input_provider):
		prov = _replay_input_provider
	elif player and "input_provider" in player and player.input_provider:
		prov = player.input_provider
	elif is_instance_valid(_active_input_provider):
		prov = _active_input_provider
	
	if prov and prov.mode == prov.Mode.REPLAY:
		var idx = prov.playback_index
		var sz = prov.playback_buffer.size()
		if idx >= sz and not _drift_validated:
			_finish_and_validate()

# Helper para tests: ejecuta la simulación desde un buffer
# Asume que player ya está en el árbol y que las plataformas también están instanciadas
func run_simulation_from_buffer(buffer_data: Array, world_start_state: Dictionary, player_controller: Node, yield_frames: int = 3) -> Dictionary:
	var result = {
		"final_pos": null,
		"final_vel": null,
		"final_yaw": null,
		"final_pitch": null,
		"drift": 0.0,
		"passed": false
	}
	
	if not player_controller:
		printerr("SessionManager: player_controller is null")
		return result
	
	# 0. Esperar a que el árbol registre todos los nodos en physics_server
	for _i in range(yield_frames):
		player_controller.get_tree().call_group("", "update") # Update all nodes
	
	# 1. Restaurar estado inicial del mundo (plataformas, etc.)
	var sync_nodes = _get_replay_sync_nodes()
	for node_path in world_start_state.keys():
		var node = get_tree().get_root().get_node_or_null(node_path)
		if node and node.has_method("restore_snapshot"):
			node.restore_snapshot(world_start_state[node_path])
		else:
			print("Warning: Could not restore node at path ", node_path)
	
	# 2. Restaurar estado inicial del jugador si hay snapshot
	var buffer_copy = buffer_data.duplicate(true)
	if buffer_copy.size() > 0 and buffer_copy[0].has("snapshot"):
		if player_controller.has_method("restore_snapshot"):
			player_controller.restore_snapshot(buffer_copy[0]["snapshot"])
		buffer_copy.remove(0)
	
	# 3. Crear InputProviderV2 en modo REPLAY
	var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
	var input_provider = InputProviderV2.new()
	var input_buffer = []
	for entry in buffer_copy:
		if entry.has("input"):
			input_buffer.append(entry["input"])
	input_provider.set_replay_data(input_buffer)
	
	# 4. Asignar provider al jugador
	if "input_provider" in player_controller:
		player_controller.input_provider = input_provider
	player_controller.is_replay_mode = true
	player_controller.set_physics_process(true)
	
	# 5. Desactivar _physics_process en plataformas (usaremos step centralizado)
	for node in sync_nodes:
		if node != player_controller:
			node.set_physics_process(false)
	
	# 6. Ejecutar la simulación
	var frame_count = 0
	var max_frames = 4000 # XXX: Why do we need this limit?
	while frame_count < max_frames and input_provider.playback_index < input_provider.playback_buffer.size():
		# Obtener input
		var input = input_provider.get_input()
		
		# Step player
		if player_controller.has_method("step"):
			player_controller.step(FIXED_DT, input)
		
		# Step plataformas
		for node in sync_nodes:
			if node != player_controller and node.has_method("step"):
				node.step(FIXED_DT)
		
		frame_count += 1
	
	# 7. Capturar estado final
	result["final_pos"] = player_controller.global_transform.origin
	result["final_vel"] = player_controller.velocity if "velocity" in player_controller else Vector3.ZERO
	result["final_yaw"] = player_controller.yaw if "yaw" in player_controller else 0.0
	result["final_pitch"] = player_controller.pitch if "pitch" in player_controller else 0.0
	
	# 8. Limpiar
	player_controller.is_replay_mode = false
	
	return result

func load_prop(path: String) -> void:
	# OYS command: LOAD_PROP
	print("[SessionManager] load_prop called: ", path)
	
	var prop_stage = get_tree().current_scene
	if not prop_stage or not prop_stage.has_method("load_prop"):
		# Try fallback search for a node named PropStage specifically
		prop_stage = get_tree().root.find_node("PropStage", true, false)
		
	if prop_stage and prop_stage.has_method("load_prop"):
		prop_stage.load_prop(path)
	else:
		printerr("[SessionManager] Error: LOAD_PROP called but PropStage not found or invalid.")

func _handle_call_command(cmd: Dictionary):
	var method = cmd.get("method", "")
	var args = cmd.get("args", [])
	
	# Detect if 'method' is actually a registered OYS Actor
	var actor = get_oys_actor(method)
	
	if actor:
		# ACTOR CALL: Command was CALL ActorName "MethodName" [Args...]
		if args.size() > 0:
			var real_method = _resolve_value(args[0])
			var call_args_raw = []
			if args.size() > 1:
				call_args_raw = args.duplicate()
				call_args_raw.pop_front()
				
			var resolved_call_args = _resolve_complex_args(call_args_raw)
			
			if actor.has_method(real_method):
				actor.callv(real_method, resolved_call_args)
			else:
				printerr("[OYS Replay] CALL Actor Error: Actor '%s' has no method '%s'" % [method, real_method])
		else:
			printerr("[OYS Replay] CALL Actor Error: Missing method name for actor '%s'" % method)
	else:
		# LEGACY/PROP CALL
		var resolved_args = _resolve_complex_args(args)
	
		var target = _resolve_prop() # Try prop first
		if not target or not target.has_method(method):
			var stage = _resolve_stage()
			if stage and stage != target and stage.has_method(method):
				target = stage
			else:
				target = self # Fallback to SessionManager
				
		if target and target.has_method(method):
			target.callv(method, resolved_args)
		else:
			printerr("[OYS Replay] CALL failed: Method '%s' not found" % method)

func _resolve_complex_args(raw_args: Array) -> Array:
	var final_args = []
	var i = 0
	while i < raw_args.size():
		var val = raw_args[i]
		var resolved_val = _resolve_value(val)
		
		# If non-string, use directly
		if typeof(resolved_val) != TYPE_STRING:
			final_args.append(resolved_val)
			i += 1
			continue
			
		val = resolved_val
		
		# Validar strings vacíos para evitar crashes en accessos [0]
		if val.empty():
			final_args.append(val)
			i += 1
			continue

		# Detect split vector "[x, y, z]" start
		if val.begins_with("[") and not val.ends_with("]"):
			var built = val
			var j = i + 1
			var completed = false
			while j < raw_args.size():
				var next_val = raw_args[j]
				built += "" + str(next_val)
				if str(next_val).ends_with("]"):
					completed = true
					i = j
					break
				j += 1
			
			if completed:
				final_args.append(_parse_vector3_flexible(built))
			else:
				final_args.append(val)
				
		# Detect single string vector "[x,y,z]"
		elif val.begins_with("[") and val.ends_with("]"):
			final_args.append(_parse_vector3_flexible(val))
		else:
			final_args.append(val)
			
		i += 1
	return final_args

func _parse_vector3_flexible(s: String) -> Vector3:
	var cleaned = s.replace("[", "").replace("]", "").replace("(", "").replace(")", "").strip_edges()
	var parts = cleaned.split(",")
	if parts.size() >= 3:
		return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	return Vector3.ZERO

func _handle_spawn_command(cmd: Dictionary):
	var scene_path = cmd.get("scene", "")
	if scene_path == "":
		printerr("[SessionManager] SPAWN failed: empty scene path")
		return

	var scene = load(scene_path)
	if scene == null:
		printerr("[SessionManager] SPAWN failed: cannot load scene ", scene_path)
		return

	var obj = scene.instance()
	if obj == null:
		printerr("[SessionManager] SPAWN failed: cannot instance scene ", scene_path)
		return
	var custom_name = String(cmd.get("name", "")).strip_edges()
	if custom_name != "":
		obj.name = custom_name

	var has_pos = cmd.has("pos") and obj is Spatial
	var parsed_pos = Vector3.ZERO
	if has_pos:
		var raw_pos = cmd.get("pos")
		if typeof(raw_pos) == TYPE_VECTOR3:
			parsed_pos = raw_pos
		else:
			parsed_pos = _parse_vector3_flexible(str(raw_pos))

	var parent = _get_active_scene_root()
	if not is_instance_valid(parent):
		parent = _resolve_stage()
	if not is_instance_valid(parent):
		parent = get_tree().root
	if not is_instance_valid(parent):
		printerr("[SessionManager] SPAWN failed: no valid parent for ", scene_path)
		return

	# Pre-position before entering tree to avoid one-frame collisions at origin.
	if has_pos:
		var s = obj as Spatial
		if parent is Spatial:
			var local_pos = (parent as Spatial).to_local(parsed_pos)
			var local_t = s.transform
			local_t.origin = local_pos
			s.transform = local_t
		else:
			var global_t = s.global_transform
			global_t.origin = parsed_pos
			s.global_transform = global_t

	parent.add_child(obj)
	_register_spawned_node(obj)
	_prepare_spawned_node_for_determinism(obj)
	if has_pos:
		var s = obj as Spatial
		var final_t = s.global_transform
		final_t.origin = parsed_pos
		s.global_transform = final_t
	if obj is RigidBody:
		var rb = obj as RigidBody
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.sleeping = false

	if _spawn_cmd_wants_anna(cmd):
		_configure_spawned_anna_agent(obj, cmd)

func _spawn_cmd_wants_anna(cmd: Dictionary) -> bool:
	if not cmd.has("anna") and not cmd.has("anna_native") and not cmd.has("anna_model"):
		return false
	if cmd.has("anna") and _as_bool(cmd.get("anna", false)):
		return true
	if cmd.has("anna_native") and _as_bool(cmd.get("anna_native", false)):
		return true
	if _as_string(cmd.get("anna_model", "")).strip_edges() != "":
		return true
	return false

func _as_bool(value, default_value := false) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	var s = String(value).strip_edges().to_lower()
	if s == "":
		return default_value
	return s in ["1", "true", "yes", "on"]

func _as_string(value, default_value := "") -> String:
	if value == null:
		return default_value
	return String(value)

func _configure_spawned_anna_agent(obj: Node, cmd: Dictionary) -> void:
	if not is_instance_valid(obj):
		return
	if not obj.has_method("inject_input"):
		printerr("[SessionManager] SPAWN anna=true ignored: spawned node lacks inject_input() -> ", obj.name)
		return

	var anna = obj.get_node_or_null("AnnaInterface")
	if not anna:
		var anna_script = load("res://core_v2/anna/AnnaInterface.gd")
		if anna_script:
			anna = anna_script.new()
			anna.name = "AnnaInterface"
			obj.add_child(anna)
	if not anna:
		printerr("[SessionManager] Could not attach AnnaInterface to ", obj.name)
		return

	if anna.has_method("set_controlled_player"):
		anna.call("set_controlled_player", obj)
	if anna.has_method("set_rl_active"):
		anna.call("set_rl_active", _as_bool(cmd.get("anna_active", true), true))

	var target_node_name = _as_string(cmd.get("anna_target_node", "")).strip_edges()
	if target_node_name != "":
		var named_target = _find_node_recursive(target_node_name)
		if named_target and anna.has_method("set_target_node"):
			anna.call("set_target_node", named_target)

	if cmd.has("anna_target") and anna.has_method("set_custom_target"):
		var target_pos = _parse_vector3_flexible(_as_string(cmd.get("anna_target", "")))
		anna.call("set_custom_target", target_pos)

	var controller = obj.get_node_or_null("AnnaNPCController")
	if not controller:
		var controller_script = load("res://core_v2/anna/AnnaNPCController.gd")
		if controller_script:
			controller = controller_script.new()
			controller.name = "AnnaNPCController"
			obj.add_child(controller)
	if not controller:
		printerr("[SessionManager] Could not attach AnnaNPCController to ", obj.name)
		return

	var model_path = _as_string(cmd.get("anna_model", "")).strip_edges()
	if model_path == "":
		model_path = _as_string(cmd.get("onnx_model", "")).strip_edges()
	if model_path != "":
		controller.set("onnx_model_path", model_path)
	controller.set("auto_start", _as_bool(cmd.get("anna_active", true), true))
	if controller.has_method("set_active"):
		controller.call("set_active", _as_bool(cmd.get("anna_active", true), true))

func _handle_anna_command(cmd: Dictionary) -> void:
	var target_name = _as_string(cmd.get("target", "")).strip_edges()
	var target_node: Node = null
	if target_name != "":
		target_node = _find_node_recursive(target_name)
	else:
		_find_player()
		target_node = player
	if not is_instance_valid(target_node):
		printerr("[SessionManager] ", cmd.get("command", "ANNA"), " failed: target not found")
		return

	var anna = target_node.get_node_or_null("AnnaInterface")
	if not anna:
		var anna_script = load("res://core_v2/anna/AnnaInterface.gd")
		if anna_script:
			anna = anna_script.new()
			anna.name = "AnnaInterface"
			target_node.add_child(anna)
	if not anna:
		printerr("[SessionManager] ", cmd.get("command", "ANNA"), " failed: AnnaInterface unavailable")
		return

	if anna.has_method("set_controlled_player"):
		anna.call("set_controlled_player", target_node)

	var command = String(cmd.get("command", "")).to_upper()
	match command:
		"ANNA_ENABLE":
			if anna.has_method("set_rl_active"):
				anna.call("set_rl_active", true)
		"ANNA_DISABLE":
			if anna.has_method("set_rl_active"):
				anna.call("set_rl_active", false)
		"ANNA_SET_TARGET":
			var pos_str = _as_string(cmd.get("pos", "")).strip_edges()
			if pos_str == "":
				printerr("[SessionManager] ANNA_SET_TARGET failed: missing pos=(x,y,z)")
			elif anna.has_method("set_custom_target"):
				anna.call("set_custom_target", _parse_vector3_flexible(pos_str))

func _handle_play_anim(cmd: Dictionary):
	var path = cmd.get("path", "")
	var anim = cmd.get("anim", "")
	var blend = float(cmd.get("blend", -1.0))
	var node = _find_node_recursive(path)
	if node and node is AnimationPlayer:
		node.play(anim, blend)

func _resolve_stage() -> Node:
	var root = get_tree().root
	var stage = root.find_node("PropStage", true, false)
	if stage: return stage
	stage = get_tree().current_scene
	if stage and (stage.name == "PropStage" or stage.has_method("load_prop")):
		return stage
	return null

func _get_active_scene_root() -> Node:
	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		return scene

	_find_player()
	if is_instance_valid(player):
		var n: Node = player
		while n.get_parent() and n.get_parent() != get_tree().root:
			n = n.get_parent()
		return n

	return null

func _register_spawned_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node.is_in_group(SESSION_SPAWN_GROUP):
		node.add_to_group(SESSION_SPAWN_GROUP)
	_session_spawned_nodes.append(weakref(node))

func _cleanup_session_spawned_nodes() -> void:
	var is_testing = false
	if Engine.has_singleton("GdUnit3"):
		is_testing = Engine.get_singleton("GdUnit3").is_test_suite()

	for wr in _session_spawned_nodes:
		if wr == null:
			continue
		var node = wr.get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			if is_testing:
				node.free()
			else:
				node.queue_free()
	_session_spawned_nodes.clear()

	# Defensive cleanup: remove any lingering SPAWN nodes that weren't tracked
	# (e.g. after scene transitions/reloads in batch mode).
	var group_nodes = get_tree().get_nodes_in_group(SESSION_SPAWN_GROUP)
	for node in group_nodes:
		if not is_instance_valid(node):
			continue
		if node.is_queued_for_deletion():
			continue
		if is_testing:
			node.free()
		else:
			node.queue_free()
	_replay_sync_cache_dirty = true

func _prepare_spawned_node_for_determinism(node: Node) -> void:
	if not is_instance_valid(node):
		return

	# If the node supports snapshot restore but is missing group membership, add it.
	if node.has_method("get_snapshot") and node.has_method("restore_snapshot") and not node.is_in_group("replay_sync"):
		node.add_to_group("replay_sync")

	# During recording/replay we must centralize simulation stepping.
	if (is_recording or is_replaying) and node.has_method("step"):
		node.set_physics_process(false)

	_replay_sync_cache_dirty = true

func _resolve_prop() -> Node:
	var stage = _resolve_stage()
	if stage and "current_prop" in stage:
		if is_instance_valid(stage.current_prop):
			return stage.current_prop
	return null

# --- OYS ACTOR REGISTRY ---

var _oys_actors := {}

func register_oys_actor(name: String, node: Node) -> void:
	if not is_instance_valid(node):
		printerr("[SessionManager] Attempted to register invalid actor: ", name)
		return
	_oys_actors[name] = node
	if not node.is_in_group("oys_actor"):
		node.add_to_group("oys_actor")
	print("[SessionManager] OYS Actor Registered: ", name, " -> ", node.name)

func get_oys_actor(name: String) -> Node:
	if _oys_actors.has(name):
		var node = _oys_actors[name]
		if is_instance_valid(node):
			return node
		else:
			_oys_actors.erase(name) # Clean up invalid ref
	return null

func unregister_oys_actor(name: String) -> void:
	if _oys_actors.has(name):
		var node = _oys_actors[name]
		if is_instance_valid(node) and node.is_in_group("oys_actor"):
			node.remove_from_group("oys_actor")
		_oys_actors.erase(name)

func capture_scene_transition_state() -> Dictionary:
	var out := {}
	_find_player()
	if is_instance_valid(player) and player.has_method("get_full_snapshot"):
		var snapshot = player.get_full_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			out["player_snapshot"] = snapshot.duplicate(true)
	return out

func _get_transition_param(key: String, fallback):
	var sm = get_node_or_null("/root/SceneManager")
	if sm:
		var params = sm.get("_transition_params")
		if typeof(params) == TYPE_DICTIONARY:
			return params.get(key, fallback)
	return fallback

func apply_scene_transition_state(target_spawn_id: String = "", state_data: Dictionary = {}):
	_find_player()
	if not is_instance_valid(player):
		yield (get_tree(), "physics_frame")
		return null

	var active_dome_id := ""
	if typeof(state_data) == TYPE_DICTIONARY:
		active_dome_id = String(state_data.get("active_dome_id", "")).strip_edges()
	_apply_active_dome_context(active_dome_id)

	var _am_placed := bool(_get_transition_param("_airlock_manager_placed", false))
	if not _am_placed:
		if typeof(state_data) == TYPE_DICTIONARY and state_data.has("player_snapshot"):
			var snapshot = state_data["player_snapshot"]
			if typeof(snapshot) == TYPE_DICTIONARY and player.has_method("restore_snapshot"):
				player.restore_snapshot(snapshot)
		elif typeof(state_data) == TYPE_DICTIONARY and state_data.has("controller_mode"):
			var controller_manager = player.get_node_or_null("ControllerManager")
			if controller_manager and controller_manager.has_method("switch_to"):
				controller_manager.switch_to(int(state_data["controller_mode"]))

	# AirlockManager already placed the player via reparenting — use destination airlock
	# for position/orientation just like the normal path, then open the exit door.
	if _am_placed:
		var target_airlock = _find_transition_airlock(state_data)
		if is_instance_valid(target_airlock) and typeof(state_data.get("airlock_relative_transform", null)) == TYPE_TRANSFORM:
			var relative_transform: Transform = state_data["airlock_relative_transform"]
			var target_transform: Transform = target_airlock.global_transform * relative_transform
			var exit_transform: Transform = _face_airlock_exit(target_airlock, state_data, target_transform)
			var body_transform := target_transform
			body_transform.basis = Basis.IDENTITY
			# Move player directly (no teleport_to to avoid triggering extra freeze/yaw reset).
			player.global_transform = body_transform
			if "velocity" in player:
				player.velocity = Vector3.ZERO
			if "_post_teleport_snap_frames" in player:
				player._post_teleport_snap_frames = 8
			# Force camera rig Y initialized so snap works even on first frame.
			if "_camera_rig_y_initialized" in player:
				player._camera_rig_y_initialized = true
			if player.has_method("snap_camera_to_current_state"):
				player.snap_camera_to_current_state()
			_restore_transition_camera_state(state_data, exit_transform, target_airlock)
			_snap_transition_visual(exit_transform, state_data, target_airlock)
			_apply_airlock_relative_velocity(target_airlock, state_data)
			_open_transition_airlock_exit(target_airlock, state_data)
		elif is_instance_valid(target_airlock):
			var exit_transform := _face_airlock_exit(target_airlock, state_data, player.global_transform)
			if player.has_method("snap_camera_to_current_state"):
				player.snap_camera_to_current_state()
			_restore_transition_camera_state(state_data, exit_transform, target_airlock)
			_snap_transition_visual(exit_transform, state_data, target_airlock)
			_apply_airlock_relative_velocity(target_airlock, state_data)
			_open_transition_airlock_exit(target_airlock, state_data)
		else:
			_restore_transition_camera_state(state_data, player.global_transform, null)
		var teleport_system = get_node_or_null("TeleportSystem")
		if teleport_system and teleport_system.has_method("force_initial_spawn"):
			teleport_system.force_initial_spawn(player.global_transform, player.get("yaw") if "yaw" in player else 0.0, player.get("pitch") if "pitch" in player else 0.0)
		yield(get_tree(), "physics_frame")
		return player

	var target_airlock = _find_transition_airlock(state_data)
	var used_airlock_frame := false
	if is_instance_valid(target_airlock) and typeof(state_data.get("airlock_relative_transform", null)) == TYPE_TRANSFORM:
		var relative_transform: Transform = state_data["airlock_relative_transform"]
		var target_transform: Transform = target_airlock.global_transform * relative_transform
		var exit_transform: Transform = _face_airlock_exit(target_airlock, state_data, target_transform)
		# Teleport body with identity rotation to preserve the camera_rig local=world invariant
		# (PlayerControllerV2 always writes Basis(Y, world_yaw) to camera_rig LOCAL transform)
		var body_transform := target_transform
		body_transform.basis = Basis.IDENTITY
		if player.has_method("teleport_to"):
			player.teleport_to(body_transform)
		else:
			player.global_transform = body_transform
		_restore_transition_camera_state(state_data, exit_transform, target_airlock)
		_snap_transition_visual(exit_transform, state_data, target_airlock)
		_apply_airlock_relative_velocity(target_airlock, state_data)
		used_airlock_frame = true

	var spawn = _find_scene_spawn_point(target_spawn_id)
	if not used_airlock_frame and spawn and is_instance_valid(spawn):
		if player.has_method("teleport_to"):
			player.teleport_to(spawn.global_transform)
		else:
			player.global_transform = spawn.global_transform
		_restore_transition_camera_state(state_data, spawn.global_transform, null)
		_snap_transition_visual(spawn.global_transform, state_data, null)

	if used_airlock_frame:
		_open_transition_airlock_exit(target_airlock, state_data)

	var teleport_system = get_node_or_null("TeleportSystem")
	if teleport_system and teleport_system.has_method("force_initial_spawn"):
		var yaw = player.get("yaw") if "yaw" in player else 0.0
		var pitch = player.get("pitch") if "pitch" in player else 0.0
		teleport_system.force_initial_spawn(player.global_transform, yaw, pitch)

	yield (get_tree(), "physics_frame")
	return player

func _apply_active_dome_context(active_dome_id: String) -> void:
	var normalized := String(active_dome_id).strip_edges()
	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		if normalized == "":
			if scene.has_meta("dome_id"):
				scene.remove_meta("dome_id")
		else:
			scene.set_meta("dome_id", normalized)
	if is_instance_valid(player):
		if normalized == "":
			if player.has_meta("dome_id"):
				player.remove_meta("dome_id")
		else:
			player.set_meta("dome_id", normalized)

func _restore_transition_camera_state(state_data: Dictionary, target_transform: Transform, target_airlock: Spatial = null) -> void:
	if not is_instance_valid(player):
		return
	if state_data.has("camera_yaw") and "yaw" in player:
		if is_instance_valid(target_airlock) and typeof(state_data.get("camera_relative_forward", null)) == TYPE_VECTOR3:
			var camera_forward: Vector3 = target_airlock.global_transform.basis.xform(state_data["camera_relative_forward"])
			camera_forward.y = 0.0
			if camera_forward.length_squared() > 0.0001:
				camera_forward = camera_forward.normalized()
				player.yaw = atan2(-camera_forward.x, -camera_forward.z)
			else:
				player.yaw = target_transform.basis.get_euler().y
		elif state_data.has("camera_body_yaw_offset"):
			player.yaw = target_transform.basis.get_euler().y + float(state_data["camera_body_yaw_offset"])
		else:
			player.yaw = float(state_data["camera_yaw"])
		if "yaw_deg" in player:
			player.yaw_deg = rad2deg(player.yaw)
	if state_data.has("camera_pitch") and "pitch" in player:
		player.pitch = float(state_data["camera_pitch"])
		if "pitch_deg" in player:
			player.pitch_deg = rad2deg(player.pitch)
	if "camera_rig" in player and is_instance_valid(player.camera_rig) and "yaw" in player and "pitch" in player:
		player.camera_rig.transform.basis = Basis(Vector3.UP, player.yaw) * Basis(Vector3.RIGHT, player.pitch)
		player.camera_rig.force_update_transform()
	if state_data.has("camera_restore_spring_length"):
		var restore_len := float(state_data["camera_restore_spring_length"])
		if restore_len > 0.0:
			player.set_meta("airlock_restore_spring_length", restore_len)
	if state_data.has("camera_arm_spring_length"):
		# Restore arm lengths directly — avoids snap_collision_to_scene yank when
		# the exterior scene has no geometry behind the camera on arrival.
		var arm_len := float(state_data["camera_arm_spring_length"])
		var arm = player.get("_cached_spring_arm")
		if is_instance_valid(arm):
			if "spring_length" in arm:
				arm.spring_length = arm_len
			if "current_length" in arm:
				arm.current_length = arm_len
		if "current_spring_length" in player:
			player.current_spring_length = arm_len
		if "base_spring_length_3d" in player:
			player.base_spring_length_3d = arm_len
		if player.has_method("snap_ots_on_arrival_if_pending"):
			player.snap_ots_on_arrival_if_pending()
	elif player.has_method("snap_camera_to_current_state"):
		player.snap_camera_to_current_state()

func _snap_transition_visual(target_transform: Transform, state_data: Dictionary = {}, target_airlock: Spatial = null) -> void:
	if not is_instance_valid(player):
		return
	var animator = player.get("animator") if "animator" in player else null
	if is_instance_valid(animator) and animator.has_method("snap_visual_to_direction"):
		var visual_forward := -target_transform.basis.z
		if is_instance_valid(target_airlock) and typeof(state_data.get("visual_relative_forward", null)) == TYPE_VECTOR3:
			visual_forward = target_airlock.global_transform.basis.xform(state_data["visual_relative_forward"])
		visual_forward.y = 0.0
		if visual_forward.length_squared() > 0.0001:
			animator.snap_visual_to_direction(visual_forward.normalized())

func _face_airlock_exit(target_airlock: Spatial, state_data: Dictionary, target_transform: Transform) -> Transform:
	if not is_instance_valid(target_airlock):
		return target_transform
	var exit_door := String(state_data.get("target_airlock_exit_door", "outer")).strip_edges().to_lower()
	var local_exit_dir := Vector3.BACK
	if exit_door == "inner":
		local_exit_dir = Vector3.FORWARD
	elif exit_door == "none":
		return target_transform
	var exit_dir: Vector3 = target_airlock.global_transform.basis.xform(local_exit_dir)
	exit_dir.y = 0.0
	if exit_dir.length_squared() <= 0.0001:
		return target_transform
	exit_dir = exit_dir.normalized()
	var yaw := atan2(-exit_dir.x, -exit_dir.z)
	var out := target_transform
	out.basis = Basis(Vector3.UP, yaw)
	return out

func _find_transition_airlock(state_data: Dictionary) -> Spatial:
	if typeof(state_data) != TYPE_DICTIONARY:
		return null
	var scene = get_tree().current_scene
	if not is_instance_valid(scene):
		return null

	var target_path := String(state_data.get("target_airlock_path", "")).strip_edges()
	if target_path != "":
		var by_path = scene.get_node_or_null(NodePath(target_path))
		if is_instance_valid(by_path) and by_path is Spatial:
			return by_path
		var by_name = scene.find_node(target_path, true, false)
		if is_instance_valid(by_name) and by_name is Spatial:
			return by_name
		# Specific path was requested but not found — don't fall back to a random airlock
		return null

	var fallback = scene.find_node("*Airlock*", true, false)
	if is_instance_valid(fallback) and fallback is Spatial:
		return fallback
	return null

func _apply_airlock_relative_velocity(target_airlock: Spatial, state_data: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	if not ("velocity" in player):
		return
	if typeof(state_data.get("airlock_relative_velocity", null)) != TYPE_VECTOR3:
		return
	var local_velocity: Vector3 = state_data["airlock_relative_velocity"]
	player.velocity = target_airlock.global_transform.basis.xform(local_velocity)

func _open_transition_airlock_exit(target_airlock: Spatial, state_data: Dictionary) -> void:
	if not is_instance_valid(target_airlock):
		return
	var exit_door := String(state_data.get("target_airlock_exit_door", "outer")).strip_edges().to_lower()
	if exit_door == "" or exit_door == "none":
		return

	var fx_node: Node = null
	for child in target_airlock.get_children():
		if child.has_method("start_post_transition_fx"):
			fx_node = child
			break
	if is_instance_valid(fx_node):
		fx_node.call("start_post_transition_fx")
		# Delay door open until the post-transition flicker completes (~1.25 s at 0.8 Hz).
		# This gives the destination scene time to stabilise (domes, WorldRotator, lighting)
		# before the door opens, ensuring a smooth transition.
		# CONNECT_ONESHOT ensures the connection is cleaned up automatically after firing.
		fx_node.connect("fx_complete", target_airlock, "open_exit_door", [exit_door, false, true], CONNECT_ONESHOT)
	elif target_airlock.has_method("open_exit_door"):
		# No FX node present — open immediately as before.
		target_airlock.open_exit_door(exit_door, true, true)

func _find_scene_spawn_point(spawn_id: String = "") -> Position3D:
	var scene = get_tree().current_scene
	if not is_instance_valid(scene):
		return null

	var fallback: Position3D = null
	var pending: Array = [scene]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node is Position3D and "spawn_id" in node:
			var sp := node as Position3D
			if fallback == null:
				fallback = sp
			if spawn_id == "" or String(node.get("spawn_id")) == spawn_id:
				return sp
		for child in node.get_children():
			pending.push_back(child)

	if spawn_id == "":
		return fallback
	return null

func take_oys_screenshot(label: String, _extra = ""):
	# Wait for draw to complete
	yield (get_tree(), "idle_frame")
	yield (VisualServer, "frame_post_draw")
	
	var dir_path = "res://test_output/ui"
	var dir = Directory.new()
	if not dir.dir_exists(dir_path):
		dir.make_dir_recursive(dir_path)
		
	var scene_name = "oysshell"
	if get_tree().current_scene:
		scene_name = get_tree().current_scene.filename.get_file().get_basename().to_lower()
		
	var path = "%s/%s_%s.png" % [dir_path, scene_name, label]
	var img = get_tree().root.get_texture().get_data()
	img.flip_y()
	var err = img.save_png(path)
	if err != OK:
		printerr("[SessionManager] Failed to save screenshot: ", path, " err=", err)
	else:
		print("[SessionManager] Screenshot saved: ", path)
	
	yield (get_tree(), "idle_frame")
	return path
