extends Node

var player_scene := preload("res://players/elias/Pilot.tscn")
var player: Node = null
var _initial_spawn_transform := Transform()
var last_checkpoint_transform = null
var _default_cam_h_deg = null
var _default_cam_v_deg = null
var _default_camrot_h = null
var _default_camrot_v = null

func is_spawned() -> bool:
	return player != null and is_instance_valid(player)

func spawn(initial_transform: Transform = Transform()) -> Node:
	if is_spawned():
		return player
	player = player_scene.instance()
	# Defer child addition until scene is ready to avoid 'Parent node is busy' error
	call_deferred("_deferred_spawn", initial_transform)
	_initial_spawn_transform = initial_transform
	return player

func _deferred_spawn(initial_transform: Transform):
	if not is_instance_valid(player):
		player = player_scene.instance()
	var scene = get_tree().get_current_scene()
	if scene:
		scene.add_child(player)
		# No establecer owner manualmente; al estar bajo la escena, es válido.
	else:
		get_tree().get_root().add_child(player)
	player.global_transform = initial_transform
	# Capturar ángulos por defecto de cámara del prefab en el primer spawn
	var camroot = player.get_node_or_null("Camroot")
	if camroot:
		var h = camroot.get_node_or_null("h")
		var v = null
		if h:
			v = h.get_node_or_null("v")
		if h and _default_cam_h_deg == null:
			_default_cam_h_deg = rad2deg(h.rotation.y)
		if v and _default_cam_v_deg == null:
			_default_cam_v_deg = rad2deg(v.rotation.x)
		# También capturamos el estado interno de CameraTemplate si existe
		if _default_camrot_h == null and "camrot_h" in camroot:
			_default_camrot_h = camroot.camrot_h
		if _default_camrot_v == null and "camrot_v" in camroot:
			_default_camrot_v = camroot.camrot_v

func despawn():
	if is_spawned():
		player.queue_free()
		player = null

func get_player() -> Node:
	return player

func set_checkpoint(t: Transform) -> void:
	last_checkpoint_transform = t

func respawn() -> void:
	if not is_spawned():
		spawn(_initial_spawn_transform)
		return
	var target := _initial_spawn_transform
	if last_checkpoint_transform != null:
		target = last_checkpoint_transform
	player.global_transform = target
	# Reset de cámara al respawn: soporta rig antiguo (Camroot/h/v) y nuevo (CameraRig/Yaw/Pitch)
	var camroot = player.get_node_or_null("Camroot")
	var camrig = player.get_node_or_null("CameraRig")
	if camroot:
		var h = camroot.get_node_or_null("h")
		var v = h and h.get_node_or_null("v")
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
		var pitch = yaw and yaw.get_node_or_null("Pitch")
		if yaw and _default_cam_h_deg != null:
			yaw.rotation_degrees.y = _default_cam_h_deg
		if pitch and _default_cam_v_deg != null:
			pitch.rotation_degrees.x = _default_cam_v_deg
	# Limpiar estado transitorio del Player tras mover
	if player and player.has_method("reset_state_for_respawn"):
		player.reset_state_for_respawn()
