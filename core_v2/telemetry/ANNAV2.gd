extends Node

const PLAYER_ID_FILE := "user://odisea_player_id.txt"
const CAPTURE_DEFAULT_MAX := 36000 # ~10 min at 60 fps; ring buffer caps memory use

var _command_queue_script = preload("res://core_v2/telemetry/ANNAV2_CommandQueue.gd")
var _thread_script = preload("res://core_v2/telemetry/ANNAV2_Thread.gd")
var _thread_web_script = preload("res://core_v2/telemetry/ANNAV2_Thread_Web.gd")

var _command_queue
var _net_thread
var _is_web_thread := false  # true when using ANNAV2_Thread_Web (worker-backed)
var _player_id := ""
var _session_id := ""
var _build_info := {}

# --- Local telemetry capture (bridge-independent; opt-in for analysis runs) ---
var _capture_enabled := false
# Ring buffer: fixed-size array written via a circular head index. Writes are O(1)
# (no O(n) pop_front shift), so capture cost stays flat regardless of session length.
var _capture_buffer := []
var _capture_head := 0   # next write slot
var _capture_count := 0  # number of valid frames (<= _capture_max)
var _capture_max := CAPTURE_DEFAULT_MAX
var _capture_dump_path := ""
# Custom data points registered by controllers; merged into every captured frame
var _custom_points := {}

# Telemetry is gathered at most every TELEMETRY_INTERVAL_MS (decoupled from frame rate).
# The network thread only sends at 10Hz anyway, so gathering at 60Hz was wasted main-thread
# work. Lower the interval for finer local capture; raise it to reduce ANNA's per-frame cost.
var TELEMETRY_INTERVAL_MS := 100 # 10Hz

# Diagnostico temporal FD-270: cuenta nodos con _physics_process/_process activos.
# Recorrer 2600+ nodos a 10Hz seria mas caro que lo que mide, asi que va aparte
# con su propio throttle y se cachea entre llamadas.
const PROC_COUNT_INTERVAL_MS := 2000
var _last_proc_count_ms := 0
var _cached_proc_counts := {"physics": 0, "process": 0}
# When the game is paused or the window loses focus the user has stepped away and
# nothing measurable is happening: FPS, position and hotzones all describe a frozen
# (and OS-throttled) game. We send one last heartbeat flagging the state and then
# stop the heartbeat stream entirely instead of streaming idle noise to the central.
# The WebSocket stays connected, so bridge commands (inspect/screenshot) keep working
# and resuming costs no reconnect; the dashboard drops the session from the live list
# after its own 30s staleness window, which is the intent.
var _window_focused := true
var _telemetry_idle := false
var _automated_run := false
var _last_telemetry_ms := 0
var _perf_monitor: Node = null
var _perf_profiling_enabled := false
# Replay sessions (HotzonePlayer) must not emit telemetry: they would show up on
# the dashboard as phantom players and pollute hotzone/FPS stats with playback
# numbers. When true we never start the network thread and _process is a no-op.
var _replay_mode := false
var _telemetry_enabled := true

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	_automated_run = _detect_automated_run()
	# Bail out early for hotzone playback: this is a viewer, not a play session.
	# Detected from the cmdline scene arg (native launch + web shell + deep link
	# all pass --scene HotzonePlayer.tscn) and, on web, the shell's is_replaying
	# flag. Returning before _net_thread.start() means no central/peer connection,
	# no heartbeats, no phantom session.
	if _detect_replay_mode():
		_replay_mode = true
		print("[ANNAV2] Replay mode detected — telemetry disabled for this session.")
		return

	# Optimization for HTML5/Weak hardware
	if OS.get_name() == "HTML5" or OS.has_touchscreen_ui_hint():
		TELEMETRY_INTERVAL_MS = 200 # 5Hz for web
		print("[ANNAV2] HTML5: Throttling telemetry to 5Hz")

	_player_id = _load_or_create_player_id()
	_session_id = _generate_session_id()

	_command_queue = _command_queue_script.new()

	# On HTML5, use the worker-backed thread class that bridges to a Web Worker
	# via JavaScript.eval(). WebSocket traffic stays off the main thread.
	if OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		_net_thread = _thread_web_script.new()
		_is_web_thread = true
		print("[ANNAV2] HTML5: using worker-backed WebSocket bridge")
	else:
		_net_thread = _thread_script.new()

	# URL query params (HTML5 only; no-op on native, where env vars are used instead).
	# e.g. index.html?token=XXXX&central=host:port&bridge=host:port&nocentral=1
	var bridge_override = _get_url_param("bridge")
	if bridge_override != "":
		_net_thread._peer_url = "ws://" + bridge_override + "/ws"
	var token_override = _get_url_param("token")
	if token_override != "":
		_net_thread._bridge_token = token_override
	var central_override = _get_url_param("central")
	if central_override != "":
		_net_thread._central_url = "wss://" + central_override + "/ws"
	var scheme_override = _get_url_param("scheme")
	if scheme_override != "":
		_net_thread.set_scheme(scheme_override)
	if _get_url_param("nocentral") in ["1", "true", "yes", "on"]:
		_net_thread._central_enabled = false
	_build_info = _load_build_info()
	if token_override == "":
		var build_token := _get_build_meta_value("token")
		if _is_valid_build_token(build_token) and _net_thread._bridge_token == "odisea-dev-insecure":
			_net_thread._bridge_token = build_token
	if _net_thread.has_method("set_build_info"):
		_net_thread.set_build_info(_build_info)
	# HTML5 desde HTTPS: usar wss:// automáticamente (el central ya tiene TLS)
	if OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		var js = Engine.get_singleton("JavaScript")
		var proto = js.eval("window.location.protocol")
		if proto == "https:":
			_net_thread.set_scheme("wss")

	_net_thread.start(_command_queue, _player_id, _session_id, _build_info.get("game_version", Constants.GAME_VERSION))
	_init_capture_from_env()
	_perf_monitor = get_node_or_null("/root/PerformanceMonitor")
	_perf_profiling_enabled = _perf_monitor and "_profiling_enabled" in _perf_monitor and _perf_monitor._profiling_enabled
	print("[ANNAV2] Initialized. PlayerID: ", _player_id, " SessionID: ", _session_id)

# Disable telemetry for this session, tearing down the network thread if it has
# already started. Idempotent. Called by HotzonePlayer for the runtime paths that
# _detect_replay_mode() can't see at autoload time — chiefly the Android deep link,
# which change_scene()s into HotzonePlayer after ANNAV2._ready() already ran.
func set_replay_mode(enabled: bool = true) -> void:
	if not enabled or _replay_mode:
		return
	_replay_mode = true
	if _net_thread:
		_net_thread.stop()
	print("[ANNAV2] Replay mode set at runtime — telemetry stopped for this session.")

func set_telemetry_enabled(enabled: bool) -> void:
	if _replay_mode or enabled == _telemetry_enabled:
		return
	_telemetry_enabled = enabled
	if not enabled:
		if _net_thread:
			_net_thread.stop()
		print("[ANNAV2] Telemetry disabled by user preference.")
		return
	if _net_thread:
		_net_thread.start(_command_queue, _player_id, _session_id, _build_info.get("game_version", Constants.GAME_VERSION))
	print("[ANNAV2] Telemetry enabled by user preference.")

func _init_capture_from_env():
	# Opt-in local capture for headless telemetry analysis. Never required for the
	# game to run; defaults keep capture off so normal sessions are unaffected.
	if OS.get_environment("ANNA_V2_CAPTURE") in ["1", "true", "yes", "on"]:
		_capture_enabled = true
	var dump_env = OS.get_environment("ANNA_V2_CAPTURE_DUMP")
	if dump_env != "":
		_capture_dump_path = dump_env
	var max_env = OS.get_environment("ANNA_V2_CAPTURE_MAX")
	if max_env.is_valid_integer():
		_capture_max = int(max(1, int(max_env)))

# True when this process is a hotzone playback viewer. Checks the cmdline scene
# arg (used by native launch, the web shell's engineConfig.args, and the Android
# deep link) plus, on web, the shell's OdiseaShell.is_replaying flag.
func _detect_replay_mode() -> bool:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			if "HotzonePlayer" in args[i + 1]:
				return true
		elif args[i] == "--replay-file" or args[i] == "--replay-scene":
			return true
	if OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		var js = JavaScript.get_interface("OdiseaShell")
		if js != null and js.is_replaying:
			return true
	return false

func _exit_tree():
	if _replay_mode:
		return
	# Auto-dump on shutdown so headless runs always leave a JSON artifact behind.
	if _capture_enabled and _capture_dump_path != "" and _capture_count > 0:
		dump_telemetry_json(_capture_dump_path)
	if _net_thread:
		_net_thread.stop()

func _notification(what):
	# Window focus drives the idle gate + the `unfocused` heartbeat flag. Works on
	# desktop and HTML5 (Godot maps browser tab blur to the same notifications).
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		_window_focused = false
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		_window_focused = true
		# Send one prompt heartbeat on return so the dashboard updates immediately.
		_last_telemetry_ms = 0

# True while the session has nothing worth reporting: pause menu open (PauseManager
# also pauses on focus loss) or window backgrounded. Automated runs are exempt:
# headless/RL sessions have no window manager to give them focus and must keep
# reporting. Evaluated every frame, so it stays free of OS calls (see _automated_run).
func _is_idle() -> bool:
	if _automated_run:
		return false
	return not _window_focused or _is_tree_paused()

func _is_tree_paused() -> bool:
	var tree = get_tree()
	return tree != null and tree.paused

func _detect_automated_run() -> bool:
	if OS.has_feature("Server"):
		return true
	if OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]:
		return true
	# Escape hatch for tooling that drives an unfocused window and still needs a live
	# telemetry stream (agent runs, perf capture over alt-tab).
	if OS.get_environment("ANNA_V2_ALWAYS_STREAM") in ["1", "true", "yes", "on"]:
		return true
	return false

func _process(_delta):
	# Replay viewer: no network thread was started, so there is nothing to tick.
	if _replay_mode or not _telemetry_enabled:
		return

	if _perf_profiling_enabled:
		_perf_monitor.profiling_start("ANNAV2")

	if _is_web_thread:
		_net_thread._main_thread_tick()

	var idle = _is_idle()
	if idle != _telemetry_idle:
		_telemetry_idle = idle
		if idle:
			# One final sample carrying paused/unfocused so the dashboard shows why
			# the stream stopped, then silence the heartbeats (interval 0).
			_update_telemetry()
			_net_thread.flush_heartbeat()
			_net_thread.update_heartbeat_params(0, 3)
		else:
			# Resume with an immediate gather + heartbeat.
			_last_telemetry_ms = 0

	var now = OS.get_ticks_msec()
	if not _telemetry_idle and now - _last_telemetry_ms >= TELEMETRY_INTERVAL_MS:
		_last_telemetry_ms = now
		_update_telemetry()

	var commands = _command_queue.pop_all()
	for cmd in commands:
		call_deferred("_execute_command", cmd)

	if _perf_profiling_enabled:
		_perf_monitor.profiling_end("ANNAV2")

func _get_proc_counts() -> Dictionary:
	var now = OS.get_ticks_msec()
	if now - _last_proc_count_ms < PROC_COUNT_INTERVAL_MS:
		return _cached_proc_counts
	_last_proc_count_ms = now
	var scene = get_tree().current_scene
	if scene == null:
		return _cached_proc_counts
	var physics_count = 0
	var process_count = 0
	var stack := [scene]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node.is_physics_processing():
			physics_count += 1
		if node.is_processing():
			process_count += 1
		for child in node.get_children():
			stack.push_back(child)
	_cached_proc_counts = {"physics": physics_count, "process": process_count}
	return _cached_proc_counts

var _debug_toggled_nodes := []

# Diagnostico temporal FD-270: apaga/prende _physics_process y _process de TODOS
# los nodos de la escena actual de un tirón, para bisectar si el costo fijo por
# tick esta en scripts de escena (69 nodos con physics activo) o en el motor.
func debug_toggle_all_scene_processing(enable: bool) -> Dictionary:
	var scene = get_tree().current_scene
	if scene == null:
		return {"error": "no_scene"}
	if not enable:
		_debug_toggled_nodes.clear()
		var stack := [scene]
		var count = 0
		while not stack.empty():
			var node: Node = stack.pop_back()
			var was_physics = node.is_physics_processing()
			var was_process = node.is_processing()
			if was_physics or was_process:
				_debug_toggled_nodes.append([weakref(node), was_physics, was_process])
				if was_physics:
					node.set_physics_process(false)
				if was_process:
					node.set_process(false)
				count += 1
			for child in node.get_children():
				stack.push_back(child)
		return {"disabled": count}
	else:
		var restored = 0
		for entry in _debug_toggled_nodes:
			var wr = entry[0]
			var node = wr.get_ref()
			if node != null and is_instance_valid(node):
				if entry[1]:
					node.set_physics_process(true)
				if entry[2]:
					node.set_process(true)
				restored += 1
		_debug_toggled_nodes.clear()
		return {"restored": restored}

# Como debug_toggle_all_scene_processing pero solo sobre nodos cuyo script
# (por resource_path) contiene alguno de los substrings dados, para bisectar
# CUAL tipo de componente pesa sin tener que ubicar rutas de nodo a mano.
func debug_toggle_by_script_match(substrings: Array, enable: bool) -> Dictionary:
	var scene = get_tree().current_scene
	if scene == null:
		return {"error": "no_scene"}
	if not enable:
		_debug_toggled_nodes.clear()
		var stack := [scene]
		var count = 0
		var by_match := {}
		while not stack.empty():
			var node: Node = stack.pop_back()
			var scr = node.get_script()
			if scr != null:
				var path = String(scr.resource_path)
				var matched = false
				for s in substrings:
					if path.find(String(s)) != -1:
						matched = true
						break
				if matched:
					var was_physics = node.is_physics_processing()
					var was_process = node.is_processing()
					if was_physics or was_process:
						_debug_toggled_nodes.append([weakref(node), was_physics, was_process])
						if was_physics:
							node.set_physics_process(false)
						if was_process:
							node.set_process(false)
						count += 1
						by_match[path] = by_match.get(path, 0) + 1
			for child in node.get_children():
				stack.push_back(child)
		return {"disabled": count, "by_script": by_match}
	else:
		var restored = 0
		for entry in _debug_toggled_nodes:
			var wr = entry[0]
			var node = wr.get_ref()
			if node != null and is_instance_valid(node):
				if entry[1]:
					node.set_physics_process(true)
				if entry[2]:
					node.set_process(true)
				restored += 1
		_debug_toggled_nodes.clear()
		return {"restored": restored}

# Lista todos los scripts distintos con al menos un nodo procesando, y cuántos
# nodos de ese script lo hacen. Para ver de un vistazo qué componente domina antes
# de bisectar con debug_toggle_by_script_match.
func debug_list_processing_scripts() -> Dictionary:
	var scene = get_tree().current_scene
	if scene == null:
		return {"error": "no_scene"}
	var counts := {}
	var stack := [scene]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node.is_physics_processing() or node.is_processing():
			var scr = node.get_script()
			var key = String(scr.resource_path) if scr != null else "<no_script:%s>" % node.get_class()
			counts[key] = counts.get(key, 0) + 1
		for child in node.get_children():
			stack.push_back(child)
	return counts

func _update_telemetry():
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	
	# Keep full telemetry payloads, but do not force a faster network heartbeat
	# than the main-thread gather cadence.
	var interval_ms = TELEMETRY_INTERVAL_MS
	var tier = 3
		
	_net_thread.update_heartbeat_params(interval_ms, tier)

	var player = SessionManager.player
	var player_data = {
		"position": [0, 0, 0],
		"velocity": [0, 0, 0],
		"yaw": 0.0,
		"pitch": 0.0,
		"roll": 0.0,
		"mode": "standard",
		"scene": "",
		"zone": "",
		"tick": 0,
		"fps": fps,
		"focused": _window_focused,
		"paused": _is_tree_paused(),
		"memory_mb": _get_memory_mb()
	}

	if is_instance_valid(player):
		var pos = player.global_transform.origin
		player_data["position"] = [pos.x, pos.y, pos.z]
		if "velocity" in player:
			var vel = player.velocity
			player_data["velocity"] = [vel.x, vel.y, vel.z]
		if "yaw" in player: player_data["yaw"] = player.yaw
		if "pitch" in player: player_data["pitch"] = player.pitch
		if "roll" in player: player_data["roll"] = player.get("roll") if "roll" in player else 0.0

	if get_tree().current_scene:
		var scene_name = get_tree().current_scene.filename.get_file().get_basename()
		if scene_name == "":
			scene_name = get_tree().current_scene.name # Fallback para escenas no guardadas o dinamicas
		player_data["scene"] = scene_name
		
		if get_tree().current_scene.has_meta("zone"):
			player_data["zone"] = get_tree().current_scene.get_meta("zone")

	player_data["tick"] = Engine.get_idle_frames() # Or physics frames if preferred

	var proc_counts = _get_proc_counts()
	player_data["perf"] = {
		"dc": Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
		"obj": Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME),
		"vtx": Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"phys_proc": proc_counts.physics,
		"proc": proc_counts.process
	}

	# Merge controller-registered custom data points (e.g. jump_count, state flags)
	for k in _custom_points:
		player_data[k] = _custom_points[k]

	_net_thread.update_telemetry({"player": player_data})

	if _capture_enabled:
		var frame = player_data.duplicate(true)
		frame["t_msec"] = OS.get_ticks_msec()
		if _capture_buffer.size() != _capture_max:
			_capture_buffer.resize(_capture_max)
		_capture_buffer[_capture_head] = frame
		_capture_head = (_capture_head + 1) % _capture_max
		_capture_count = min(_capture_count + 1, _capture_max)

func _execute_command(cmd: Dictionary):
	var action = cmd.get("action")
	var args = cmd.get("args", {})
	var id = cmd.get("id", "unknown")

	print("[ANNAV2] Executing command: ", action, " id: ", id)

	if not _can_execute_remote_command(action, bool(cmd.get("from_central", true))):
		_send_response(id, false, {"error": "command not available in release build"})
		return

	if action == "inspect_node":
		_cmd_inspect_node(id, args)
	elif action == "set_property":
		_cmd_set_property(id, args)
	elif action == "execute_script":
		_cmd_execute_script(id, args)
	elif action == "spawn_scene":
		_cmd_spawn_scene(id, args)
	elif action == "reload_resource":
		_cmd_reload_resource(id, args)
	elif action == "screenshot":
		_cmd_screenshot(id, args)
	elif action == "teleport_player":
		_cmd_teleport_player(id, args)
	elif action == "reload_pck":
		_cmd_reload_pck(id, args)
	else:
		_send_response(id, false, {"error": "unknown action: " + str(action)})

# Gating has two axes: the build, and who is asking.
#
#   debug build / editor      -> everything (dev machine, unchanged behaviour)
#   release + local peer      -> inspect_node, screenshot (a developer attached a peer
#                                to an exported build on purpose)
#   release + remote central  -> nothing
#
# The last row is the point: a store build (iOS/macOS release) must not let the central
# capture its viewport or walk its live scene tree. Those two commands used to be allowed
# unconditionally, which made every shipped release remotely screenshot-able.
func _can_execute_remote_command(action: String, from_central: bool = true) -> bool:
	if OS.is_debug_build() or OS.has_feature("editor"):
		return true
	if from_central:
		return false
	return action in ["inspect_node", "screenshot"]

func _find_expected_sha256(artifact_id: String) -> String:
	var f = File.new()

	# 1. Check sidecar file (highest priority for manual/dev overrides)
	var sidecar_path = "user://updates/packages/" + artifact_id + ".json"
	if f.file_exists(sidecar_path):
		if f.open(sidecar_path, File.READ) == OK:
			var res = JSON.parse(f.get_as_text())
			f.close()
			if res.error == OK and typeof(res.result) == TYPE_DICTIONARY:
				var sha = res.result.get("sha256", "")
				if sha != "": return sha

	# 2. Check update state files
	var state_files = [
		"user://updates/state.json",
		"user://updates/pending_boot.json",
		"user://updates/confirmed_boot.json"
	]

	for path in state_files:
		if f.file_exists(path):
			if f.open(path, File.READ) == OK:
				var res = JSON.parse(f.get_as_text())
				f.close()
				if res.error == OK:
					var sha = _extract_sha256_recursive(res.result, artifact_id)
					if sha != "": return sha

	return ""

func _extract_sha256_recursive(data, artifact_id: String) -> String:
	if typeof(data) == TYPE_DICTIONARY:
		if data.get("artifact_id") == artifact_id and data.has("sha256"):
			return str(data["sha256"])
		for key in data:
			var res = _extract_sha256_recursive(data[key], artifact_id)
			if res != "": return res
	elif typeof(data) == TYPE_ARRAY:
		for item in data:
			var res = _extract_sha256_recursive(item, artifact_id)
			if res != "": return res
	return ""

func _send_response(id, ok, data):
	var resp = {
		"type": "command_response",
		"id": id,
		"ok": ok
	}
	for k in data:
		resp[k] = data[k]
	_net_thread.send_command_response(resp)

# --- Commands ---

func _cmd_inspect_node(id, args):
	var path = args.get("path")
	var node = get_node_or_null(path)
	if not node:
		_send_response(id, false, {"error": "node not found: " + str(path)})
		return

	var result = {
		"name": node.name,
		"type": node.get_class(),
		"children_count": node.get_child_count()
	}

	if node is Spatial:
		var t = node.global_transform
		result["position"] = [t.origin.x, t.origin.y, t.origin.z]
		var r = t.basis.get_euler()
		result["rotation"] = [r.x, r.y, r.z]
		var s = t.basis.get_scale()
		result["scale"] = [s.x, s.y, s.z]

	_send_response(id, true, {"result": result})

func _cmd_set_property(id, args):
	var path = args.get("path")
	var property = args.get("property")
	var value = args.get("value")

	var node = get_node_or_null(path)
	if not node:
		_send_response(id, false, {"error": "node not found: " + str(path)})
		return

	node.set(property, value)
	_send_response(id, true, {})

func _cmd_execute_script(id, args):
	var script_text = args.get("script")
	var validation_error := _validate_remote_script(script_text)
	if validation_error != "":
		_send_response(id, false, {"error": validation_error})
		return

	var script = GDScript.new()
	# Extend Node and run from a node attached to the tree, so the script can use get_node(),
	# get_tree(), SceneManager, etc. A bare Reference has no tree access (get_node/get_tree
	# don't exist on it) and even `get_tree().x` fails to compile with ERR_PARSE_ERROR (43).
	script.set_source_code("extends Node\nfunc run():\n" + _indent_code(script_text))
	var err = script.reload()
	if err != OK:
		_send_response(id, false, {"error": "script compilation error: " + str(err)})
		return

	var runner = Node.new()
	runner.set_script(script)
	add_child(runner)  # ANNAV2 is an autoload under /root, so the runner is in the tree
	var result = null
	var run_err = null
	if runner.has_method("run"):
		result = runner.call("run")
	else:
		run_err = "script has no run() body"
	runner.queue_free()
	if run_err != null:
		_send_response(id, false, {"error": run_err})
	else:
		_send_response(id, true, {"result": _json_safe_value(result)})

func _validate_remote_script(script_text) -> String:
	if typeof(script_text) != TYPE_STRING:
		return "script must be a string"
	if script_text.length() > 12000:
		return "script too long"
	var stripped := String(script_text).strip_edges()
	if stripped == "":
		return "script is empty"
	var allow_blocks := OS.get_environment("ODISEA_TELEMETRY_ALLOW_SCRIPT_BLOCKS") in ["1", "true", "yes", "on"]
	if not allow_blocks and stripped.find("\n") != -1:
		return "multi-line execute_script is disabled; use /eval expressions or set ODISEA_TELEMETRY_ALLOW_SCRIPT_BLOCKS=1"
	var risky_tokens = [
		"\nfunc ",
		" func ",
		"\nclass ",
		" class ",
		"\nclass_name ",
		" class_name ",
		"\nextends ",
		" extends ",
		"\nyield(",
		" yield(",
		"\nyield ",
		" yield ",
		"\nwhile ",
		" while ",
		"\nfor ",
		" for ",
		"\nmatch ",
		" match ",
		"\nload(",
		" load(",
		"\npreload(",
		" preload(",
		"\ncall_deferred(",
		" call_deferred(",
		"\nqueue_free(",
		" queue_free(",
		"\nfree(",
		" free("
	]
	var padded := "\n" + stripped + "\n"
	for token in risky_tokens:
		if padded.find(token) != -1:
			return "unsupported remote script token: " + token.strip_edges()
	return ""

func _json_safe_value(value, depth: int = 0):
	if depth > 4:
		return "<max_depth>"
	var t := typeof(value)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_NODE_PATH:
			return String(value)
		TYPE_OBJECT:
			if value is Node:
				return {"node_path": String(value.get_path()), "name": value.name, "class": value.get_class()}
			if value is Resource:
				return {"resource_path": value.resource_path, "class": value.get_class()}
			return str(value)
		TYPE_ARRAY:
			var out := []
			for item in value:
				out.append(_json_safe_value(item, depth + 1))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for key in value.keys():
				out[str(key)] = _json_safe_value(value[key], depth + 1)
			return out
		_:
			return str(value)

func _indent_code(code: String) -> String:
	var indented = ""
	for line in code.split("\n"):
		indented += "\t" + line + "\n"
	return indented

func _cmd_spawn_scene(id, args):
	var scene_path = args.get("scene_path")
	var pos_arr = args.get("position", [0, 0, 0])

	var scene = load(scene_path)
	if not scene:
		_send_response(id, false, {"error": "failed to load scene: " + str(scene_path)})
		return

	var inst = scene.instance()
	if inst is Spatial:
		inst.global_transform.origin = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])

	get_tree().current_scene.add_child(inst)
	_send_response(id, true, {"path": str(inst.get_path())})

func _cmd_reload_resource(id, args):
	var path = args.get("path")
	var res = load(path)
	if res:
		res.reload_from_file()
		_send_response(id, true, {})
	else:
		_send_response(id, false, {"error": "resource not found: " + str(path)})

func _cmd_screenshot(id, _args):
	var pause_layer = get_tree().root.get_node_or_null("PauseMenuLayer")
	var pause_was_visible := false
	var should_restore_pause := false
	if pause_layer and is_instance_valid(pause_layer) and pause_layer is CanvasItem:
		pause_was_visible = pause_layer.visible
		if pause_was_visible:
			pause_layer.visible = false
			should_restore_pause = true

	yield(get_tree(), "idle_frame")
	yield(VisualServer, "frame_post_draw")

	var viewport = get_viewport()
	var tex = viewport.get_texture()
	var img = tex.get_data()
	img.flip_y()

	var buffer = img.save_png_to_buffer()
	var b64 = Marshalls.raw_to_base64(buffer)

	if should_restore_pause and pause_layer and is_instance_valid(pause_layer):
		pause_layer.visible = pause_was_visible

	_send_response(id, true, {"result": b64})

func _cmd_teleport_player(id, args):
	var pos_arr = args.get("position")
	var yaw = args.get("yaw")

	var player = SessionManager.player
	if not is_instance_valid(player):
		_send_response(id, false, {"error": "player not found"})
		return

	if pos_arr:
		player.global_transform.origin = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	if yaw != null:
		player.yaw = yaw

	_send_response(id, true, {})

func _cmd_reload_pck(id, args):
	if not (OS.is_debug_build() or OS.has_feature("editor")):
		_send_response(id, false, {"error": "reload_pck only available in debug/editor builds"})
		return

	if args.has("url"):
		_send_response(id, false, {"error": "reload_pck no longer accepts URLs for security reasons"})
		return

	var artifact_id = args.get("artifact_id")
	if not artifact_id or artifact_id == "":
		_send_response(id, false, {"error": "missing artifact_id"})
		return

	var pck_path = "user://updates/packages/" + artifact_id + ".pck"
	var f = File.new()
	if not f.file_exists(pck_path):
		_send_response(id, false, {"error": "pck not found in local updates: " + pck_path})
		return

	var expected_sha = _find_expected_sha256(artifact_id)
	if expected_sha == "":
		_send_response(id, false, {"error": "no verified SHA-256 found for artifact: " + artifact_id})
		return

	var actual_sha = f.get_sha256(pck_path)
	if actual_sha.to_lower() != expected_sha.to_lower():
		_send_response(id, false, {
			"error": "SHA-256 mismatch",
			"expected": expected_sha,
			"actual": actual_sha
		})
		return

	print("[ANNAV2] Loading verified PCK: ", pck_path)
	var success = ProjectSettings.load_resource_pack(pck_path)
	if not success:
		_send_response(id, false, {"error": "failed to load resource pack"})
		return

	var target_scene = args.get("scene")
	if target_scene and target_scene != "":
		print("[ANNAV2] Changing scene to: ", target_scene)
		var change_err = get_tree().change_scene(target_scene)
		if change_err != OK:
			_send_response(id, false, {"error": "failed to change scene: " + str(change_err)})
			return
	else:
		var current = get_tree().current_scene.filename
		if current == "":
			current = "res://scenes/Main.tscn"

		print("[ANNAV2] Reloading current scene: ", current)
		var reload_err = get_tree().change_scene(current)
		if reload_err != OK:
			_send_response(id, false, {"error": "failed to reload scene: " + str(reload_err)})
			return

	_send_response(id, true, {"message": "verified pck loaded and scene reloaded"})

# --- Telemetry capture API (local, bridge-independent) ---
# Safe to call from OYS (ANNA_ENABLE/ANNA_DISABLE/ANNA_DUMP) or directly from
# controllers via the ANNAV2 autoload singleton.

func set_capture_enabled(enabled: bool) -> void:
	_capture_enabled = enabled
	print("[ANNAV2] Telemetry capture ", "ENABLED" if enabled else "DISABLED")

func is_capture_enabled() -> bool:
	return _capture_enabled

func clear_capture() -> void:
	_capture_head = 0
	_capture_count = 0

# Register/override a custom telemetry data point merged into every captured frame.
# e.g. ANNAV2.register_telemetry_point("jump_count", 3)
func register_telemetry_point(key: String, value) -> void:
	_custom_points[key] = value

# Alias of register_telemetry_point for grouped/structured data (e.g. a sub-dict).
# NOTE: values must be JSON-serializable (no raw Vector3/Basis) — convert to arrays/floats.
func add_telemetry_data(key: String, value) -> void:
	register_telemetry_point(key, value)

func clear_telemetry_point(key: String) -> void:
	_custom_points.erase(key)

func get_capture_log() -> Array:
	return _capture_frames_in_order(true)

# Returns captured frames oldest-first. The buffer is circular, so we walk from the
# oldest valid slot. Pass deep=true to deep-copy each frame for safe external mutation.
func _capture_frames_in_order(deep := false) -> Array:
	var out = []
	if _capture_count == 0:
		return out
	var start = (_capture_head - _capture_count + _capture_max) % _capture_max
	for i in range(_capture_count):
		var frame = _capture_buffer[(start + i) % _capture_max]
		out.append(frame.duplicate(true) if deep else frame)
	return out

# Write the captured frames to a JSON file. Returns the resolved path, or "" on failure.
func dump_telemetry_json(path := "") -> String:
	if path == "":
		path = _capture_dump_path
	if path == "":
		path = "user://anna_v2_telemetry_%d.json" % OS.get_unix_time()

	var payload = {
		"player_id": _player_id,
		"session_id": _session_id,
		"game_version": _build_info.get("game_version", Constants.GAME_VERSION),
		"git_commit": _build_info.get("git_commit", ""),
		"build_id": _build_info.get("build_id", ""),
		"build_channel": _build_info.get("build_channel", ""),
		"official_host": _build_info.get("official_host", ""),
		"godot_version": Engine.get_version_info().string,
		"captured_at": OS.get_unix_time(),
		"frame_count": _capture_count,
		"frames": _capture_frames_in_order()
	}

	var f = File.new()
	var err = f.open(path, File.WRITE)
	if err != OK:
		printerr("[ANNAV2] Failed to open telemetry dump path: ", path, " err: ", err)
		return ""
	f.store_string(JSON.print(payload, "  "))
	f.close()
	print("[ANNAV2] Telemetry dumped to ", path, " (", _capture_count, " frames)")
	return path

# --- Helpers ---

func _load_or_create_player_id() -> String:
	var f = File.new()
	if f.file_exists(PLAYER_ID_FILE):
		f.open(PLAYER_ID_FILE, File.READ)
		var id = f.get_as_text().strip_edges()
		f.close()
		if id != "": return id

	var id = _generate_uuid()
	f.open(PLAYER_ID_FILE, File.WRITE)
	f.store_string(id)
	f.close()
	return id

func _generate_uuid() -> String:
	# Simplistic UUID-like string. OS.get_unique_id() is unavailable on HTML5, so skip it
	# there and use the time/random fallback below.
	var unique_id = ""
	if not OS.has_feature("web"):
		unique_id = OS.get_unique_id()
	if unique_id == "" or unique_id == "unknown":
		# Fallback for platforms where unique_id is not reliable
		unique_id = str(OS.get_unix_time()) + str(randi())

	var h = str(unique_id).hash()
	if h == 0:
		h = OS.get_unix_time() + randi()

	return str(OS.get_unix_time()) + "-" + str(h)

func _generate_session_id() -> String:
	# Unique per game session (one per process launch), and stable across bridge
	# reconnections because it's generated once in _ready() and never regenerated.
	# Must NOT collide between two instances on the same machine: OS.get_unique_id()
	# is identical per machine and unix_time is identical within a second, so we mix
	# the microsecond counter (differs per process) with randomize()+randi() entropy.
	randomize()
	var rnd = ""
	for i in range(4):
		rnd += "%08x" % randi()
	return "%d-%d-%s" % [OS.get_unix_time(), OS.get_ticks_usec(), rnd]

func _get_url_param(param_name: String) -> String:
	if not OS.has_feature("web"): return ""
	# In Godot 3.x, OS.get_executable_path() might contain the URL in some exports,
	# but JavaScript.eval is more reliable.
	if not Engine.has_singleton("JavaScript"): return ""
	var js = Engine.get_singleton("JavaScript")
	var res = js.eval("new URLSearchParams(window.location.search).get('" + param_name + "')")
	return str(res) if res != null else ""

func _get_build_meta_value(key: String) -> String:
	# HTML5: read from window.ODISEA_BUILD_META injected by CI
	if OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		var js = Engine.get_singleton("JavaScript")
		var expr = "window.ODISEA_BUILD_META && window.ODISEA_BUILD_META['" + key + "'] || ''"
		var res = js.eval(expr)
		return str(res) if res != null else ""
	# Native: read from build_meta.json next to the executable
	return _get_build_meta_value_from_file(key)

func _is_valid_build_token(token: String) -> bool:
	var value := token.strip_edges()
	if value == "":
		return false
	if value == "ODISEA_TOKEN_CANARY_MISSING":
		return false
	if value == "odisea-dev-insecure":
		return false
	return true

var _build_meta_json_cache: Dictionary = {}

func _get_build_meta_value_from_file(key: String) -> String:
	if _build_meta_json_cache.empty():
		var file: File = File.new()
		# res:// first so the value is embedded in the .pck and behaves
		# identically on every platform (Windows can launch the .exe with a
		# different CWD, so the loose file next to the binary is unreliable).
		var meta_paths := [
			"res://build_meta.json",
			"build_meta.json",
			OS.get_executable_path().get_base_dir().plus_file("build_meta.json")
		]
		for path in meta_paths:
			if file.file_exists(path):
				var err := file.open(path, File.READ)
				if err == OK:
					var text: String = file.get_as_text()
					file.close()
					var parse_result = JSON.parse(text)
					if parse_result.error == OK and typeof(parse_result.result) == TYPE_DICTIONARY:
						_build_meta_json_cache = parse_result.result
						break
		if _build_meta_json_cache.empty():
			_build_meta_json_cache["_loaded"] = false
			return ""
	return str(_build_meta_json_cache.get(key, ""))

func _load_build_info() -> Dictionary:
	var game_version = OS.get_environment("ODISEA_GAME_VERSION")
	if game_version == "":
		game_version = _get_url_param("game_version")
	if game_version == "":
		game_version = _get_build_meta_value("version")
	if game_version == "":
		game_version = Constants.GAME_VERSION

	var git_commit = OS.get_environment("ODISEA_GIT_COMMIT")
	if git_commit == "":
		git_commit = OS.get_environment("GITHUB_SHA")
	if git_commit == "":
		git_commit = _get_url_param("git_commit")
	if git_commit == "":
		git_commit = _get_url_param("commit")
	if git_commit == "":
		git_commit = _get_build_meta_value("commit")

	var build_id = OS.get_environment("ODISEA_BUILD_ID")
	if build_id == "":
		build_id = OS.get_environment("GITHUB_RUN_ID")
	if build_id == "":
		build_id = _get_url_param("build_id")
	if build_id == "":
		build_id = _get_build_meta_value("build_id")

	var build_channel = OS.get_environment("ODISEA_BUILD_CHANNEL")
	if build_channel == "":
		build_channel = _get_url_param("build_channel")
	if build_channel == "":
		build_channel = _get_build_meta_value("channel")
	if build_channel == "":
		build_channel = "dev"

	var official_host = OS.get_environment("ODISEA_OFFICIAL_HOST")
	if official_host == "":
		official_host = _get_url_param("official_host")
	if official_host == "":
		official_host = _get_build_meta_value("officialHost")
	if official_host == "" and OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		var js = Engine.get_singleton("JavaScript")
		official_host = str(js.eval("window.location.hostname || ''"))

	return {
		"game_version": game_version,
		"git_commit": git_commit,
		"build_id": build_id,
		"build_channel": build_channel,
		"official_host": official_host,
		"official_build": official_host != "" or build_channel in ["nightly", "tip", "release"]
	}

func _get_memory_mb() -> float:
	var mem_static: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0
	if mem_static > 0.0:
		return mem_static
	var sm: Node = get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("read_process_memory_mb"):
		var os_mem: float = sm.read_process_memory_mb()
		if os_mem >= 0.0:
			return os_mem
	return 0.0
