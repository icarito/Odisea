extends Node

signal new_version_available(version_data)

const CHECK_INTERVAL_SECONDS = 1800 # 30 minutes
const CENTRAL_URL = "https://odisea.educa.juegos/game/version"

var has_update := false
var latest_version_data := {}
var _check_timer: Timer

func _ready():
	_check_timer = Timer.new()
	_check_timer.wait_time = CHECK_INTERVAL_SECONDS
	_check_timer.one_shot = false
	_check_timer.connect("timeout", self, "check_for_updates")
	add_child(_check_timer)

	# Small delay to let the game initialize and potentially have internet access settled
	yield(get_tree().create_timer(5.0), "timeout")
	check_for_updates()
	_check_timer.start()

func check_for_updates():
	var http = HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", self, "_on_request_completed", [http])

	var err = http.request(CENTRAL_URL)
	if err != OK:
		printerr("[VersionChecker] Failed to start HTTP request: ", err)
		http.queue_free()

func _on_request_completed(result, response_code, _headers, body, http_node):
	http_node.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[VersionChecker] Request failed or server returned non-200. Silently ignoring.")
		return

	var json_res = JSON.parse(body.get_string_from_utf8())
	if json_res.error != OK:
		print("[VersionChecker] Failed to parse JSON response. Silently ignoring.")
		return

	var data = json_res.result
	if typeof(data) != TYPE_DICTIONARY or not data.has("version"):
		print("[VersionChecker] Invalid data format in response. Silently ignoring.")
		return

	var remote_version = data["version"]
	var local_version = Constants.GAME_VERSION

	if _is_newer_version(local_version, remote_version):
		has_update = true
		latest_version_data = data
		emit_signal("new_version_available", data)
		print("[VersionChecker] New version available: ", remote_version, " (Local: ", local_version, ")")
	else:
		print("[VersionChecker] Game is up to date (", local_version, ")")

func _is_newer_version(p_local: String, p_remote: String) -> bool:
	# Simple semantic version comparison or just different string comparison if one is v0.x.x
	# For simplicity as requested, if remote != local and remote is not v0.0.0
	if p_remote == "v0.0.0" or p_remote == "":
		return false

	if p_local == p_remote:
		return false

	# Basic SemVer-ish comparison
	var local_parts = p_local.replace("v", "").split(".")
	var remote_parts = p_remote.replace("v", "").split(".")

	for i in range(min(local_parts.size(), remote_parts.size())):
		var lp = int(local_parts[i])
		var rp = int(remote_parts[i])
		if rp > lp:
			return true
		if lp > rp:
			return false

	return remote_parts.size() > local_parts.size()
