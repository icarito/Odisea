extends Node

signal update_available(info)
signal update_progress(downloaded_bytes, total_bytes)
signal update_ready(info)
signal update_failed(code, recoverable)
signal new_version_available(version_data)

enum State {
	IDLE,
	CHECKING,
	AVAILABLE,
	DOWNLOADING,
	VERIFYING,
	READY_TO_RESTART,
	APPLYING_EXTERNAL,
	BLOCKED_CRITICAL,
	FAILED
}

const UPDATE_DIR = "user://updates/"
const STAGING_DIR = UPDATE_DIR + "staging/"
const PACKAGE_DIR = UPDATE_DIR + "packages/"
const STATE_FILE = UPDATE_DIR + "state.json"
const PENDING_BOOT_FILE = UPDATE_DIR + "pending_boot.json"
const CONFIRMED_BOOT_FILE = UPDATE_DIR + "confirmed_boot.json"
const INSTALL_ID_FILE = UPDATE_DIR + "installation_id"

const Utils = preload("res://core_v2/update/UpdateUtils.gd")

var _state = State.IDLE
var _keyring: Reference
var _verifier: Reference
var _local_state := {}
var _installation_id := ""
var _pending_update := {}
var _active_download := {}
var _http_download: HTTPRequest
var _chunk_retries := 0

func _ready():
	_keyring = load("res://core_v2/update/UpdateKeyring.gd").new()
	_verifier = load("res://core_v2/update/UpdateManifestVerifier.gd").new(_keyring)
	_ensure_dirs()
	_load_installation_id()
	_load_local_state()
	_check_pending_boot()
	_cleanup_staging()
	# Confirmar el boot tras un update no debe depender SOLO de llegar al menú
	# (Menu.gd): si el jugador entra directo a gameplay (deep-link) o el menú cambia,
	# el pending nunca se confirmaba y el update se revertía a los 2 intentos aunque
	# funcionara. El startup gate de SessionManager abre de forma fiable en cualquier
	# flujo, así que también confirmamos ahí (confirm_boot es idempotente).
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.has_signal("startup_gate_opened"):
		sm.connect("startup_gate_opened", self, "_on_startup_gate_opened", [], CONNECT_ONESHOT)

func _on_startup_gate_opened(_reason, _frames) -> void:
	confirm_boot()

func check_for_updates() -> void:
	if _state != State.IDLE and _state != State.FAILED:
		return
	_set_state(State.CHECKING)

	# El canal debe venir del build_meta empaquetado (channel=nightly en builds de
	# main). Antes salía solo de la env var ODISEA_UPDATE_CHANNEL y caía a "release",
	# así que un build nightly preguntaba por un manifest "release" inexistente y el
	# server devolvía 204 -> el juego nunca veía la actualización. La env var sigue
	# como override para debug. Fallback: "nightly", porque hoy SOLO se publica
	# nightly (no hay canal release todavía).
	var channel = OS.get_environment("ODISEA_UPDATE_CHANNEL")
	if channel == "":
		channel = _get_build_meta_value("channel")
	if channel == "":
		channel = "nightly"

	var platform = "linux"
	var os_name = OS.get_name()
	if os_name == "Windows": platform = "windows"
	elif os_name == "OSX": platform = "macos"
	elif os_name == "Android": platform = "android"
	elif os_name == "iOS": platform = "ios"
	elif os_name == "HTML5": platform = "html5"

	var arch = "x86_64"
	if OS.has_feature("arm64"):
		arch = "arm64"
	elif OS.has_feature("32"):
		arch = "x86"
	if os_name == "HTML5":
		arch = "web"

	var version = "v0.0.0"
	var constants = get_node_or_null("/root/Constants")
	if constants:
		version = constants.get("GAME_VERSION")

	var query = "channel=%s&platform=%s&arch=%s&current_version=%s&current_build_id=%s" % [
		channel, platform, arch, version, _get_current_build_id()
	]

	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", self, "_on_check_completed", [http, channel, platform])

	var url = "https://odisea.educa.juegos/game/updates/v1/manifest?" + query
	# El server EXIGE este Accept o devuelve 400 invalid_accept_header. Sin él, el
	# check siempre fallaba (-> State.FAILED) y nunca aparecía la notificación.
	var request_headers := ["Accept: application/vnd.odisea.update-manifest.v1+json"]
	var err = http.request(url, request_headers)
	if err != OK:
		_on_error("network_unavailable", true)
		http.queue_free()

func _on_check_completed(result, response_code, _headers, body, http, channel, platform):
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		_on_error("network_unavailable", true)
		return

	if response_code == 301 or response_code == 302:
		# Very basic redirect handling
		var headers = _headers
		for h in headers:
			if h.to_lower().begins_with("location:"):
				var new_url = h.split(":", true, 1)[1].strip_edges()
				_redirect_check(new_url, channel, platform)
				return

	if response_code == 204:
		_set_state(State.IDLE)
		return

	if response_code != 200:
		_on_error("invalid_response", true)
		return

	var json_res = JSON.parse(body.get_string_from_utf8())
	if json_res.error != OK or not (json_res.result is Dictionary):
		_on_error("invalid_response", true)
		return

	var envelope = json_res.result
	var res = _verifier.verify(envelope)
	if res.has("error"):
		_on_error(res["error"], false)
		return

	var payload = res["payload"]
	if not _validate_manifest(payload, channel, platform):
		return

	_pending_update = payload
	_set_state(State.AVAILABLE)
	emit_signal("update_available", payload)
	emit_signal("new_version_available", payload)

func _validate_manifest(p, channel, platform) -> bool:
	if p.get("channel") != channel:
		_on_error("channel_mismatch", false)
		return false
	if p.get("platform") != platform:
		_on_error("platform_mismatch", false)
		return false

	var seq = p.get("release_sequence", 0)
	var last_seq = 0
	if _local_state["accepted_sequences"].size() > 0:
		last_seq = _local_state["accepted_sequences"].max()

	if seq <= last_seq:
		# Already have this or newer
		_set_state(State.IDLE)
		return false

	# Check expiry if present
	if p.has("expires_at"):
		var expiry = Utils.iso8601_to_unix(p["expires_at"])
		if OS.get_unix_time() > expiry:
			_on_error("manifest_expired", false)
			return false

	# Rollout calculation
	var rollout_percent = p.get("rollout_percent", 100)
	if rollout_percent < 100:
		var manifest_id = p.get("manifest_id", "")
		var ctx = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update((_installation_id + ":" + manifest_id).to_utf8())
		var digest = ctx.finish()
		var bucket = (digest[0] << 24 | digest[1] << 16 | digest[2] << 8 | digest[3]) % 10000
		if bucket >= rollout_percent * 100:
			_on_error("not_in_rollout", true)
			return false

	return true

func _on_error(code: String, recoverable: bool):
	_set_state(State.FAILED)
	emit_signal("update_failed", code, recoverable)

func get_current_update() -> Dictionary:
	return _pending_update.duplicate()

func _get_current_build_id() -> String:
	# Tras aplicar un update, el build corriente queda en confirmed_boot.json. En una
	# instalación fresca ese archivo no existe, así que caemos al build_id empaquetado
	# (build_meta) para que el server compare contra el build real, no contra "".
	var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	var bid = confirmed.get("build_id", "")
	if bid == "":
		bid = _get_build_meta_value("build_id")
	return bid

# Lee un valor del build_meta inyectado por CI: window.ODISEA_BUILD_META en web,
# res://build_meta.json (embebido en el .pck) en nativo. Mismo patrón que ANNAV2.
var _build_meta_cache := {}
func _get_build_meta_value(key: String) -> String:
	if OS.has_feature("web") and Engine.has_singleton("JavaScript"):
		var js = Engine.get_singleton("JavaScript")
		var expr = "window.ODISEA_BUILD_META && window.ODISEA_BUILD_META['" + key + "'] || ''"
		var res = js.eval(expr)
		return str(res) if res != null else ""
	if _build_meta_cache.empty():
		var file := File.new()
		var meta_paths := [
			"res://build_meta.json",
			"build_meta.json",
			OS.get_executable_path().get_base_dir().plus_file("build_meta.json")
		]
		for path in meta_paths:
			if file.file_exists(path):
				if file.open(path, File.READ) == OK:
					var parsed = JSON.parse(file.get_as_text())
					file.close()
					if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
						_build_meta_cache = parsed.result
						break
		if _build_meta_cache.empty():
			_build_meta_cache["_loaded"] = false
	return str(_build_meta_cache.get(key, ""))


func begin_update() -> void:
	if _state != State.AVAILABLE:
		return

	if OS.get_name() == "iOS":
		var url = _pending_update.get("downloads_page", "")
		if url != "":
			OS.shell_open(url)
		return

	if OS.get_name() == "HTML5":
		# Delegate to shell by reloading with build_id
		var build_id = _pending_update.get("build_id", "")
		if JavaScript:
			JavaScript.eval("window.location.href = window.location.origin + window.location.pathname + '?build_id=' + '" + build_id + "';")
		return

	var artifact = get_selected_artifact(_pending_update)
	if artifact.empty():
		_on_error("no_compatible_artifact", false)
		return

	_start_download(artifact)

func get_selected_artifact(p: Dictionary) -> Dictionary:
	var current_confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	var current_build_id = current_confirmed.get("build_id", "")

	# Try delta
	if p.has("delta_artifacts"):
		for delta in p["delta_artifacts"]:
			if delta.get("from_build_id") == current_build_id:
				if is_delta_eligible(delta, p):
					delta["is_delta"] = true
					return delta

	# Fallback to full
	if p.has("full_artifact"):
		var full = p["full_artifact"]
		full["is_delta"] = false
		return full

	return {}

func is_delta_eligible(delta: Dictionary, p: Dictionary) -> bool:
	if p.get("force_full", false): return false
	if delta.get("touches_bootstrap", false): return false
	if not delta.get("deleted_paths", []).empty(): return false

	var full_size = p.get("full_artifact", {}).get("size", 1)
	if delta.get("size", 0) > full_size * 0.7: return false

	if _local_state.get("active_package_ids", []).size() >= 3: # Base + 2 patches
		return false

	return true

func cancel_download() -> void:
	if _state == State.DOWNLOADING:
		if _http_download:
			_http_download.cancel_request()
		_set_state(State.AVAILABLE)

func request_restart() -> void:
	if _state == State.READY_TO_RESTART:
		get_tree().quit() # Or OS.shell_execute for restart if possible

func confirm_boot() -> void:
	var pending = _load_json(PENDING_BOOT_FILE, {})
	if pending.empty(): return

	var confirmed = pending.duplicate()
	_save_json(CONFIRMED_BOOT_FILE, confirmed)

	# Update local state
	_local_state["accepted_sequences"].append(pending.get("release_sequence", 0))
	_local_state["active_package_ids"] = pending.get("package_ids", [])
	_save_json(STATE_FILE, _local_state)

	var d = Directory.new()
	d.remove(PENDING_BOOT_FILE)

	_cleanup_packages()

func get_status() -> String:
	return State.keys()[_state].to_lower()

func _set_state(new_state: int):
	_state = new_state
	print("[UpdateManager] State changed to: ", get_status())
	# Silenciar warnings de CPU Budget mientras descargamos/verificamos (es CPU-pesado
	# y esperado); restaurar al volver a un estado ocioso.
	var pm = get_node_or_null("/root/PerformanceMonitor")
	if pm and pm.has_method("set_heavy_op_active"):
		pm.set_heavy_op_active(new_state == State.DOWNLOADING or new_state == State.VERIFYING)

func _ensure_dirs():
	var d = Directory.new()
	for path in [UPDATE_DIR, STAGING_DIR, PACKAGE_DIR]:
		if not d.dir_exists(path):
			d.make_dir_recursive(path)

func _load_installation_id():
	var f = File.new()
	if f.file_exists(INSTALL_ID_FILE):
		if f.open(INSTALL_ID_FILE, File.READ) == OK:
			_installation_id = f.get_as_text().strip_edges()
			f.close()

	if _installation_id == "":
		# Generate 128-bit random ID (UUID-like)
		var b = []
		for i in range(16):
			b.append(randi() % 256)
		_installation_id = ""
		for val in b:
			_installation_id += "%02x" % val

		if f.open(INSTALL_ID_FILE, File.WRITE) == OK:
			f.store_string(_installation_id)
			f.close()

func _load_local_state():
	_local_state = _load_json(STATE_FILE, {
		"accepted_sequences": [],
		"active_package_ids": []
	})

func _load_json(path: String, default: Dictionary) -> Dictionary:
	var f = File.new()
	if not f.file_exists(path):
		return default
	if f.open(path, File.READ) != OK:
		return default
	var text = f.get_as_text()
	f.close()
	var res = JSON.parse(text)
	if res.error != OK or not (res.result is Dictionary):
		return default
	return res.result

func _save_json(path: String, data: Dictionary):
	var f = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(JSON.print(data))
		f.close()

func _start_download(artifact: Dictionary):
	_active_download = artifact
	_set_state(State.DOWNLOADING)
	_chunk_retries = 0
	_download_next_chunk()

func _download_next_chunk():
	var artifact_id = _active_download["artifact_id"]
	var state_path = STAGING_DIR + artifact_id + ".state.json"

	var ds = _load_json(state_path, {"completed_chunks": []})
	var chunks = _active_download.get("chunks", [])

	var next_chunk_idx = -1
	for i in range(chunks.size()):
		if not i in ds["completed_chunks"]:
			next_chunk_idx = i
			break

	if next_chunk_idx == -1:
		_finalize_download()
		return

	var chunk = chunks[next_chunk_idx]
	var http = HTTPRequest.new()
	add_child(http)
	_http_download = http

	var start_byte = chunk["offset"]
	var end_byte = chunk["offset"] + chunk["size"] - 1
	var headers = ["Range: bytes=%d-%d" % [start_byte, end_byte]]

	http.connect("request_completed", self, "_on_chunk_completed", [http, next_chunk_idx])
	var err = http.request(_active_download["url"], headers)
	if err != OK:
		_handle_chunk_error("request_failed")

func _on_chunk_completed(result, response_code, _headers, body, http, idx):
	http.queue_free()
	_http_download = null

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_chunk_error("http_request_failed")
		return

	if response_code == 200:
		# Server might not support Range, it returned the whole file
		_handle_non_range_response(body)
		return

	if response_code != 206:
		_handle_chunk_error("http_status_" + str(response_code))
		return

	var chunk = _active_download["chunks"][idx]
	if body.size() != chunk["size"]:
		_handle_chunk_error("size_mismatch")
		return

	# File.get_sha256_from_buffer NO existe en Godot 3.6 (es de Godot 4): devolvía
	# null -> siempre chunk_hash_mismatch -> descarga fallaba. Usamos HashingContext
	# vía UpdateUtils (mismo que el verifier) y comparamos el hex.
	if Utils.get_sha256_hash(body).hex_encode() != chunk["sha256"]:
		_handle_chunk_error("chunk_hash_mismatch")
		return

	# Write chunk to part file
	var f = File.new()
	var part_path = STAGING_DIR + _active_download["artifact_id"] + ".part"
	var err
	if f.file_exists(part_path):
		err = f.open(part_path, File.READ_WRITE)
	else:
		err = f.open(part_path, File.WRITE)

	if err != OK:
		_handle_chunk_error("file_error")
		return

	f.seek(chunk["offset"])
	f.store_buffer(body)
	f.close()

	# Update state
	var state_path = STAGING_DIR + _active_download["artifact_id"] + ".state.json"
	var ds = _load_json(state_path, {"completed_chunks": []})
	ds["completed_chunks"].append(idx)
	_save_json(state_path, ds)

	_chunk_retries = 0
	emit_signal("update_progress", ds["completed_chunks"].size() * chunk["size"], _active_download["size"])
	_download_next_chunk()

func _handle_chunk_error(code):
	_chunk_retries += 1
	if _chunk_retries > 3:
		_on_error("download_failed:" + code, true)
		return

	var backoff = [0, 1, 3, 10][_chunk_retries]
	yield(get_tree().create_timer(backoff), "timeout")
	_download_next_chunk()

func _finalize_download():
	_set_state(State.VERIFYING)

	if _active_download.get("kind") == "apk":
		_finalize_apk_download()
		return

	var artifact_id = _active_download["artifact_id"]
	var part_path = STAGING_DIR + artifact_id + ".part"
	var final_path = PACKAGE_DIR + artifact_id + ".pck"

	var f = File.new()
	if f.get_sha256(part_path) != _active_download["sha256"]:
		_on_error("artifact_hash_mismatch", false)
		return

	var d = Directory.new()
	if d.rename(part_path, final_path) != OK:
		_on_error("promote_failed", false)
		return

	d.remove(STAGING_DIR + artifact_id + ".state.json")

	# Create pending boot
	var package_ids = []
	if _active_download["is_delta"]:
		package_ids = _local_state.get("active_package_ids", []).duplicate()
	package_ids.append(artifact_id)

	# Keep track of hashes for boot verification
	var package_hashes = _get_current_package_hashes()
	package_hashes[artifact_id] = _active_download["sha256"]

	var pending = {
		"manifest_id": _pending_update["manifest_id"],
		"build_id": _pending_update["build_id"],
		"release_sequence": _pending_update["release_sequence"],
		"package_ids": package_ids,
		"package_hashes": package_hashes,
		"attempts": 0
	}

	if OS.has_feature("web"):
		# HTML5 specific: navigate with build_id
		_finalize_web_update(pending)
		return

	_save_json(PENDING_BOOT_FILE, pending)

	_set_state(State.READY_TO_RESTART)
	emit_signal("update_ready", _pending_update)

func _get_current_package_hashes() -> Dictionary:
	var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	return confirmed.get("package_hashes", {}).duplicate()

func _finalize_apk_download():
	var artifact_id = _active_download["artifact_id"]
	var part_path = STAGING_DIR + artifact_id + ".part"

	var f = File.new()
	if f.get_sha256(part_path) != _active_download["sha256"]:
		_on_error("artifact_hash_mismatch", false)
		return

	# On Android, we don't load the PCK, we trigger the APK install
	var real_path = ProjectSettings.globalize_path(part_path)

	# Rename to .apk so the OS recognizes it
	var apk_path = PACKAGE_DIR + artifact_id + ".apk"
	var d = Directory.new()
	if d.file_exists(apk_path):
		d.remove(apk_path)

	if d.copy(part_path, apk_path) == OK:
		OS.shell_open(ProjectSettings.globalize_path(apk_path))
		_set_state(State.APPLYING_EXTERNAL)
	else:
		_on_error("apk_promote_failed", false)

func _finalize_web_update(pending):
	# JavaScript call to navigate with cache busting
	if JavaScript:
		var build_id = pending["build_id"]
		JavaScript.eval("window.location.href = window.location.pathname + '?build_id=' + '" + build_id + "';")
	_set_state(State.READY_TO_RESTART)

func _check_pending_boot():
	var pending = _load_json(PENDING_BOOT_FILE, {})
	if pending.empty():
		_load_active_packages()
		return

	pending["attempts"] = pending.get("attempts", 0) + 1
	_save_json(PENDING_BOOT_FILE, pending)

	if pending["attempts"] > 2:
		print("[UpdateManager] Pending boot failed 2 times. Rolling back.")
		var d = Directory.new()
		d.remove(PENDING_BOOT_FILE)
		_load_active_packages()
		return

	_apply_packages(pending["package_ids"], pending.get("package_hashes", {}))

func _load_active_packages():
	var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	if confirmed.has("package_ids"):
		_apply_packages(confirmed["package_ids"])

func _apply_packages(package_ids: Array, p_hashes: Dictionary = {}):
	var package_hashes = p_hashes
	if package_hashes.empty():
		var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
		package_hashes = confirmed.get("package_hashes", {})

	for id in package_ids:
		var path = PACKAGE_DIR + id + ".pck"
		var f = File.new()
		if not f.file_exists(path):
			print("[UpdateManager] Missing package: ", id)
			continue

		# Re-verify SHA-256 before loading
		if package_hashes.has(id):
			var expected_hash = package_hashes[id]
			if f.get_sha256(path) != expected_hash:
				print("[UpdateManager] Hash mismatch for package ", id, ". Skipping load.")
				continue

		if not ProjectSettings.load_resource_pack(path, true):
			print("[UpdateManager] Failed to load package: ", id)

func _cleanup_packages():
	var active = _local_state.get("active_package_ids", [])
	var d = Directory.new()
	if d.open(PACKAGE_DIR) == OK:
		d.list_dir_begin()
		var file_name = d.get_next()
		while file_name != "":
			if not d.current_is_dir() and file_name.ends_with(".pck"):
				var id = file_name.get_basename()
				if not id in active:
					d.remove(file_name)
			file_name = d.get_next()

func _cleanup_staging():
	var d = Directory.new()
	if d.open(STAGING_DIR) != OK: return

	d.list_dir_begin()
	var file_name = d.get_next()
	while file_name != "":
		if not d.current_is_dir():
			# Simple policy: clear staging at boot if it's not a resumed download
			# In a real scenario we'd check modification times
			d.remove(file_name)
		file_name = d.get_next()

func _redirect_check(url, channel, platform):
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", self, "_on_check_completed", [http, channel, platform])
	# Mismo Accept que el check directo, o el destino del redirect daría 400.
	http.request(url, ["Accept: application/vnd.odisea.update-manifest.v1+json"])

func _handle_non_range_response(body: PoolByteArray):
	print("[UpdateManager] Server does not support Range. Handling full response.")
	if body.size() == _active_download["size"]:
		# get_sha256_from_buffer no existe en 3.6 (ver chunk verify arriba).
		if Utils.get_sha256_hash(body).hex_encode() == _active_download["sha256"]:
			var artifact_id = _active_download["artifact_id"]
			var part_path = STAGING_DIR + artifact_id + ".part"
			var f = File.new()
			if f.open(part_path, File.WRITE) == OK:
				f.store_buffer(body)
				f.close()
				_finalize_download()
				return

	_on_error("non_range_unsupported", true)
