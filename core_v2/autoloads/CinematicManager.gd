extends Node

# CinematicManager.gd - Autoload for managing cinematic rigs and transitions

enum ControlMode {
	FREE,
	SIDESCROLL,
	LOCKED_VIEW,
	FIXED_AXIS
}

var active_rig = null
var current_control_mode = ControlMode.FREE

signal cinematic_started(rig_id)
signal cinematic_stopped
signal control_mode_changed(mode)

# For interpolation
var _is_transitioning := false
var _is_exit_transition := false
var _transition_timer := 0.0
var _transition_duration := 0.0
var _trans_camera: Camera = null
var _source_transform: Transform
var _source_fov: float
var _exit_target_cam: Camera = null

func _ready():
	# Create a helper camera for transitions if needed, or we just manipulate the active rig's camera
	_trans_camera = Camera.new()
	_trans_camera.name = "CinematicTransitionCamera"
	_trans_camera.current = false
	add_child(_trans_camera)

func activate_rig(rig_id: String, control_mode: int = ControlMode.FREE):
	var rigs = get_tree().get_nodes_in_group("cinematic_rigs")
	var target_rig = null
	for rig in rigs:
		if rig.name == rig_id or (rig.has("rig_id") and rig.rig_id == rig_id):
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
	
	# Guard: skip if this rig is already active or we're transitioning to it
	if active_rig == target_rig:
		print("[CinematicManager] Skipping - rig already active: ", target_rig.name)
		return
	
	# Guard: if we're in an enter transition, don't interrupt it
	if _is_transitioning and not _is_exit_transition:
		print("[CinematicManager] Skipping - enter transition in progress")
		return
	
	var new_cam = target_rig.get_camera() if target_rig.has_method("get_camera") else null
	if not new_cam:
		printerr("[CinematicManager] Rig has no camera: ", target_rig.name)
		return

	# Use provided old_camera or find player camera deterministically
	if old_camera == null:
		old_camera = _find_player_camera()
	
	print("[CinematicManager] ACTIVATE rig=", target_rig.name, " old_cam=", old_camera, " trans_camera=", _trans_camera)
	
	current_control_mode = control_mode
	emit_signal("control_mode_changed", control_mode)

	# CinematicManager handles all transitions
	var trans_time = target_rig.transition_time if "transition_time" in target_rig else 0.0
	
	print("[CinematicManager] trans_time=", trans_time, " old_camera!=trans=", old_camera != _trans_camera)
	
	if trans_time > 0 and old_camera and old_camera != _trans_camera:
		print("[CinematicManager] Starting ENTER transition")
		_start_transition(old_camera, new_cam, trans_time, target_rig)
	else:
		print("[CinematicManager] Applying rig directly (no transition)")
		_apply_rig(target_rig)

	emit_signal("cinematic_started", target_rig.name)

func deactivate_rig():
	print("[CinematicManager] DEACTIVATE called, active_rig=", active_rig, " _is_exit_transition=", _is_exit_transition)
	
	# Guard: if we're already in an exit transition, don't interrupt it
	if _is_exit_transition:
		print("[CinematicManager] Skipping - exit transition already in progress")
		return
	
	if not active_rig:
		return
	
	var rig_cam = active_rig.get_camera() if active_rig.has_method("get_camera") else null
	var trans_time = active_rig.transition_time if "transition_time" in active_rig else 0.0
	var player_cam = _find_player_camera()
	
	print("[CinematicManager] rig_cam=", rig_cam, " trans_time=", trans_time, " player_cam=", player_cam)
	
	active_rig.deactivate()
	active_rig = null
	current_control_mode = ControlMode.FREE
	emit_signal("control_mode_changed", ControlMode.FREE)
	
	# Start exit transition if we have valid cameras and transition time
	if trans_time > 0 and rig_cam and player_cam:
		print("[CinematicManager] Starting EXIT transition")
		_start_exit_transition(rig_cam, player_cam, trans_time)
	else:
		print("[CinematicManager] Immediate switch to player cam")
		# Immediate switch
		if player_cam:
			player_cam.current = true
		_is_transitioning = false
		_is_exit_transition = false
	
	emit_signal("cinematic_stopped")


func _start_exit_transition(from_cam: Camera, to_cam: Camera, duration: float):
	"""Start transition FROM rig camera TO player camera (current position)."""
	_source_transform = from_cam.global_transform
	_source_fov = from_cam.fov
	_exit_target_cam = to_cam
	_transition_duration = duration
	_transition_timer = 0.0
	_is_transitioning = true
	_is_exit_transition = true
	
	_trans_camera.global_transform = _source_transform
	_trans_camera.fov = _source_fov
	_trans_camera.current = true

func _find_player_camera() -> Camera:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_node("CameraRig/SpringArm/Camera"):
			return p.get_node("CameraRig/SpringArm/Camera") as Camera
		# Generic search if standard path fails
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

func _start_transition(from_cam: Camera, _to_cam: Camera, duration: float, rig: Spatial):
	active_rig = rig
	_source_transform = from_cam.global_transform
	_source_fov = from_cam.fov
	_transition_duration = duration
	_transition_timer = 0.0
	_is_transitioning = true
	_is_exit_transition = false # Ensure this is an ENTER transition

	_trans_camera.global_transform = _source_transform
	_trans_camera.fov = _source_fov
	_trans_camera.current = true

	# We don't activate the rig's camera yet to avoid jumping
	if active_rig.has_method("activate"):
		# Pass false to NOT set its camera as current yet
		active_rig.activate(false)

func _apply_rig(rig):
	if active_rig and active_rig != rig:
		active_rig.deactivate()

	active_rig = rig
	active_rig.activate(true) # Set current = true
	_is_transitioning = false
	_is_exit_transition = false

func _process(_delta):
	# Only handle non-transition logic here, transitions are now in step()
	pass

func step(delta: float):
	if not _is_transitioning:
		return
	
	_transition_timer += delta
	var t = clamp(_transition_timer / _transition_duration, 0.0, 1.0)
	
	# Simple ease in-out (smoothstep)
	var weight = t * t * (3.0 - 2.0 * t)
	
	# print("[CinematicManager] step: t=", t, " weight=", weight, " exit=", _is_exit_transition)
	
	if _is_exit_transition:
		# Exit transition: interpolate toward CURRENT player camera position
		if _exit_target_cam and is_instance_valid(_exit_target_cam):
			var target_transform = _exit_target_cam.global_transform
			var target_fov = _exit_target_cam.fov
			_trans_camera.global_transform = _source_transform.interpolate_with(target_transform, weight)
			_trans_camera.fov = lerp(_source_fov, target_fov, weight)
			
			if t >= 1.0:
				print("[CinematicManager] Exit transition COMPLETE. Switching to player cam.")
				_is_transitioning = false
				_is_exit_transition = false
				_exit_target_cam.current = true
				_exit_target_cam = null
	else:
		# Enter transition: interpolate toward rig camera
		if active_rig:
			var target_cam = active_rig.get_camera()
			if target_cam:
				# Debug stuck camera: check transforms
				# var t_orig = _trans_camera.global_transform.origin
				# var t_targ = target_cam.global_transform.origin
				# print("Trans from ", t_orig, " to ", t_targ)
				_trans_camera.global_transform = _source_transform.interpolate_with(target_cam.global_transform, weight)
				_trans_camera.fov = lerp(_source_fov, target_cam.fov, weight)
				
				if t >= 1.0:
					print("[CinematicManager] Enter transition COMPLETE. Switching to rig cam.")
					_is_transitioning = false
					target_cam.current = true

func get_active_camera() -> Camera:
	if _is_transitioning:
		return _trans_camera
	if active_rig:
		return active_rig.get_camera()
	return get_viewport().get_camera()

func get_control_mode() -> int:
	return current_control_mode

func is_active() -> bool:
	return _is_transitioning or active_rig != null

func get_full_snapshot() -> Dictionary:
	var snapshot = {
		"current_control_mode": current_control_mode,
		"is_transitioning": _is_transitioning,
		"transition_timer": _transition_timer,
		"transition_duration": _transition_duration,
		"source_transform": {
			"origin": _source_transform.origin,
			"basis": {
				"x": _source_transform.basis.x,
				"y": _source_transform.basis.y,
				"z": _source_transform.basis.z
			}
		},
		"source_fov": _source_fov,
	}
	if active_rig:
		snapshot["active_rig_path"] = active_rig.get_path()
	else:
		snapshot["active_rig_path"] = ""
	
	# Include current camera path for deterministic restoration
	var current_cam = get_viewport().get_camera()
	if current_cam:
		snapshot["current_camera_path"] = current_cam.get_path()
	else:
		snapshot["current_camera_path"] = ""
	
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	current_control_mode = data.get("current_control_mode", ControlMode.FREE)
	_is_transitioning = data.get("is_transitioning", false)
	_transition_timer = data.get("transition_timer", 0.0)
	_transition_duration = data.get("transition_duration", 0.0)
	var source_trans_data = data.get("source_transform", {"origin": [0, 0, 0], "basis": {"x": [1, 0, 0], "y": [0, 1, 0], "z": [0, 0, 1]}})
	var basis_data = source_trans_data["basis"]
	var x = Vector3(basis_data["x"][0], basis_data["x"][1], basis_data["x"][2])
	var y = Vector3(basis_data["y"][0], basis_data["y"][1], basis_data["y"][2])
	var z = Vector3(basis_data["z"][0], basis_data["z"][1], basis_data["z"][2])
	var basis = Basis(x, y, z)
	var origin = Vector3(source_trans_data["origin"][0], source_trans_data["origin"][1], source_trans_data["origin"][2])
	_source_transform = Transform(basis, origin)
	_source_fov = data.get("source_fov", 70.0)
	
	var rig_path = data.get("active_rig_path", "")
	if rig_path != "":
		active_rig = get_node(rig_path)
		if active_rig:
			var cam = active_rig.get_camera()
			if cam:
				cam.current = true
	else:
		active_rig = null
	
	# Restore current camera
	var cam_path = data.get("current_camera_path", "")
	if cam_path != "":
		var cam = get_node(cam_path)
		if cam and cam is Camera:
			cam.current = true
