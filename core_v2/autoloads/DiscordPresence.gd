extends Node

# DiscordPresence.gd
# Manager autoload for Discord Rich Presence with live telemetry integration.
# Part of OdiseaOS Telemetry / Discord Rich Presence System (FD-315).

const UPDATE_INTERVAL_MSEC := 15000 # 15 seconds Discord API throttle
const DiscordSDKScript = preload("res://core_v2/autoloads/DiscordPresenceSDK.gd")

var _sdk: Node = null
var _last_update_msec: int = 0
var _last_scene_name: String = ""
var _start_timestamp: int = 0
var _presence_active: bool = false
var _mock_mode: bool = false

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	_sdk = DiscordSDKScript.new()
	add_child(_sdk)

	_start_timestamp = OS.get_unix_time()

func enable_mock_mode(enabled: bool = true) -> void:
	_mock_mode = enabled
	if _sdk != null and _sdk.has_method("enable_mock_mode"):
		_sdk.enable_mock_mode(enabled)

func get_sdk() -> Node:
	return _sdk

func is_presence_allowed() -> bool:
	# Gate 1: Replay mode / hotzone playback gate
	var anna = get_node_or_null("/root/ANNAV2")
	if anna != null:
		if ("_replay_mode" in anna and anna._replay_mode) or ("_is_hotzone_playback" in anna and anna._is_hotzone_playback):
			return false

	# Gate 2: Telemetry consent (FD-292) and explicit opt-out
	var sm = get_node_or_null("/root/SettingsManager")
	if sm != null:
		var consent_asked = sm.get("consent_asked") if "consent_asked" in sm else false
		var telemetry_enabled = sm.get("telemetry_enabled") if "telemetry_enabled" in sm else false
		if not consent_asked or not telemetry_enabled:
			return false

		if "discord_presence_enabled" in sm and not sm.discord_presence_enabled:
			return false
	else:
		return false

	return true

func _process(_delta):
	var allowed = is_presence_allowed()

	if not allowed:
		if _presence_active:
			clear_presence()
		return

	var now_msec = OS.get_ticks_msec()
	var current_scene = _get_current_scene_name()

	var scene_changed = (current_scene != _last_scene_name)
	var time_passed = (now_msec - _last_update_msec >= UPDATE_INTERVAL_MSEC)

	if scene_changed:
		_last_scene_name = current_scene
		if _is_menu_scene(current_scene):
			_start_timestamp = OS.get_unix_time()
		_update_presence()
		_last_update_msec = now_msec
	elif time_passed or not _presence_active:
		_update_presence()
		_last_update_msec = now_msec

func _update_presence() -> void:
	if _sdk == null:
		return

	var current_scene = _get_current_scene_name()
	var is_menu = _is_menu_scene(current_scene)
	var is_paused = get_tree() != null and get_tree().paused

	var readable_zone = _get_readable_zone_name(current_scene)

	var details_text := ""
	var state_text := ""

	if is_menu:
		details_text = "En el menú de Odisea"
	elif is_paused:
		details_text = "En pausa - " + readable_zone
	else:
		details_text = "Explorando " + readable_zone

	var session_num_str = _get_session_display_id()
	if session_num_str != "":
		state_text = "Sesión #" + session_num_str
	else:
		state_text = "Sesión activa"

	if not is_menu and not is_paused:
		var fps = _get_current_fps()
		if fps > 0:
			state_text += " · " + str(fps) + " FPS"

	var activity = {
		"details": details_text,
		"state": state_text,
		"timestamps": {
			"start": _start_timestamp
		}
	}

	var success = _sdk.set_activity(activity)
	if success:
		_presence_active = true

func clear_presence() -> void:
	if _sdk != null:
		_sdk.clear_activity()
	_presence_active = false

func _get_current_scene_name() -> String:
	var tree = get_tree()
	if tree != null and tree.current_scene != null:
		var name = tree.current_scene.filename.get_file().get_basename()
		if name == "":
			name = tree.current_scene.name
		return name
	return "Main"

func _is_menu_scene(scene_name: String) -> bool:
	var name_lower = scene_name.to_lower()
	return name_lower in ["boot", "menu", "mainmenu", "pausemenu", "title"] or name_lower.find("menu") != -1

func _get_readable_zone_name(scene_name: String) -> String:
	var tree = get_tree()
	if tree != null and tree.current_scene != null:
		if tree.current_scene.has_meta("zone"):
			var zone_meta = String(tree.current_scene.get_meta("zone"))
			if zone_meta != "":
				return zone_meta

	match scene_name:
		"Dome_Intro", "DomeIntro":
			return "Domo de Introducción"
		"RingHub", "RingHub_Level", "RingHubWakeup":
			return "Anillo Central"
		"CoolantLab":
			return "Laboratorio de Criorefrigerante"
		"Room3DLab":
			return "Laboratorio Ambiental"
		"Prologue":
			return "Prólogo"
		_:
			return scene_name.capitalize()

func _get_session_display_id() -> String:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna != null and ("_session_id" in anna):
		var full_id = String(anna._session_id)
		if full_id != "":
			var parts = full_id.split("-")
			if parts.size() > 0:
				var unix_part = parts[0]
				if unix_part.length() >= 4:
					return unix_part.substr(unix_part.length() - 4, 4)
				return unix_part
	return "1"

func _get_current_fps() -> int:
	var perf = get_node_or_null("/root/PerformanceMonitor")
	if perf != null and ("_last_fps" in perf):
		return int(round(perf._last_fps))
	return int(round(Performance.get_monitor(Performance.TIME_FPS)))
