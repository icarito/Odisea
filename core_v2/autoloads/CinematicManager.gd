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
var latched_camera_basis = Basis.IDENTITY
var latched_control_mode = ControlMode.FREE
var latch_active := false
var _transition_active := false
var _transition_start_time := 0.0
var _transition_duration := 0.0
var _transition_from_cam: Camera = null
var _transition_to_cam: Camera = null
var _transition_start_transform: Transform
var _transition_start_fov: float

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
	var trans_time = 0.5 # Default exit transition time
	if active_rig.has_method("get_transition_time"):
		trans_time = active_rig.get_transition_time()
	elif "transition_time" in active_rig:
		trans_time = active_rig.transition_time
	
	var player_cam = _find_player_camera()
	
	if active_rig.has_method("deactivate"):
		active_rig.deactivate(false)
			
	active_rig = null
	current_control_mode = ControlMode.FREE
	emit_signal("control_mode_changed", ControlMode.FREE)
	
	if trans_time > 0 and rig_cam and player_cam:
		# Use our custom dynamic transition
		_start_dynamic_transition(rig_cam, player_cam, trans_time)
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

func _start_dynamic_transition(from: Camera, to: Camera, duration: float):
	_transition_active = true
	_transition_start_time = OS.get_ticks_msec() / 1000.0
	_transition_duration = duration
	_transition_from_cam = from
	_transition_to_cam = to
	_transition_start_transform = from.global_transform
	_transition_start_fov = from.fov
	
	# Ensure the 'to' camera is NOT current yet, but we need a camera to render
	# We can use the 'from' camera or a temporary one. 
	# Actually, CameraTransition uses a dedicated internal camera. 
	# Here we will manipulate the 'to' camera but keep it 'current' from the start?
	# No, if we make 'to' current, it will jump to its position unless we override its transform.
	# Better approach: Use CameraTransition's camera3D but control it ourselves?
	# Or clearer: We hijack the 'from' camera (if possible) or just use the Viewport's current.
	
	# Let's use CameraTransition's singleton camera for the blend
	if CameraTransition.camera3D:
		CameraTransition.camera3D.current = true
		CameraTransition.camera3D.global_transform = _start_dynamic_transform()
		CameraTransition.camera3D.fov = _transition_start_fov

func _start_dynamic_transform() -> Transform:
	return _transition_start_transform

func _process(delta: float):
	if _transition_active:
		var now = OS.get_ticks_msec() / 1000.0
		var elapsed = now - _transition_start_time
		if elapsed >= _transition_duration:
			_finish_dynamic_transition()
		else:
			var t = elapsed / _transition_duration
			# Ease InOut Cubic
			t = -0.5 * (cos(PI * t) - 1)
			
			if is_instance_valid(_transition_to_cam) and CameraTransition.camera3D:
				# Interpolate from Fixed Start to Moving Target
				var target_tx = _transition_to_cam.global_transform
				var target_fov = _transition_to_cam.fov
				
				var new_tx = _transition_start_transform.interpolate_with(target_tx, t)
				var new_fov = lerp(_transition_start_fov, target_fov, t)
				
				CameraTransition.camera3D.global_transform = new_tx
				CameraTransition.camera3D.fov = new_fov

func _finish_dynamic_transition():
	_transition_active = false
	if is_instance_valid(_transition_to_cam):
		_transition_to_cam.current = true
	emit_signal("cinematic_stopped")

func step(_delta: float):
	pass

func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"current_control_mode": current_control_mode,
		"latched_camera_basis": [
			latched_camera_basis.x.x, latched_camera_basis.x.y, latched_camera_basis.x.z,
			latched_camera_basis.y.x, latched_camera_basis.y.y, latched_camera_basis.y.z,
			latched_camera_basis.z.x, latched_camera_basis.z.y, latched_camera_basis.z.z
		],
		"latched_control_mode": latched_control_mode,
		"latch_active": latch_active
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
	var lb = data.get("latched_camera_basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	latched_camera_basis = Basis(
		Vector3(lb[0], lb[1], lb[2]),
		Vector3(lb[3], lb[4], lb[5]),
		Vector3(lb[6], lb[7], lb[8])
	)
	latched_control_mode = data.get("latched_control_mode", ControlMode.FREE)
	latch_active = data.get("latch_active", false)
	
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
