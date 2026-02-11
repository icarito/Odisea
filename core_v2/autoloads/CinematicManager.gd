extends Node

# CinematicManager.gd - Autoload for managing cinematic rigs and transitions
# Simplified to use CameraTransition plugin.

enum ControlMode {
	FREE,
	SIDESCROLL, # Legacy, keeping for compatibility but might be unused
	LOCKED_VIEW,
	FIXED_AXIS
}

var active_rig = null
var current_control_mode = ControlMode.FREE

signal cinematic_started(rig_id)
signal cinematic_stopped
signal control_mode_changed(mode)

func _ready():
	pass

func activate_rig(rig_id: String, control_mode: int = ControlMode.FREE):
	var rigs = get_tree().get_nodes_in_group("cinematic_rigs")
	var target_rig = null
	for rig in rigs:
		if rig.name == rig_id:
			target_rig = rig
			break
		if rig.get("rig_id") == rig_id:
			target_rig = rig
			break

	if not target_rig:
		printerr("[CinematicManager] Rig not found: ", rig_id)
		return

	activate_rig_direct(target_rig, control_mode)

func activate_rig_direct(target_rig: Spatial, control_mode: int = ControlMode.FREE, old_camera: Camera = null):
	"""Activate a rig directly by reference (preferred over string ID)."""
	if not target_rig:
		printerr("[CinematicManager] activate_rig_direct called with null rig")
		return
	
	if active_rig == target_rig:
		return
	
	var new_cam = target_rig.get_camera() if target_rig.has_method("get_camera") else null
	if not new_cam:
		printerr("[CinematicManager] Rig has no camera: ", target_rig.name)
		return

	if old_camera == null:
		old_camera = _find_player_camera()
		if not old_camera:
			old_camera = get_viewport().get_camera()

	# Notify change
	current_control_mode = control_mode
	emit_signal("control_mode_changed", control_mode)
	
	# Handle transition
	var trans_time = target_rig.transition_time if "transition_time" in target_rig else 0.0
	
	if active_rig:
		if active_rig.has_method("deactivate"):
			active_rig.deactivate(false) # Do not restore camera, we handle it

	active_rig = target_rig
	if active_rig.has_method("activate"):
		active_rig.activate(false) # Activate logic but don't force camera current yet

	if trans_time > 0 and old_camera and new_cam and old_camera != new_cam:
		CameraTransition.transition_camera3D(old_camera, new_cam, trans_time)
	else:
		# Immediate switch
		new_cam.current = true

	emit_signal("cinematic_started", target_rig.name)

func deactivate_rig():
	if not active_rig:
		return
	
	var rig_cam = active_rig.get_camera() if active_rig.has_method("get_camera") else null
	var trans_time = active_rig.transition_time if "transition_time" in active_rig else 0.0
	var player_cam = _find_player_camera()
	
	if active_rig.has_method("deactivate"):
		active_rig.deactivate(false)
			
	active_rig = null
	current_control_mode = ControlMode.FREE
	emit_signal("control_mode_changed", ControlMode.FREE)
	
	if trans_time > 0 and rig_cam and player_cam:
		CameraTransition.transition_camera3D(rig_cam, player_cam, trans_time)
	else:
		if player_cam:
			player_cam.current = true
	
	emit_signal("cinematic_stopped")

func _find_player_camera() -> Camera:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_node("CameraRig/SpringArm/Camera"):
			return p.get_node("CameraRig/SpringArm/Camera") as Camera
		var cam = _search_camera(p)
		if cam: return cam
	return null

func _search_camera(node: Node) -> Camera:
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _search_camera(node.get_child(i))
		if cam:
			return cam
	return null

func get_active_camera() -> Camera:
	if active_rig:
		return active_rig.get_camera()
	return get_viewport().get_camera()

func get_control_mode() -> int:
	return current_control_mode

func is_active() -> bool:
	return active_rig != null

# Compatibility for PlayerController or other systems calling step/force_finish
func force_finish_transition():
	# CameraTransition doesn't easily support force finish, but it's fine for now.
	pass

func step(_delta: float):
	pass

func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"current_control_mode": current_control_mode
	}
	if active_rig:
		snapshot["active_rig_path"] = active_rig.get_path()
	else:
		snapshot["active_rig_path"] = ""
	
	var current_cam = get_viewport().get_camera()
	if current_cam:
		snapshot["current_camera_path"] = current_cam.get_path()
	else:
		snapshot["current_camera_path"] = ""
	
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	current_control_mode = data.get("current_control_mode", ControlMode.FREE)
	
	var rig_path = data.get("active_rig_path", "")
	if rig_path != "":
		var rig = get_node(rig_path)
		if rig:
			active_rig = rig
			var cam = active_rig.get_camera()
			if cam:
				cam.current = true
	else:
		active_rig = null
	
	var cam_path = data.get("current_camera_path", "")
	if cam_path != "":
		var cam = get_node(cam_path)
		if cam and cam is Camera:
			cam.current = true
