extends Node

# PlayerManager (autoload: "PlayerManager")
# Responsibility: Centralizes the player's persistent state and interface,
# decoupling the PlayerController from gameplay logic.

# --- Properties ---
var player_health: int = 100
var respawn_point: Transform setget set_respawn_point
var player_reference: Node = null # Reference to the active PlayerController node

var player_scene := preload("res://players/elias/Pilot.tscn")
var _initial_spawn_transform := Transform()

# --- Private properties for camera state reset ---
var _default_cam_h_deg = null
var _default_cam_v_deg = null
var _default_camrot_h = null
var _default_camrot_v = null

# --- Signals ---
signal player_died()
signal health_updated(new_health)
signal player_respawned()


# --- Public API ---

func damage_player(amount: int) -> void:
	self.player_health -= amount
	emit_signal("health_updated", player_health)
	if player_health <= 0:
		emit_signal("player_died")
		respawn_player() # Or whatever the desired logic is on death

func respawn_player() -> void:
	if not is_spawned():
		spawn(_initial_spawn_transform)
		return

	var target_transform := _initial_spawn_transform
	if respawn_point != null:
		target_transform = respawn_point

	player_reference.global_transform = target_transform

	# Reset camera state on respawn
	_reset_camera_state()

	# Reset player's internal state (e.g., velocity)
	if player_reference and player_reference.has_method("reset_state_for_respawn"):
		player_reference.reset_state_for_respawn()

	emit_signal("player_respawned")

func set_respawn_point(new_respawn_point: Transform) -> void:
	respawn_point = new_respawn_point

# --- Node Management ---

func is_spawned() -> bool:
	return player_reference != null and is_instance_valid(player_reference)

func get_player() -> Node:
	return player_reference

func spawn(initial_transform: Transform) -> Node:
	if is_spawned():
		return player_reference
	player_reference = player_scene.instance()
	call_deferred("_deferred_spawn", initial_transform)
	_initial_spawn_transform = initial_transform
	return player_reference

func _deferred_spawn(initial_transform: Transform):
	if not is_instance_valid(player_reference):
		player_reference = player_scene.instance()
		
	var scene = get_tree().get_current_scene()
	if scene:
		scene.add_child(player_reference)
	else:
		get_tree().get_root().add_child(player_reference)
		
	player_reference.global_transform = initial_transform
	
	# Capture default camera angles from the prefab on the first spawn
	_capture_default_camera_state()


func despawn() -> void:
	if is_spawned():
		player_reference.queue_free()
		player_reference = null

# --- Private Helper Functions ---

func _capture_default_camera_state():
	if not is_spawned(): return
	
	var camroot = player_reference.get_node_or_null("Camroot")
	if camroot:
		var h = camroot.get_node_or_null("h")
		var v = h.get_node_or_null("v") if h else null
		
		if h and _default_cam_h_deg == null:
			_default_cam_h_deg = rad2deg(h.rotation.y)
		if v and _default_cam_v_deg == null:
			_default_cam_v_deg = rad2deg(v.rotation.x)
			
		if _default_camrot_h == null and "camrot_h" in camroot:
			_default_camrot_h = camroot.camrot_h
		if _default_camrot_v == null and "camrot_v" in camroot:
			_default_camrot_v = camroot.camrot_v

func _reset_camera_state():
	if not is_spawned(): return

	var camroot = player_reference.get_node_or_null("Camroot")
	var camrig = player_reference.get_node_or_null("CameraRig")

	if camroot:
		var h = camroot.get_node_or_null("h")
		var v = h.get_node_or_null("v") if h else null
		
		if h and _default_cam_h_deg != null:
			h.rotation_degrees.y = _default_cam_h_deg
			if "camrot_h" in camroot:
				camroot.camrot_h = _default_camrot_h if _default_camrot_h != null else _default_cam_h_deg
		if v and _default_cam_v_deg != null:
			v.rotation_degrees.x = _default_cam_v_deg
			if "camrot_v" in camroot:
				camroot.camrot_v = _default_camrot_v if _default_camrot_v != null else _default_cam_v_deg
	elif camrig:
		var yaw = camrig.get_node_or_null("Yaw")
		var pitch = yaw.get_node_or_null("Pitch") if yaw else null
		if yaw and _default_cam_h_deg != null:
			yaw.rotation_degrees.y = _default_cam_h_deg
		if pitch and _default_cam_v_deg != null:
			pitch.rotation_degrees.x = _default_cam_v_deg
