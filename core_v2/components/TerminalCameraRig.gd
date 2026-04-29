extends Spatial
class_name TerminalCameraRig

# TerminalCameraRig.gd - Orchestrates cinematic/focus camera modes for terminals
# Extracted from HoloTerminalV2 for reusability and cleaner architecture.

signal focus_entered()
signal focus_exited()

export(bool) var use_cinematic_zone := true
export(bool) var close_on_exit_zone := true
export(bool) var allow_focus_mode := true
export(int, "Fixed", "Follow Player") var cinematic_camera_behavior := 0 setget _set_cinematic_camera_behavior

enum CinematicCameraBehavior {
	CAMERA_FIXED,
	CAMERA_FOLLOW_PLAYER,
}

var _camera_zone: Area = null
var _cinematic_rig = null
var _focused_rig = null
var _terminal: Node = null
var _player_in_zone := false
var _is_focused := false
var _locked_player: Node = null
var _prev_hardware_input_enabled := true
var _focus_camera_request_id := -1

func _ready():
	pass

func initialize(terminal: Node, cinematic_setup_path: NodePath = NodePath("CinematicSetup")) -> void:
	_terminal = terminal
	if Engine.editor_hint:
		return
	
	_camera_zone = terminal.get_node_or_null(cinematic_setup_path.get_subname(0) + "/CameraZone")
	_cinematic_rig = terminal.get_node_or_null(cinematic_setup_path.get_subname(0) + "/CinematicPathRig")
	_focused_rig = terminal.get_node_or_null(cinematic_setup_path.get_subname(0) + "/FocusedRig")
	
	if _camera_zone and "is_zone_active" in _camera_zone:
		_camera_zone.is_zone_active = use_cinematic_zone
	
	if _cinematic_rig:
		_apply_cinematic_camera_behavior()
	
	_deactivate_terminal_cameras()
	
	if _camera_zone:
		if not _camera_zone.is_connected("body_entered", self, "_on_camera_zone_body_entered"):
			_camera_zone.connect("body_entered", self, "_on_camera_zone_body_entered")
		if not _camera_zone.is_connected("body_exited", self, "_on_camera_zone_body_exited"):
			_camera_zone.connect("body_exited", self, "_on_camera_zone_body_exited")

func _set_cinematic_camera_behavior(value: int) -> void:
	cinematic_camera_behavior = int(clamp(value, 0, 1))
	_apply_cinematic_camera_behavior()

func _apply_cinematic_camera_behavior() -> void:
	if not _cinematic_rig or not is_instance_valid(_cinematic_rig):
		return
	var follow_player = cinematic_camera_behavior == CinematicCameraBehavior.CAMERA_FOLLOW_PLAYER

	if "track_player" in _cinematic_rig:
		_cinematic_rig.set("track_player", follow_player)
	if "follow_player_on_path" in _cinematic_rig:
		_cinematic_rig.set("follow_player_on_path", follow_player)
	if _cinematic_rig.has_method("_update_rotation_mode"):
		_cinematic_rig.call("_update_rotation_mode")

	var follow_node = _cinematic_rig.get_node_or_null("Follow")
	if follow_node and "enabled" in follow_node:
		follow_node.set("enabled", follow_player)
	var look_at_node = _cinematic_rig.get_node_or_null("LookAt")
	if look_at_node and "enabled" in look_at_node:
		look_at_node.set("enabled", follow_player)

func _deactivate_terminal_cameras() -> void:
	if not _terminal:
		return
	var path_cam = _terminal.get_node_or_null("CinematicSetup/CinematicPathRig/PathFollow/Camera")
	if path_cam and path_cam is Camera:
		(path_cam as Camera).current = false
	var focus_cam = _terminal.get_node_or_null("CinematicSetup/FocusedRig/Camera")
	if focus_cam and focus_cam is Camera:
		(focus_cam as Camera).current = false

func is_focused() -> bool:
	return _is_focused

func is_player_in_zone() -> bool:
	return _player_in_zone

func enter_focus_mode() -> void:
	if _is_focused:
		return
	
	if not _focused_rig:
		push_warning("[TerminalCameraRig] Cannot enter focus mode: FocusedRig not found")
		return
	
	_is_focused = true
	_set_player_input_blocked(true)
	print("[TerminalCameraRig] Entering focus mode, activating FocusedRig")
	_request_focus_camera_rig(_focused_rig)
	emit_signal("focus_entered")

func exit_focus_mode() -> void:
	if not _is_focused:
		return
	
	_is_focused = false
	_set_player_input_blocked(false)
	_release_focus_camera_request()
	
	if not use_cinematic_zone and _camera_zone and "is_zone_active" in _camera_zone:
		_camera_zone.is_zone_active = false
	
	print("[TerminalCameraRig] Exiting focus mode")
	emit_signal("focus_exited")

func toggle_focus_mode() -> void:
	if _is_focused:
		exit_focus_mode()
	else:
		enter_focus_mode()

func set_zone_active(active: bool) -> void:
	if _camera_zone and "is_zone_active" in _camera_zone:
		_camera_zone.is_zone_active = active

func _on_camera_zone_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_zone = true

func _on_camera_zone_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	
	_player_in_zone = false
	
	if close_on_exit_zone and _terminal and "is_active" in _terminal:
		var is_active = _terminal.is_active if _terminal.has_method("get_is_active") else _terminal.get("is_active")
		if is_active:
			_terminal.call_deferred("set_active", false)

func _set_player_input_blocked(blocked: bool) -> void:
	var player = _find_player()
	if player == null:
		return
	if blocked:
		if _locked_player and is_instance_valid(_locked_player):
			return
		_locked_player = player
		if "input_provider" in player and player.input_provider:
			_prev_hardware_input_enabled = bool(player.input_provider.hardware_input_enabled)
			player.input_provider.hardware_input_enabled = false
		else:
			_prev_hardware_input_enabled = true
		if player.has_method("set_camera_input_locked"):
			player.call("set_camera_input_locked", true)
	elif _locked_player and is_instance_valid(_locked_player):
		if _locked_player.has_method("set_camera_input_locked"):
			_locked_player.call("set_camera_input_locked", false)
		if "input_provider" in _locked_player and _locked_player.input_provider:
			_locked_player.input_provider.hardware_input_enabled = _prev_hardware_input_enabled
		_locked_player = null

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _request_focus_camera_rig(rig: Node) -> void:
	_release_focus_camera_request()
	if rig == null or not is_instance_valid(rig):
		return
	var transition_time := 0.0
	if "transition_time" in rig:
		transition_time = float(rig.transition_time)
	var payload = {
		"rig": rig,
		"transition_time": transition_time,
		"latch_on_enter": true,
		"latch_on_exit": true,
	}
	if has_node("/root/CinematicManager") or get_tree().root.has_node("CinematicManager"):
		var cinematic_manager = get_tree().root.get_node("CinematicManager")
		if cinematic_manager and "request_camera_mode" in cinematic_manager:
			_focus_camera_request_id = cinematic_manager.request_camera_mode(
				1, # LOCKED_VIEW
				payload,
				"terminal_focus_" + _terminal.name if _terminal else "terminal_focus",
				12
			)

func _release_focus_camera_request() -> void:
	if _focus_camera_request_id == -1:
		return
	if has_node("/root/CinematicManager") or get_tree().root.has_node("CinematicManager"):
		var cinematic_manager = get_tree().root.get_node("CinematicManager")
		if cinematic_manager and "release_camera_request" in cinematic_manager:
			cinematic_manager.release_camera_request(_focus_camera_request_id)
	_focus_camera_request_id = -1

func _exit_tree() -> void:
	_release_focus_camera_request()
