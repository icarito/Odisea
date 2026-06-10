extends Node

const PLAYER_ID_FILE := "user://odisea_player_id.txt"
const GAME_VERSION := "0.1.0"
const CAPTURE_DEFAULT_MAX := 36000 # ~10 min at 60 fps; ring buffer caps memory use

var _command_queue_script = preload("res://core_v2/anna/v2/ANNAV2_CommandQueue.gd")
var _thread_script = preload("res://core_v2/anna/v2/ANNAV2_Thread.gd")
var _thread_web_script = preload("res://core_v2/anna/v2/ANNAV2_Thread_Web.gd")

var _command_queue
var _net_thread
var _is_web_thread := false  # true when using ANNAV2_Thread_Web (worker-backed)
var _player_id := ""
var _session_id := ""

# --- Local telemetry capture (bridge-independent; ON by default) ---
var _capture_enabled := true
var _capture_buffer := []
var _capture_max := CAPTURE_DEFAULT_MAX
var _capture_dump_path := ""
# Custom data points registered by controllers; merged into every captured frame
var _custom_points := {}

# Telemetry is gathered at most every TELEMETRY_INTERVAL_MS (decoupled from frame rate).
# The network thread only sends at 10Hz anyway, so gathering at 60Hz was wasted main-thread
# work. Lower the interval for finer local capture; raise it to reduce ANNA's per-frame cost.
const TELEMETRY_INTERVAL_MS := 50 # ~20Hz
var _last_telemetry_ms := 0

func _ready():
	_player_id = _load_or_create_player_id()
	_session_id = _generate_uuid()

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
		_net_thread._central_url = "ws://" + central_override + "/ws"
	var scheme_override = _get_url_param("scheme")
	if scheme_override != "":
		_net_thread.set_scheme(scheme_override)
	if _get_url_param("nocentral") in ["1", "true", "yes", "on"]:
		_net_thread._central_enabled = false
	# HTML5 desde HTTPS: forzar ws:// sin TLS porque el central no tiene certificado
	if OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		_net_thread.set_scheme("ws")

	_net_thread.start(_command_queue, _player_id, _session_id, GAME_VERSION)
	_init_capture_from_env()
	print("[ANNAV2] Initialized. PlayerID: ", _player_id, " SessionID: ", _session_id)

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

func _exit_tree():
	# Auto-dump on shutdown so headless runs always leave a JSON artifact behind.
	if _capture_enabled and _capture_dump_path != "" and not _capture_buffer.empty():
		dump_telemetry_json(_capture_dump_path)
	if _net_thread:
		_net_thread.stop()

func _process(_delta):
	if _is_web_thread:
		_net_thread._main_thread_tick()

	var now = OS.get_ticks_msec()
	if now - _last_telemetry_ms >= TELEMETRY_INTERVAL_MS:
		_last_telemetry_ms = now
		_update_telemetry()

	var commands = _command_queue.pop_all()
	for cmd in commands:
		call_deferred("_execute_command", cmd)

func _update_telemetry():
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	
	# Forzamos tier 3 siempre para garantizar que el dashboard de observabilidad 
	# reciba todos los datos (posicion, escena, modo, etc.) sin importar los FPS.
	# El throttling por FPS causaba que se dejaran de enviar datos criticos cuando el juego bajaba de 30 FPS.
	var interval_ms = 100
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
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1024 / 1024
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

	# Merge controller-registered custom data points (e.g. jump_count, state flags)
	for k in _custom_points:
		player_data[k] = _custom_points[k]

	_net_thread.update_telemetry({"player": player_data})

	if _capture_enabled:
		var frame = player_data.duplicate(true)
		frame["t_msec"] = OS.get_ticks_msec()
		_capture_buffer.append(frame)
		if _capture_buffer.size() > _capture_max:
			_capture_buffer.pop_front()

func _execute_command(cmd: Dictionary):
	var action = cmd.get("action")
	var args = cmd.get("args", {})
	var id = cmd.get("id", "unknown")

	print("[ANNAV2] Executing command: ", action, " id: ", id)

	if not _can_execute_remote_command(action):
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
	else:
		_send_response(id, false, {"error": "unknown action: " + str(action)})

func _can_execute_remote_command(action: String) -> bool:
	# Telemetry and harmless info commands are always allowed
	if action in ["inspect_node", "screenshot"]:
		return true
	return OS.is_debug_build() or OS.has_feature("editor")

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
	var script = GDScript.new()
	# In some Godot 3 versions, GDScript.new() might not work as expected for source loading.
	# But .new() is the standard way to create a script resource.
	script.set_source_code("func run():\n" + _indent_code(script_text))
	var err = script.reload()
	if err != OK:
		_send_response(id, false, {"error": "script compilation error: " + str(err)})
		return

	var obj = Reference.new()
	obj.set_script(script)
	var result = obj.call("run")
	_send_response(id, true, {"result": result})

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
	yield(get_tree(), "idle_frame")
	yield(VisualServer, "frame_post_draw")

	var viewport = get_viewport()
	var tex = viewport.get_texture()
	var img = tex.get_data()
	img.flip_y()

	var buffer = img.save_png_to_buffer()
	var b64 = Marshalls.raw_to_base64(buffer)
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

# --- Telemetry capture API (local, bridge-independent) ---
# Safe to call from OYS (ANNA_ENABLE/ANNA_DISABLE/ANNA_DUMP) or directly from
# controllers via the ANNAV2 autoload singleton.

func set_capture_enabled(enabled: bool) -> void:
	_capture_enabled = enabled
	print("[ANNAV2] Telemetry capture ", "ENABLED" if enabled else "DISABLED")

func is_capture_enabled() -> bool:
	return _capture_enabled

func clear_capture() -> void:
	_capture_buffer.clear()

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
	return _capture_buffer.duplicate(true)

# Write the captured frames to a JSON file. Returns the resolved path, or "" on failure.
func dump_telemetry_json(path := "") -> String:
	if path == "":
		path = _capture_dump_path
	if path == "":
		path = "user://anna_v2_telemetry_%d.json" % OS.get_unix_time()

	var payload = {
		"player_id": _player_id,
		"session_id": _session_id,
		"game_version": GAME_VERSION,
		"godot_version": Engine.get_version_info().string,
		"captured_at": OS.get_unix_time(),
		"frame_count": _capture_buffer.size(),
		"frames": _capture_buffer
	}

	var f = File.new()
	var err = f.open(path, File.WRITE)
	if err != OK:
		printerr("[ANNAV2] Failed to open telemetry dump path: ", path, " err: ", err)
		return ""
	f.store_string(JSON.print(payload, "  "))
	f.close()
	print("[ANNAV2] Telemetry dumped to ", path, " (", _capture_buffer.size(), " frames)")
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

func _get_url_param(param_name: String) -> String:
	if not OS.has_feature("web"): return ""
	# In Godot 3.x, OS.get_executable_path() might contain the URL in some exports,
	# but JavaScript.eval is more reliable.
	if not Engine.has_singleton("JavaScript"): return ""
	var js = Engine.get_singleton("JavaScript")
	var res = js.eval("new URLSearchParams(window.location.search).get('" + param_name + "')")
	return str(res) if res != null else ""
