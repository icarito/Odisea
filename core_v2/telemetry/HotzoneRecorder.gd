extends Node

# HotzoneRecorder.gd
# Captures sustained low-FPS windows (hotzones) and uploads binary input snapshots for diagnostics.

const PENDING_DIR := "user://pending_hotzones/"
const BINARY_MAGIC := 0x485a4e32 # "HZN2"
const SCHEMA_VERSION := 1

# Configuration
var hotzone_enabled := true
var hotzone_buffer_frames := 300
var hotzone_fps_threshold := 30.0
var hotzone_min_duration := 5.0
var hotzone_cooldown := 60.0
var hotzone_max_captures_per_session := 5
var hotzone_grid_size := 10.0
var snapshot_interval := 100 # Frames between full snapshots in buffer

# State
var _is_testing := false
var _test_fps := 60.0
var _ring_buffer := []
var _head := 0
var _count := 0
var _hotzone_start_msec := 0
var _is_in_hotzone := false
var _last_hotzone_msec := 0
var _capture_count := 0
var _dedup_table := {} # key: "scene:gx:gy" -> timestamp
var _upload_queue := []
var _http_request: HTTPRequest = null
var _is_uploading := false
var _anna_v2: Node = null
var _last_scene_name := ""
var _is_web := false
var _retry_timer := 0.0
var _frames_since_snapshot := 0

func _ready():
	_is_web = OS.has_feature("web")
	_ensure_dir()
	_setup_http()
	call_deferred("_cache_anna_reference")
	if _is_web:
		_inject_worker()

	# Opportunistic startup scan
	call_deferred("_scan_pending_files")
	print("[HotzoneRecorder] Initialized. Web: ", _is_web)

func _cache_anna_reference():
	if has_node("/root/ANNAV2"):
		_anna_v2 = get_node("/root/ANNAV2")
	else:
		print("[HotzoneRecorder] ANNAV2 not found in scene tree yet")

func _ensure_dir():
	var dir = Directory.new()
	if not dir.dir_exists(PENDING_DIR):
		dir.make_dir_recursive(PENDING_DIR)

func _setup_http():
	if _is_web: return
	_http_request = HTTPRequest.new()
	_http_request.use_threads = true
	add_child(_http_request)
	_http_request.connect("request_completed", self, "_on_upload_completed")

func record_frame(input, dt: float):
	if not hotzone_enabled: return

	var fps = _test_fps if _is_testing else Performance.get_monitor(Performance.TIME_FPS)
	var now = OS.get_ticks_msec()

	var scene_name = ""
	var pos = Vector3.ZERO
	var player = SessionManager.player
	if is_instance_valid(player):
		pos = player.global_transform.origin
		if get_tree().current_scene:
			scene_name = get_tree().current_scene.filename.get_file().get_basename()

	# Detect scene change - discard hotzone if it happens across a scene transition
	if scene_name != _last_scene_name:
		if _is_in_hotzone:
			# Discard current hotzone on scene change
			_is_in_hotzone = false
			print("[HotzoneRecorder] Discarding hotzone due to scene change")
		_last_scene_name = scene_name
		_frames_since_snapshot = 0 # Force a snapshot on scene change

	# Store frame in ring buffer
	var frame_data = {
		"input": input.to_dict() if input and input.has_method("to_dict") else {},
		"dt": dt,
		"pos": [pos.x, pos.y, pos.z],
		"fps": fps,
		"t": now
	}

	# Periodically include a full snapshot
	if _frames_since_snapshot <= 0 or _frames_since_snapshot >= snapshot_interval:
		if is_instance_valid(player) and player.has_method("get_full_snapshot"):
			frame_data["snapshot"] = player.get_full_snapshot()
			_frames_since_snapshot = 0
	_frames_since_snapshot += 1

	if _ring_buffer.size() < hotzone_buffer_frames:
		_ring_buffer.append(frame_data)
	else:
		_ring_buffer[_head] = frame_data

	_head = (_head + 1) % hotzone_buffer_frames
	_count = min(_count + 1, hotzone_buffer_frames)

	# Hotzone Detection Logic
	if not _is_in_hotzone:
		if fps < hotzone_fps_threshold and _capture_count < hotzone_max_captures_per_session:
			if now - _last_hotzone_msec > hotzone_cooldown * 1000.0:
				_is_in_hotzone = true
				_hotzone_start_msec = now
				print("[HotzoneRecorder] Potential hotzone started at FPS ", fps)
	else:
		# Already in hotzone
		if fps >= hotzone_fps_threshold:
			# FPS recovered! Check duration
			var duration = (now - _hotzone_start_msec) / 1000.0
			if duration >= hotzone_min_duration:
				_trigger_capture(scene_name, pos, "auto")

			_is_in_hotzone = false
			_last_hotzone_msec = now
		elif (now - _hotzone_start_msec) > 30000: # Max 30s hotzone
			# Give up if it stays low for too long, might be a permanent stall
			_is_in_hotzone = false
			_last_hotzone_msec = now
			print("[HotzoneRecorder] Hotzone timed out (sustained low FPS > 30s)")

func _unhandled_input(event):
	var manual = false
	if event is InputEventKey and event.pressed:
		if event.control and event.shift and event.scancode == KEY_BACKSPACE:
			manual = true

	if not manual and event.is_action_pressed("hotzone_manual_capture"):
		manual = true

	if manual:
		var scene_name = ""
		var pos = Vector3.ZERO
		var player = SessionManager.player
		if is_instance_valid(player):
			pos = player.global_transform.origin
			if get_tree().current_scene:
				scene_name = get_tree().current_scene.filename.get_file().get_basename()

		_trigger_capture(scene_name, pos, "manual")

func _trigger_capture(scene: String, pos: Vector3, trigger_type: String):
	if trigger_type == "auto":
		var gx = int(floor(pos.x / hotzone_grid_size))
		var gz = int(floor(pos.z / hotzone_grid_size))
		var key = "%s:%d:%d" % [scene, gx, gz]

		if _dedup_table.has(key):
			print("[HotzoneRecorder] Skipping capture: grid cell already recorded this session")
			return

		_dedup_table[key] = OS.get_unix_time()

	_capture_count += 1
	print("[HotzoneRecorder] Triggering hotzone capture (type: %s) for %s" % [trigger_type, scene])

	# Collect frames from ring buffer in order
	var frames = []
	var start_idx = (_head - _count + hotzone_buffer_frames) % hotzone_buffer_frames
	for i in range(_count):
		frames.append(_ring_buffer[(start_idx + i) % hotzone_buffer_frames])

	var snapshot = {
		"magic": BINARY_MAGIC,
		"version": SCHEMA_VERSION,
		"trigger": trigger_type,
		"player_id": _anna_v2.player_id if _anna_v2 else "unknown",
		"session_id": _anna_v2.session_id if _anna_v2 else "unknown",
		"timestamp": OS.get_unix_time(),
		"scene": scene,
		"grid": [int(floor(pos.x / hotzone_grid_size)), int(floor(pos.z / hotzone_grid_size))],
		"frames": frames
	}

	var blob = var2bytes(snapshot)
	var filename = "hotzone_%d.bin" % OS.get_unix_time()
	var filepath = PENDING_DIR + filename

	var f = File.new()
	if f.open(filepath, File.WRITE) == OK:
		f.store_buffer(blob)
		f.close()
		_enqueue_upload(filepath, trigger_type)
		if trigger_type == "manual":
			_show_feedback("Bug report enviado ✓")
	else:
		printerr("[HotzoneRecorder] Failed to save hotzone blob to ", filepath)
		if trigger_type == "manual":
			_show_feedback("Error al enviar — se reintentará", true)

func _enqueue_upload(filepath: String, trigger_type: String = "auto"):
	if not filepath in _upload_queue:
		_upload_queue.append({"path": filepath, "trigger": trigger_type})

	if _upload_queue.size() > 3:
		var dropped = _upload_queue.pop_at(1)
		print("[HotzoneRecorder] Memory queue full, deferring ", dropped.path)

	if not _is_uploading:
		call_deferred("_process_upload_queue")

func _process_upload_queue():
	if _is_uploading or _upload_queue.empty():
		return

	var item = _upload_queue[0]
	var filepath = item.path
	var trigger = item.trigger

	var f = File.new()
	if not f.file_exists(filepath):
		_upload_queue.pop_front()
		call_deferred("_process_upload_queue")
		return

	if f.open(filepath, File.READ) != OK:
		_upload_queue.pop_front()
		call_deferred("_process_upload_queue")
		return

	var blob = f.get_buffer(f.get_len())
	f.close()

	_is_uploading = true

	var url = _get_upload_url()
	var token = _get_token()

	if _is_web:
		_upload_web(url, token, blob, filepath, trigger)
	else:
		_upload_native(url, token, blob, trigger)

func _get_upload_url() -> String:
	var base = "wss://odisea.educa.juegos/ws" # Default
	if _anna_v2 and _anna_v2._net_thread:
		var peer_url = _anna_v2._net_thread._peer_url
		if peer_url != "":
			base = peer_url

	var url = base.replace("/ws", "/hotzone")
	if url.begins_with("ws://"): url = url.replace("ws://", "http://")
	if url.begins_with("wss://"): url = url.replace("wss://", "https://")
	return url

func _get_token() -> String:
	if _anna_v2 and _anna_v2._net_thread:
		return _anna_v2._net_thread._bridge_token
	return ""

func _upload_native(url: String, token: String, blob: PoolByteArray, trigger: String):
	var headers = [
		"Authorization: Bearer " + token,
		"Content-Type: application/octet-stream"
	]

	var player_id = _anna_v2.player_id if _anna_v2 else "unknown"
	var session_id = _anna_v2.session_id if _anna_v2 else "unknown"
	headers.append("X-Player-ID: " + player_id)
	headers.append("X-Session-ID: " + session_id)
	headers.append("X-Trigger: " + trigger)

	var err = _http_request.request_raw(url, headers, true, HTTPClient.METHOD_POST, blob)
	if err != OK:
		printerr("[HotzoneRecorder] Native upload request failed to start: ", err)
		_is_uploading = false
		_on_upload_error()

func _on_upload_completed(_result, response_code, _headers, _body):
	_is_uploading = false
	if response_code == 200 or response_code == 201:
		print("[HotzoneRecorder] Upload successful")
		var item = _upload_queue.pop_front()
		var dir = Directory.new()
		dir.remove(item.path)

		_retry_timer = 5.0
		call_deferred("_process_upload_queue")
	else:
		printerr("[HotzoneRecorder] Upload failed with code ", response_code)
		_on_upload_error()

func _on_upload_error():
	var _failed_item = _upload_queue.pop_front()
	_retry_timer = hotzone_cooldown

func _scan_pending_files():
	var dir = Directory.new()
	if dir.open(PENDING_DIR) == OK:
		dir.list_dir_begin(true)
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".bin"):
				var full_path = PENDING_DIR + file_name
				var already_in = false
				for item in _upload_queue:
					if item.path == full_path:
						already_in = true
						break
				if not already_in:
					_upload_queue.append({"path": full_path, "trigger": "unknown"})
					if _upload_queue.size() >= 5: break
			file_name = dir.get_next()
		dir.list_dir_end()

	if not _is_uploading and not _upload_queue.empty():
		_process_upload_queue()

func _show_feedback(message: String, is_error: bool = false):
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	get_tree().root.add_child(canvas)

	var label = Label.new()
	label.text = message
	label.align = Label.ALIGN_RIGHT
	label.valign = Label.VALIGN_TOP
	label.set_anchors_and_margins_preset(Control.PRESET_TOP_RIGHT)
	label.margin_top = 20
	label.margin_right = -20

	if is_error:
		label.modulate = Color(1, 0.3, 0.3)
	else:
		label.modulate = Color(0.3, 1, 0.3)

	canvas.add_child(label)

	# Simple fade out
	var t = Timer.new()
	t.wait_time = 3.0
	t.one_shot = true
	canvas.add_child(t)
	t.start()
	yield(t, "timeout")

	# Manual animation for fade (since I can't use Tween easily in this script without complex setup)
	# For simplicity, just queue_free
	canvas.queue_free()

# --- HTML5 / Web Worker ---

func _inject_worker():
	if not Engine.has_singleton("JavaScript"): return

	var worker_code = ""
	var f = File.new()
	if f.file_exists("res://core_v2/telemetry/html/hotzone_worker.js"):
		f.open("res://core_v2/telemetry/html/hotzone_worker.js", File.READ)
		worker_code = f.get_as_text().replace("\"", "\\\"").replace("\n", "\\n")
		f.close()
	else:
		worker_code = "self.onmessage=async function(e){ var {url,token,blob,id,headers}=e.data; try { var fetchHeaders={'Authorization':'Bearer '+token,'Content-Type':'application/octet-stream'}; if(headers)Object.assign(fetchHeaders,headers); var resp=await fetch(url,{method:'POST',headers:fetchHeaders,body:blob}); self.postMessage({id:id,ok:resp.ok,status:resp.status}); } catch(err){ self.postMessage({id:id,ok:false,error:err.message}); } };"

	Engine.get_singleton("JavaScript").eval("""
(function(){
if (window.Hotzone_Worker_Bridge) return;
var w = new Worker(URL.createObjectURL(new Blob([
\"""" + worker_code + """\"
].join('\\n'),{type:'application/javascript'})));
var results = {};
w.onmessage = function(ev) {
	results[ev.data.id] = ev.data;
};
window.Hotzone_Worker_Bridge = {
	upload: function(url, token, blob, id, headers) {
		w.postMessage({url: url, token: token, blob: blob, id: id, headers: headers});
	},
	poll: function(id) {
		var res = results[id];
		if (res) delete results[id];
		return res;
	}
};
})();
""")

var _current_web_upload_id := ""

func _upload_web(url: String, token: String, blob: PoolByteArray, _filepath: String, trigger: String):
	_current_web_upload_id = str(OS.get_ticks_msec())
	var js = Engine.get_singleton("JavaScript")
	var player_id = _anna_v2.player_id if _anna_v2 else "unknown"
	var session_id = _anna_v2.session_id if _anna_v2 else "unknown"
	var b64 = Marshalls.raw_to_base64(blob)
	js.eval("(function(){ " +
		"var b64 = '" + b64 + "';" +
		"var bin = atob(b64);" +
		"var buf = new Uint8Array(bin.length);" +
		"for (var i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);" +
		"var headers = {" +
		"  'X-Player-ID': '" + player_id + "'," +
		"  'X-Session-ID': '" + session_id + "'," +
		"  'X-Trigger': '" + trigger + "'" +
		"};" +
		"Hotzone_Worker_Bridge.upload('" + url + "', '" + token + "', buf, '" + _current_web_upload_id + "', headers);" +
		"})()")

func _process(delta):
	if _is_web and _is_uploading and _current_web_upload_id != "":
		var js = Engine.get_singleton("JavaScript")
		var poll_res = js.eval("JSON.stringify(Hotzone_Worker_Bridge.poll('" + _current_web_upload_id + "'))")
		if poll_res != null and poll_res != "" and poll_res != "undefined":
			var result = JSON.parse(poll_res)
			if result.error == OK and typeof(result.result) == TYPE_DICTIONARY:
				_on_web_upload_completed(result.result)

	# Cooldown / Retry logic
	_retry_timer -= delta
	if _retry_timer <= 0:
		_retry_timer = hotzone_cooldown
		if not _is_uploading:
			_scan_pending_files()

func _on_web_upload_completed(res):
	_is_uploading = false
	var ok = res.get("ok")
	if ok:
		print("[HotzoneRecorder] Web upload successful")
		var item = _upload_queue.pop_front()
		var dir = Directory.new()
		dir.remove(item.path)
		_retry_timer = 5.0
	else:
		printerr("[HotzoneRecorder] Web upload failed: ", res.get("error", "unknown error"), " Status: ", res.get("status"))
		_on_upload_error()

	_current_web_upload_id = ""
	call_deferred("_process_upload_queue")
