extends Reference

const PEER_PORT := 4999
const RECONNECT_INTERVAL_MS := 2000
const DEV_DEFAULT_TOKEN := "odisea-dev-insecure"
const DEFAULT_CENTRAL := "odisea.educa.juegos"

var _stop_thread := false

var _command_queue
var _is_connected := false
var _was_connected := false  # detect state transitions
var _peer_url := ""
var _central_url := "wss://" + DEFAULT_CENTRAL + "/ws"
var _bridge_token := DEV_DEFAULT_TOKEN
var _central_enabled := true

var player_id := ""
var session_id := ""
var game_version := "0.1.0"
var git_commit := ""
var build_id := ""
var build_channel := "dev"
var official_host := ""
var official_build := false

var _last_telemetry := {}
var _heartbeat_counter := 0
var _heartbeat_interval_ms := 100
var _throttle_tier := 3
var _force_heartbeat := false
var _last_heartbeat := 0
var _last_reconnect := 0
var _reconnect_attempts := 0
const MAX_RECONNECT_INTERVAL_MS := 5000

func set_scheme(scheme: String):
	if _central_url.begins_with("ws://") and scheme == "wss":
		_central_url = "wss://" + _central_url.substr(5)
	elif _central_url.begins_with("wss://") and scheme == "ws":
		_central_url = "ws://" + _central_url.substr(6)

func update_heartbeat_params(interval_ms: int, tier: int):
	_heartbeat_interval_ms = interval_ms
	_throttle_tier = tier

# Send the current telemetry once on the next tick, ignoring the interval. Used to
# push a final sample before the heartbeats are silenced (interval 0).
func flush_heartbeat():
	_force_heartbeat = true

func set_build_info(info: Dictionary):
	game_version = info.get("game_version", game_version)
	git_commit = info.get("git_commit", "")
	build_id = info.get("build_id", "")
	build_channel = info.get("build_channel", "dev")
	official_host = info.get("official_host", "")
	official_build = info.get("official_build", false)

func _init():
	# Web can't safely embed the ingest token (it'd be visible in the browser), so
	# the official-ingest path is handled via the build-meta token / ?token= URL
	# param elsewhere. Here we only honor an explicit env token, then dev fallback.
	_bridge_token = OS.get_environment("ODISEA_BRIDGE_TOKEN")
	if _bridge_token == "":
		_bridge_token = OS.get_environment("ODISEA_CENTRAL_INGEST_TOKEN")
	if _bridge_token == "":
		_bridge_token = DEV_DEFAULT_TOKEN
	var central_env = OS.get_environment("ANNA_V2_CENTRAL")
	if central_env == "":
		central_env = DEFAULT_CENTRAL
	_central_url = "wss://" + central_env + "/ws"
	_central_enabled = not (OS.get_environment("ANNA_V2_NO_CENTRAL") in ["1", "true", "yes", "on"])

func start(command_queue, p_id, s_id, g_ver):
	_stop_thread = false
	_command_queue = command_queue
	player_id = p_id
	session_id = s_id
	game_version = g_ver
	_inject_bridge()
	print("[ANNAV2-Web] Worker-backed thread started (main-thread poll, WebSocket in Web Worker)")

func stop():
	_stop_thread = true
	_eval("ANNAV2_WS_Bridge.disconnect()")

func update_telemetry(data: Dictionary):
	_last_telemetry = data

func send_command_response(response: Dictionary):
	_send_json(response)

# Called every frame from ANNAV2._process().
func _main_thread_tick():
	if _stop_thread:
		return

	# OS.get_ticks_msec() may return null on the very first HTML5 frame.
	# Fall back to 0 so the arithmetic doesn't crash with 'int and Nil'.
	var raw = OS.get_ticks_msec()
	var now = raw if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_REAL else 0

	if not _is_connected:
		var backoff = min(MAX_RECONNECT_INTERVAL_MS, RECONNECT_INTERVAL_MS * pow(1.5, _reconnect_attempts))
		var jitter = rand_range(0, 500)
		if now - _last_reconnect > (backoff + jitter):
			_attempt_connection()
			_last_reconnect = now
			_reconnect_attempts += 1
	else:
		_reconnect_attempts = 0
		var interval = _heartbeat_interval_ms
		var tier = _throttle_tier
		var force = _force_heartbeat
		_force_heartbeat = false
		# interval == 0 means the session went idle (paused/tab in background): stay
		# connected for commands, but stop streaming heartbeats.
		if force or (interval > 0 and now - _last_heartbeat > interval):
			_send_heartbeat(tier)
			_last_heartbeat = now

	_poll_worker()

# ---- Bridge to Web Worker (via JavaScript.eval) ----
# The bridge JS is injected at runtime via JavaScript.eval() so it works in
# both editor-run and exported builds (no custom HTML shell dependency).

func _inject_bridge():
	if not Engine.has_singleton("JavaScript"):
		return
	Engine.get_singleton("JavaScript").eval("""
(function(){
if (window.ANNAV2_WS_Bridge) return;
var w = new Worker(URL.createObjectURL(new Blob([[
"var ws=null,pi=[];",
"self.onmessage=function(e){var m=e.data;",
"switch(m.cmd){",
"case'connect':if(ws){ws.close();}pi.length=0;",
"try{ws=new WebSocket(m.url);ws.binaryType='arraybuffer';}",
"catch(err){self.postMessage({cmd:'state',state:3});return;}",
"ws.onopen=function(){self.postMessage({cmd:'state',state:1});};",
"ws.onclose=function(){self.postMessage({cmd:'state',state:3});ws=null;};",
"ws.onerror=function(){self.postMessage({cmd:'state',state:3});};",
"ws.onmessage=function(ev){",
"var t=typeof ev.data==='string'?ev.data:new TextDecoder('utf-8').decode(new Uint8Array(ev.data));",
"pi.push(t);};break;",
"case'disconnect':if(ws){ws.close();ws=null;}pi.length=0;self.postMessage({cmd:'state',state:3});break;",
"case'send':if(ws&&ws.readyState===WebSocket.OPEN)ws.send(m.text);break;",
"case'poll':var n=m.max||16;self.postMessage({cmd:'pollResult',messages:pi.splice(0,n)});break;",
"case'getState':self.postMessage({cmd:'state',state:ws?ws.readyState:3});break;",
"}}"
].join('\\n')],{type:'application/javascript'})));
var iq=[],cs=3;
w.onmessage=function(ev){var m=ev.data;
if(m.cmd==='pollResult'&&m.messages&&m.messages.length)iq.push.apply(iq,m.messages);
if(m.cmd==='state')cs=m.state;};
window.ANNAV2_WS_Bridge={
connect:function(url){iq.length=0;cs=0;w.postMessage({cmd:'connect',url:url});},
disconnect:function(){w.postMessage({cmd:'disconnect'});iq.length=0;},
send:function(t){w.postMessage({cmd:'send',text:t});},
poll:function(){w.postMessage({cmd:'poll'});var o=iq.slice();iq.length=0;return o||[];},
getState:function(){w.postMessage({cmd:'getState'});return cs;},
/** Returns browser memory estimate (MB), or -1 if unavailable. */
getBrowserMemMB:function(){
  if(typeof performance!=='undefined'&&performance.memory&&typeof performance.memory.usedJSHeapSize==='number'){
    return performance.memory.usedJSHeapSize/(1024*1024);
  }
  return -1;
}
};
console.log('[ANNAV2-Bridge] Worker injected via GDScript');
})();
""")

func _eval(js_code: String):
	if not Engine.has_singleton("JavaScript"):
		return
	Engine.get_singleton("JavaScript").eval(js_code)

func _attempt_connection():
	if _peer_url == "":
		_peer_url = _discover_peer()

	if _peer_url != "":
		print("[ANNAV2] Attempting to connect to peer: ", _peer_url)
		_eval("ANNAV2_WS_Bridge.connect('" + _peer_url.replace("'", "\\'") + "')")
		_was_connected = false

func _discover_peer() -> String:
	var env_bridge = OS.get_environment("ANNA_V2_BRIDGE")
	if env_bridge != "":
		return "ws://" + env_bridge + "/ws"

	if not _central_enabled:
		return ""
	print("[ANNAV2] HTML5 build: falling back to central: ", _central_url)
	return _central_url

func _poll_worker():
	# Check connection state
	var state = _eval_int("ANNAV2_WS_Bridge.getState()")

	# state: 1=OPEN, others=not connected
	var connected = (state == 1)

	if connected and not _was_connected:
		_is_connected = true
		_was_connected = true
		print("[ANNAV2] Connected to peer (worker-backed)")
		_send_handshake()
	elif not connected and _was_connected:
		_is_connected = false
		_was_connected = false
		print("[ANNAV2] Disconnected from peer (worker-backed)")
	elif not connected:
		_is_connected = false

	# Drain incoming messages from the worker
	var msgs_arr = _eval_array("(function(){ var m = ANNAV2_WS_Bridge.poll(); return JSON.stringify(m); })()")
	if msgs_arr != null:
		for msg_str in msgs_arr:
			if typeof(msg_str) == TYPE_STRING and msg_str != "":
				_process_incoming(msg_str)

func _process_incoming(text: String):
	var result = JSON.parse(text)
	if result.error == OK and typeof(result.result) == TYPE_DICTIONARY:
		var msg = result.result
		var type = msg.get("type")
		if type == "handshake_ack":
			print("[ANNAV2] Handshake ACK received")
		elif type == "command":
			var action = msg.get("action")
			var args = msg.get("args", {})
			var cmd_id = msg.get("id", "unknown")
			# See ANNAV2_Thread._on_data: origin decides what a release build will run.
			# On web the only non-central target is an explicit ?bridge= / ANNA_V2_BRIDGE
			# override, which is a developer attaching a local peer on purpose.
			_command_queue.push({
				"action": action,
				"args": args,
				"id": cmd_id,
				"from_central": _peer_url == _central_url
			})

func _eval_int(js_code: String) -> int:
	if not Engine.has_singleton("JavaScript"): return 3
	var res = Engine.get_singleton("JavaScript").eval(js_code)
	return int(res) if typeof(res) == TYPE_REAL or typeof(res) == TYPE_INT else 3

func _eval_array(js_code: String) -> Array:
	if not Engine.has_singleton("JavaScript"): return []
	var res = Engine.get_singleton("JavaScript").eval(js_code)
	if typeof(res) == TYPE_STRING and res != "":
		var parse_result = JSON.parse(res)
		if parse_result.error == OK and typeof(parse_result.result) == TYPE_ARRAY:
			return parse_result.result
	return []

func _eval_float(js_code: String) -> float:
	if not Engine.has_singleton("JavaScript"): return -1.0
	var res = Engine.get_singleton("JavaScript").eval(js_code)
	if typeof(res) == TYPE_REAL or typeof(res) == TYPE_INT:
		return float(res)
	return -1.0

func _send_json(msg: Dictionary):
	if _is_connected:
		var json_str = JSON.print(msg)
		_eval("ANNAV2_WS_Bridge.send('" + json_str.replace("\\", "\\\\").replace("'", "\\'") + "')")

func _send_handshake():
	var platform = "web"

	var msg = {
		"type": "handshake",
		"platform": platform,
		"player_id": player_id,
		"session_id": session_id,
		"game_version": game_version,
		"git_commit": git_commit,
		"build_id": build_id,
		"build_channel": build_channel,
		"official_host": official_host,
		"official_build": official_build
	}
	if _bridge_token != "":
		msg["token"] = _bridge_token
		msg["peer_id"] = player_id
	_send_json(msg)

func _send_heartbeat(tier: int):
	var player_data = _last_telemetry.get("player", {})

	_heartbeat_counter += 1

	var platform_name = "HTML5"

	var msg = {
		"schema_version": 1,
		"type": "heartbeat",
		"player_id": player_id,
		"session_id": session_id,
		"host": OS.get_name(),
		"godot_version": Engine.get_version_info().string,
		"engine_version": Engine.get_version_info().string,
		"game_version": game_version,
		"git_commit": git_commit,
		"build_id": build_id,
		"build_channel": build_channel,
		"official_host": official_host,
		"official_build": official_build,
		"platform": platform_name,
		"timestamp": OS.get_unix_time()
	}
	# Stamp the token on every heartbeat so the central classifies intake_mode from our
	# own token even when relayed through a peer (otherwise relayed heartbeats inherit
	# the peer's handshake mode). Mirrors the native ANNAV2_Thread heartbeat.
	if _bridge_token != "":
		msg["token"] = _bridge_token

	# En HTML5, Performance.MEMORY_STATIC puede devolver 0 o valores invalidos.
	# Usamos la API del navegador (performance.memory.usedJSHeapSize en Chrome,
	# o -1 si no esta disponible). El bridge JS expone getBrowserMemMB().
	var mem_mb = player_data.get("memory_mb", 0.0)
	if typeof(mem_mb) != TYPE_REAL and typeof(mem_mb) != TYPE_INT:
		mem_mb = 0.0
	if mem_mb <= 0.0:
		# Guard against older HTML shells whose bridge predates getBrowserMemMB:
		# calling a missing method throws and would spam every heartbeat.
		var browser_mem = _eval_float("(window.ANNAV2_WS_Bridge && typeof ANNAV2_WS_Bridge.getBrowserMemMB === 'function') ? ANNAV2_WS_Bridge.getBrowserMemMB() : -1")
		if browser_mem > 0:
			mem_mb = browser_mem

	var player_msg = {
		"fps": player_data.get("fps", 0),
		"position": player_data.get("position", [0, 0, 0]),
		"yaw": player_data.get("yaw", 0.0),
		"pitch": player_data.get("pitch", 0.0),
		"roll": player_data.get("roll", 0.0),
		"scene": player_data.get("scene", "Desconocida"),
		"zone": player_data.get("zone", "Desconocida"),
		"mode": player_data.get("mode", "standard"),
		"tick": player_data.get("tick", 0),
		"memory_mb": mem_mb,
		"velocity": player_data.get("velocity", [0, 0, 0]),
		"focused": player_data.get("focused", true),
		"paused": player_data.get("paused", false),
		"platform": platform_name,
		"transition": player_data.get("transition", {})
	}

	msg["player"] = player_msg
	_send_json(msg)
