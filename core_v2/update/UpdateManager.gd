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

# NO usar preload() ni string literal res:// del .gdns: el exporter de Godot 3.x escanea
# cualquier string "res://" en scripts de autoload y lo trata como dependencia, incluso
# si no es preload. En Android (sin lib ARM nativa) eso dispara init_library y ABORTA
# el export. El empaquetado de la lib en desktop lo garantiza el include_filter, así que
# la ruta se construye SIN string literal res:// para que el exporter no la detecte.
const BSPATCH_GDNS_PATH := "core_v2/update/native/OdiseaBspatch.gdns"

var _state = State.IDLE
var _keyring: Reference
var _verifier: Reference
var _local_state := {}
var _installation_id := ""
var _pending_update := {}
var _active_download := {}
var _http_download: HTTPRequest
var _downloading_chunk_idx := -1
var _chunk_retries := 0
var _needs_binary_update := false
var _download_queue := []
var _staged_artifacts := []

func _ready():
	_keyring = load("res://core_v2/update/UpdateKeyring.gd").new()
	_verifier = load("res://core_v2/update/UpdateManifestVerifier.gd").new(_keyring)
	_ensure_dirs()
	_load_installation_id()
	_load_local_state()
	if _is_source_checkout():
		print("[UpdateManager] Source checkout detected; packaged updates disabled for this run.")
		return
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
	if _is_source_checkout():
		_set_state(State.IDLE)
		return
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
	_needs_binary_update = _check_needs_binary_update(payload)
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

func _check_needs_binary_update(p: Dictionary) -> bool:
	if OS.has_feature("web") or OS.get_name() == "Android" or OS.get_name() == "iOS":
		return false

	var remote_godot_hash = p.get("project_godot_hash", "")
	if remote_godot_hash == "":
		return false

	var local_godot_hash = _get_local_project_godot_hash()
	return local_godot_hash != remote_godot_hash

func _get_local_project_godot_hash() -> String:
	var paths = [
		"res://project.godot",
		OS.get_executable_path().get_base_dir().plus_file("project.godot")
	]
	var f = File.new()
	for path in paths:
		if f.file_exists(path):
			if f.open(path, File.READ) == OK:
				var data = f.get_buffer(f.get_len())
				f.close()
				return Utils.get_sha256_hash(data).hex_encode()
	return ""

func _on_error(code: String, recoverable: bool):
	_free_download_request()
	_set_state(State.FAILED)
	emit_signal("update_failed", code, recoverable)

# Libera el HTTPRequest persistente de descarga (al terminar/fallar/cancelar), para
# que la próxima descarga arranque con uno limpio.
func _free_download_request() -> void:
	if is_instance_valid(_http_download):
		_http_download.queue_free()
	_http_download = null
	_downloading_chunk_idx = -1

func get_current_update() -> Dictionary:
	return _pending_update.duplicate()

func _get_current_build_id() -> String:
	if _is_source_checkout():
		return OS.get_environment("ODISEA_BUILD_ID") if OS.get_environment("ODISEA_BUILD_ID") != "" else "dev"
	# Tras aplicar un update, el build corriente queda en confirmed_boot.json. En una
	# instalación fresca ese archivo no existe, así que caemos al build_id empaquetado
	# (build_meta) para que el server compare contra el build real, no contra "".
	var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	var confirmed_bid = str(confirmed.get("build_id", ""))
	var packaged_bid = _get_build_meta_value("build_id")
	# Si reinstalaste un .zip más NUEVO que el último update aplicado (p.ej. bajaste
	# manualmente el build 227 pero confirmed_boot decía 225 de un update viejo), el
	# build_meta empaquetado es la verdad. Si no, antes el cliente reportaba el 225 y
	# el server ofrecía "actualizar" a 227 = la versión que ya tenías instalada.
	# Usamos el MAYOR de los dos (todos son run_number, comparables como int).
	if confirmed_bid == "":
		return packaged_bid
	if packaged_bid != "" and packaged_bid.is_valid_integer() and confirmed_bid.is_valid_integer():
		if int(packaged_bid) > int(confirmed_bid):
			return packaged_bid
	return confirmed_bid

# Lee un valor del build_meta inyectado por CI: window.ODISEA_BUILD_META en web,
# res://build_meta.json (embebido en el .pck) en nativo. Mismo patrón que ANNAV2.
var _build_meta_cache := {}
# Info del build LOCAL instalado (del build_meta empaquetado), para mostrar en el
# diálogo de update junto al build remoto. Devuelve "" en los campos que falten.
func get_local_build_info() -> Dictionary:
	return {
		"version": _get_build_meta_value("version"),
		"commit": _get_build_meta_value("commit"),
		"build_id": _get_build_meta_value("build_id"),
		"channel": _get_build_meta_value("channel"),
	}

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

func _is_source_checkout() -> bool:
	if OS.get_environment("ODISEA_ENABLE_UPDATES_IN_DEV") in ["1", "true", "yes", "on"]:
		return false
	if Engine.editor_hint or OS.has_feature("editor"):
		return true
	var dir := Directory.new()
	return dir.dir_exists("res://.git")


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

	_download_queue = []
	_staged_artifacts = []
	if _needs_binary_update:
		var binary = get_selected_binary_artifact(_pending_update)
		if not binary.empty():
			_download_queue.append(binary)

	var pck = get_selected_artifact(_pending_update)
	if not pck.empty():
		_download_queue.append(pck)

	if _download_queue.empty():
		_on_error("no_compatible_artifact", false)
		return

	_download_next_in_queue(true)

func _download_next_in_queue(is_reentry: bool = false):
	if _download_queue.empty():
		_finalize_all_downloads()
		return

	var artifact = _download_queue.pop_front()
	if is_reentry:
		_start_download(artifact)
	else:
		call_deferred("_start_download", artifact)

func get_selected_binary_artifact(p: Dictionary) -> Dictionary:
	var current_confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	var current_build_id = current_confirmed.get("build_id", "")

	# Try binary delta
	if p.has("binary_delta_artifacts"):
		for delta in p["binary_delta_artifacts"]:
			if delta.get("from_build_id") == current_build_id:
				delta["is_delta"] = true
				delta["is_binary"] = true
				return delta

	# Fallback to binary full
	if p.has("binary_full_artifact") and p["binary_full_artifact"] != null:
		var full = p["binary_full_artifact"]
		full["is_delta"] = false
		full["is_binary"] = true
		return full

	return {}

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
	# Un delta bsdiff requiere la lib nativa OdiseaBspatch para reconstruir el .pck.
	# En plataformas sin lib (p.ej. web, o un build móvil sin .so ARM) preferimos el
	# full antes que ofrecer un delta que no podríamos aplicar.
	if not _has_native_bspatch(): return false
	if delta.get("touches_bootstrap", false): return false
	if not delta.get("deleted_paths", []).empty(): return false

	var full_size = p.get("full_artifact", {}).get("size", 1)
	if delta.get("size", 0) > full_size * 0.7: return false

	if _local_state.get("active_package_ids", []).size() >= 3: # Base + 2 patches
		return false

	return true

# True si la lib nativa de bspatch puede instanciarse en esta plataforma. La web no
# usa deltas binarios (recarga la página), y un build sin la .so/.dll correcta no debe
# ofrecer deltas. Se cachea: instanciar abre la lib una vez.
var _native_bspatch_ok := -1  # -1 desconocido, 0 no, 1 sí
func _has_native_bspatch() -> bool:
	if _native_bspatch_ok != -1:
		return _native_bspatch_ok == 1
	_native_bspatch_ok = 0
	if OS.has_feature("web"):
		return false
	if not ResourceLoader.exists("res://" + BSPATCH_GDNS_PATH):
		return false
	var script = load("res://" + BSPATCH_GDNS_PATH)
	if script != null:
		var p = script.new()
		if p != null and p.has_method("apply"):
			_native_bspatch_ok = 1
	return _native_bspatch_ok == 1

func cancel_download() -> void:
	if _state == State.DOWNLOADING:
		if is_instance_valid(_http_download):
			_http_download.cancel_request()
		_free_download_request()
		_set_state(State.AVAILABLE)

func request_restart() -> void:
	if _state != State.READY_TO_RESTART:
		return

	var pending = _load_json(PENDING_BOOT_FILE, {})
	var exe := OS.get_executable_path()

	if OS.has_feature("web"):
		get_tree().quit()
		return

	# Apply binary update if pending BEFORE launching the new process.
	if pending.has("pending_binary") and not pending["pending_binary"].empty():
		if OS.get_name() == "Windows":
			# On Windows we can't replace the EXE while running.
			# We launch a temporary batch script that handles the swap and relaunch.
			_launch_windows_updater(pending["pending_binary"], exe)
			get_tree().quit()
			return
		else:
			# Linux/macOS: swap it now.
			if not _apply_binary_update(pending["pending_binary"]):
				# If swap failed, we can't really proceed with an incompatible PCK.
				# The user will have to try again or we might need a rollback here.
				print("[UpdateManager] Binary swap failed before restart.")

	if exe != "":
		OS.execute(exe, [], false)
	get_tree().quit()

func _launch_windows_updater(info: Dictionary, exe_path: String) -> void:
	var bin_path = ProjectSettings.globalize_path(PACKAGE_DIR + info.id + ".bin")
	var abs_exe = ProjectSettings.globalize_path(exe_path)
	var script_path = ProjectSettings.globalize_path(UPDATE_DIR + "updater.bat")

	var script_content = [
		"@echo off",
		"timeout /t 2 /nobreak > nul",
		"copy /y \"%s\" \"%s\"" % [bin_path, abs_exe],
		"start \"\" \"%s\"" % [abs_exe],
		"del \"%%~f0\""
	]

	var f = File.new()
	if f.open(script_path, File.WRITE) == OK:
		for line in script_content:
			f.store_line(line)
		f.close()
		OS.execute("cmd.exe", ["/c", "start", "/min", script_path], false)

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
	# Auto-nuke de una vez: un puñado de clientes tempranos guardaron un
	# release_sequence = github.run_id (~2.7e10) de builds canary, antes de pasar a
	# run_number (entero chico). Ese valor gigante bloqueaba TODOS los updates
	# futuros (seq nuevo 221 <= 27483628278 -> idle para siempre). Si lo detectamos,
	# reseteamos el state de update una sola vez. Código temporal de migración.
	var seqs = _local_state.get("accepted_sequences", [])
	var poisoned = false
	for s in seqs:
		if int(s) >= 1000000000:  # ningún run_number legítimo llega a 1e9
			poisoned = true
			break
	if poisoned:
		print("[UpdateManager] Estado de update envenenado (run_id legacy) -> reset.")
		_local_state = {"accepted_sequences": [], "active_package_ids": []}
		_save_json(STATE_FILE, _local_state)

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
	# Reusar UN solo HTTPRequest para todos los chunks. Antes se creaba uno nuevo +
	# add_child + queue_free por chunk, y eso colgaba la descarga a mitad en Godot
	# 3.6 (el nodo viejo en cola de liberación chocaba con el nuevo, request_completed
	# dejaba de dispararse -> download trabado, p.ej. a 42%). Un request persistente
	# es estable (probado: baja los 12 chunks sin colgarse).
	if not is_instance_valid(_http_download):
		_http_download = HTTPRequest.new()
		add_child(_http_download)
		_http_download.connect("request_completed", self, "_on_chunk_completed")
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
	if not is_instance_valid(_http_download):
		_http_download = HTTPRequest.new()
		add_child(_http_download)
		_http_download.connect("request_completed", self, "_on_chunk_completed")

	_downloading_chunk_idx = next_chunk_idx
	var start_byte = chunk["offset"]
	var end_byte = chunk["offset"] + chunk["size"] - 1
	var headers = ["Range: bytes=%d-%d" % [start_byte, end_byte]]

	var err = _http_download.request(_active_download["url"], headers)
	if err != OK:
		_handle_chunk_error("request_failed")

func _on_chunk_completed(result, response_code, _headers, body):
	# Reusamos _http_download (no se libera por chunk). idx viene de un miembro porque
	# el HTTPRequest persistente no puede llevar binds que cambian por request.
	var idx = _downloading_chunk_idx

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

# Descomprime un .gz (src_path) a dst_path y verifica el sha256 del .pck resultante
# contra uncompressed_sha256. Devuelve false (y llama _on_error) si algo falla.
# Para un full, el contenido descomprimido es el .pck final -> verificar contra
# uncompressed_sha256/uncompressed_size. Para un delta, el contenido descomprimido es
# el PATCH crudo -> verificar contra patch_sha256/patch_uncompressed_size (el .pck
# reconstruido se valida aparte, después de bspatch).
func _decompress_gzip_to(src_path: String, dst_path: String, artifact: Dictionary, hash_field := "uncompressed_sha256") -> bool:
	var size_field := "uncompressed_size"
	if hash_field == "patch_sha256":
		size_field = "patch_uncompressed_size"
	var f := File.new()
	if f.open(src_path, File.READ) != OK:
		_on_error("decompress_open_failed", false)
		return false
	var gz := f.get_buffer(f.get_len())
	f.close()
	var uncompressed_size := int(artifact.get(size_field, 0))
	if uncompressed_size <= 0:
		_on_error("decompress_bad_size", false)
		return false
	var raw := gz.decompress(uncompressed_size, File.COMPRESSION_GZIP)
	if raw.size() != uncompressed_size:
		_on_error("decompress_failed", false)
		return false
	var wf := File.new()
	if wf.open(dst_path, File.WRITE) != OK:
		_on_error("decompress_write_failed", false)
		return false
	wf.store_buffer(raw)
	wf.close()
	# Verificar el contenido descomprimido contra el hash esperado del campo indicado.
	var expected := str(artifact.get(hash_field, ""))
	if expected != "" and File.new().get_sha256(dst_path) != expected:
		Directory.new().remove(dst_path)
		_on_error("uncompressed_hash_mismatch", false)
		return false
	return true

# Resuelve la ruta ABSOLUTA del .pck base sobre el que se aplica un delta bsdiff.
# Si ya hubo un update previo, el base es el último .pck activo en PACKAGE_DIR;
# si no, es el .pck original que se distribuye junto al ejecutable.
func _resolve_base_pck_path() -> String:
	var active = _local_state.get("active_package_ids", [])
	if not active.empty():
		var last_id = active[active.size() - 1]
		var p = PACKAGE_DIR + last_id + ".pck"
		if File.new().file_exists(p):
			return ProjectSettings.globalize_path(p)
	# Base original: <ejecutable_basename>.pck junto al binario.
	var exe = OS.get_executable_path()
	var pck = exe.get_basename() + ".pck"
	if File.new().file_exists(pck):
		return pck
	# Algunos exports nombran el pck igual que el binario sin recortar extensión.
	pck = exe.get_base_dir().plus_file(exe.get_file().get_basename() + ".pck")
	if File.new().file_exists(pck):
		return pck
	return ""

# Aplica un patch bsdiff (ODSBSDF1) sobre el .pck base actual y escribe el .pck
# reconstruido en out_path (ruta res://). Usa la lib nativa OdiseaBspatch (GDNative).
# Devuelve true si reconstruyó OK. En error llama _on_error y devuelve false.
func _resolve_base_binary_path() -> String:
	# For binaries, we only have the currently running one.
	return OS.get_executable_path()

func _apply_binary_patch(patch_path: String, out_path: String, is_binary: bool = false) -> bool:
	if not ResourceLoader.exists("res://" + BSPATCH_GDNS_PATH):
		_on_error("bspatch_native_missing", false)
		return false
	var script = load("res://" + BSPATCH_GDNS_PATH)
	if script == null:
		_on_error("bspatch_native_missing", false)
		return false
	var patcher = script.new()
	if patcher == null or not patcher.has_method("apply"):
		_on_error("bspatch_native_invalid", false)
		return false
	var base_abs = _resolve_base_binary_path() if is_binary else _resolve_base_pck_path()
	if base_abs == "":
		_on_error("bspatch_base_missing", false)
		return false
	# La lib nativa hace todo el I/O en C con rutas absolutas del SO.
	var patch_abs = ProjectSettings.globalize_path(patch_path)
	var out_abs = ProjectSettings.globalize_path(out_path)
	var rc = patcher.apply(base_abs, patch_abs, out_abs)
	if rc != 0:
		_on_error("bspatch_apply_failed:" + str(rc), false)
		return false
	return true

func _handle_chunk_error(code):
	_chunk_retries += 1
	if _chunk_retries > 3:
		_on_error("download_failed:" + code, true)
		return

	var backoff = [0, 1, 3, 10][_chunk_retries]
	yield(get_tree().create_timer(backoff), "timeout")
	_download_next_chunk()

func _finalize_download():
	_free_download_request()
	_set_state(State.VERIFYING)

	if _active_download.get("kind") == "apk":
		_finalize_apk_download()
		return

	var artifact_id = _active_download["artifact_id"]
	var is_binary = _active_download.get("is_binary", false)
	var part_path = STAGING_DIR + artifact_id + ".part"
	var final_path = PACKAGE_DIR + artifact_id + (".bin" if is_binary else ".pck")

	var f = File.new()
	# El .part es lo que se transportó (el .gz si viene comprimido); su sha256
	# verifica la integridad de la descarga.
	if f.get_sha256(part_path) != _active_download["sha256"]:
		_on_error("artifact_hash_mismatch", false)
		return

	var d = Directory.new()
	var is_delta = _active_download.get("is_delta", false)

	# Para un delta binario (bsdiff), lo que se transportó es un PATCH, no el .pck
	# final. El flujo es: [.gz patch] -> descomprimir a patch crudo -> bspatch(base,
	# patch) -> final_path (.pck nuevo reconstruido). Para un full, el artefacto ES
	# el .pck (o su .gz), así que solo descomprimir/renombrar.
	if is_delta:
		# 1) Materializar el patch crudo en disco (descomprimir si vino gzip).
		var patch_path = STAGING_DIR + artifact_id + ".patch"
		if _active_download.get("compression", "none") == "gzip":
			if not _decompress_gzip_to(part_path, patch_path, _active_download, "patch_sha256"):
				return  # _decompress_gzip_to ya llamó _on_error
			d.remove(part_path)
		else:
			if d.rename(part_path, patch_path) != OK:
				_on_error("promote_failed", false)
				return
		# 2) Aplicar bspatch sobre el .pck base actualmente activo.
		if not _apply_binary_patch(patch_path, final_path, is_binary):
			d.remove(patch_path)
			return  # _apply_binary_patch ya llamó _on_error
		d.remove(patch_path)
		# 3) Verificar el .pck RECONSTRUIDO contra uncompressed_sha256.
		var want = _active_download.get("uncompressed_sha256", "")
		if want != "" and f.get_sha256(final_path) != want:
			d.remove(final_path)
			_on_error("patched_pck_hash_mismatch", false)
			return
	else:
		# Si el artefacto vino comprimido (gzip), descomprimir a final_path y verificar
		# el sha del .pck resultante. Si no, basta con renombrar.
		if _active_download.get("compression", "none") == "gzip":
			if not _decompress_gzip_to(part_path, final_path, _active_download):
				return  # _decompress_gzip_to ya llamó _on_error
			d.remove(part_path)
		else:
			if d.rename(part_path, final_path) != OK:
				_on_error("promote_failed", false)
				return

	d.remove(STAGING_DIR + artifact_id + ".state.json")

	# Create pending boot. Un delta bsdiff reconstruye el .pck COMPLETO de la versión
	# nueva, así que reemplaza al base (no es un overlay encadenado): el boot carga un
	var artifact_hash = _active_download["sha256"]
	if is_delta or _active_download.get("compression", "none") == "gzip":
		artifact_hash = _active_download.get("uncompressed_sha256", artifact_hash)

	_staged_artifacts.append({
		"id": artifact_id,
		"hash": artifact_hash,
		"is_binary": is_binary
	})

	_download_next_in_queue()

func _finalize_all_downloads():
	var package_ids = []
	var package_hashes = {}
	var pending_binary = {}

	for artifact in _staged_artifacts:
		if artifact.is_binary:
			pending_binary = {
				"id": artifact.id,
				"hash": artifact.hash
			}
		else:
			package_ids.append(artifact.id)
			package_hashes[artifact.id] = artifact.hash

	var pending = {
		"manifest_id": _pending_update["manifest_id"],
		"build_id": _pending_update["build_id"],
		"release_sequence": _pending_update["release_sequence"],
		"package_ids": package_ids,
		"package_hashes": package_hashes,
		"pending_binary": pending_binary,
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
		var absolute_apk_path: String = ProjectSettings.globalize_path(apk_path)
		if Engine.has_singleton("OdiseaUpdater"):
			var updater: Object = Engine.get_singleton("OdiseaUpdater")
			if updater.install_apk(absolute_apk_path):
				_set_state(State.APPLYING_EXTERNAL)
			else:
				_on_error("apk_installer_failed", true)
		else:
			# Old Android builds do not contain the FileProvider bridge. Sending the
			# player to the GitHub release still lets them bootstrap into a build that
			# supports in-app APK installation.
			var downloads_url: String = _pending_update.get("release_notes_url", _pending_update.get("downloads_page", ""))
			if downloads_url != "":
				OS.shell_open(downloads_url)
				_set_state(State.APPLYING_EXTERNAL)
			else:
				_on_error("apk_installer_unavailable", false)
	else:
		_on_error("apk_promote_failed", false)

func _finalize_web_update(pending):
	# JavaScript call to navigate with cache busting
	if JavaScript:
		var build_id = pending["build_id"]
		JavaScript.eval("window.location.href = window.location.pathname + '?build_id=' + '" + build_id + "';")
	_set_state(State.READY_TO_RESTART)

func _check_pending_boot():
	if Engine.editor_hint:
		return
	var pending = _load_json(PENDING_BOOT_FILE, {})
	if pending.empty():
		_load_active_packages()
		return

	if _packaged_build_supersedes(pending):
		print("[UpdateManager] Packaged build supersedes pending update ", pending.get("build_id", ""), "; ignoring pending package.")
		Directory.new().remove(PENDING_BOOT_FILE)
		_load_active_packages()
		return

	pending["attempts"] = pending.get("attempts", 0) + 1
	_save_json(PENDING_BOOT_FILE, pending)

	if pending["attempts"] > 2:
		print("[UpdateManager] Pending boot failed 2 times. Rolling back.")
		_rollback_pending()
		return

	# On Linux/macOS, the binary might have been replaced by the previous process.
	# On Windows, it should have been replaced by the updater.bat.
	# We check if a binary update IS STILL PENDING (hash mismatch).
	if pending.has("pending_binary") and not pending["pending_binary"].empty():
		var info = pending["pending_binary"]
		if File.new().get_sha256(OS.get_executable_path()) != info.hash:
			# Not updated yet? This could happen if the stub failed or on Linux if we just booted.
			# Try applying it now as a fallback.
			_apply_binary_update(info)

	# Aplicar el pending; si FALLA (p.ej. el package no es un .pck válido, o falta),
	# revertir YA al build instalado en vez de quedar en un estado roto y crashear.
	if not _apply_packages(pending["package_ids"], pending.get("package_hashes", {})):
		print("[UpdateManager] Pending package(s) failed to apply. Rolling back.")
		_rollback_pending()

func _apply_binary_update(info: Dictionary) -> bool:
	var bin_path = PACKAGE_DIR + info.id + ".bin"
	var f = File.new()
	if not f.file_exists(bin_path):
		print("[UpdateManager] Binary update file missing: ", bin_path)
		return false

	var exe_path = OS.get_executable_path()
	if f.get_sha256(exe_path) == info.hash:
		print("[UpdateManager] Binary already matches target hash.")
		return true

	if f.get_sha256(bin_path) != info.hash:
		print("[UpdateManager] Binary update source hash mismatch.")
		return false

	var backup_path = UPDATE_DIR + "backup_binary"
	var d = Directory.new()
	# Backup current binary
	if d.file_exists(backup_path):
		d.remove(backup_path)

	if OS.get_name() == "Windows":
		# Direct replacement on Windows is usually locked.
		return d.copy(bin_path, exe_path) == OK
	else:
		# Linux/macOS atomic swap
		if d.copy(exe_path, backup_path) != OK:
			print("[UpdateManager] Failed to backup current binary.")

		if d.rename(bin_path, exe_path) == OK:
			if OS.get_name() == "Linux":
				OS.execute("chmod", ["+x", exe_path], true)
			print("[UpdateManager] Binary updated successfully.")
			return true

	return false

# Descarta el pending (boot fallido), borra sus packages no confirmados, y carga
# los packages confirmados (build instalado) para arrancar en un estado sano.
func _rollback_pending() -> void:
	var pending = _load_json(PENDING_BOOT_FILE, {})
	var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})

	var d = Directory.new()

	# Rollback binary if needed
	if pending.has("pending_binary") and not pending["pending_binary"].empty():
		var backup_path = UPDATE_DIR + "backup_binary"
		var exe_path = OS.get_executable_path()
		if d.file_exists(backup_path):
			d.rename(backup_path, exe_path)
			if OS.get_name() == "Linux":
				OS.execute("chmod", ["+x", exe_path], true)

	var keep = confirmed.get("package_ids", [])
	for id in pending.get("package_ids", []):
		if not id in keep:
			d.remove(PACKAGE_DIR + id + ".pck")
			d.remove(PACKAGE_DIR + id + ".bin")

	d.remove(PENDING_BOOT_FILE)
	_load_active_packages()

func _load_active_packages():
	var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
	if confirmed.has("package_ids"):
		if _packaged_build_supersedes(confirmed):
			print("[UpdateManager] Packaged build supersedes confirmed update ", confirmed.get("build_id", ""), "; ignoring installed package.")
			_clear_confirmed_update_state()
			return
		_apply_packages(confirmed["package_ids"])

func _packaged_build_supersedes(update_state: Dictionary) -> bool:
	var packaged_bid := _get_build_meta_value("build_id")
	var state_bid := str(update_state.get("build_id", ""))
	return _is_build_id_newer(packaged_bid, state_bid)

func _is_build_id_newer(candidate: String, baseline: String) -> bool:
	if candidate == "" or baseline == "":
		return false
	if not candidate.is_valid_integer() or not baseline.is_valid_integer():
		return false
	return int(candidate) > int(baseline)

func _clear_confirmed_update_state() -> void:
	Directory.new().remove(CONFIRMED_BOOT_FILE)
	_local_state["active_package_ids"] = []
	_save_json(STATE_FILE, _local_state)

# Devuelve true si TODOS los packages requeridos se aplicaron; false si alguno
# faltaba, tenía hash inválido o no cargó (para que el caller pueda revertir).
func _apply_packages(package_ids: Array, p_hashes: Dictionary = {}) -> bool:
	var package_hashes = p_hashes
	if package_hashes.empty():
		var confirmed = _load_json(CONFIRMED_BOOT_FILE, {})
		package_hashes = confirmed.get("package_hashes", {})

	var all_ok := true
	for id in package_ids:
		var path = PACKAGE_DIR + id + ".pck"
		var f = File.new()
		if not f.file_exists(path):
			print("[UpdateManager] Missing package: ", id)
			all_ok = false
			continue

		# Re-verify SHA-256 before loading
		if package_hashes.has(id):
			var expected_hash = package_hashes[id]
			if f.get_sha256(path) != expected_hash:
				print("[UpdateManager] Hash mismatch for package ", id, ". Skipping load.")
				all_ok = false
				continue

		if not ProjectSettings.load_resource_pack(path, true):
			print("[UpdateManager] Failed to load package: ", id)
			all_ok = false
		else:
			# El pck nuevo trae su propio build_meta.json -> invalidar el cache para que
			# get_local_build_info()/VersionLabel reflejen la versión recién aplicada y no
			# la del boot (ProjectSettings queda con la vieja, por eso build_meta manda).
			_build_meta_cache = {}
	return all_ok

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
