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
var _source_near: float
var _source_far: float
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
	
	# Guard: skip if this rig is already active or we're transitioning to it
	if active_rig == target_rig:
		# print("[CinematicManager] Skipping - rig already active: ", target_rig.name)
		return
	
	# Guard: if we're in an enter transition, don't interrupt it
	if _is_transitioning and not _is_exit_transition:
		# print("[CinematicManager] Skipping - enter transition in progress")
		return
	
	var new_cam = target_rig.get_camera() if target_rig.has_method("get_camera") else null
	if not new_cam:
		printerr("[CinematicManager] Rig has no camera: ", target_rig.name)
		return

	# Use provided old_camera or find player camera deterministically
	if old_camera == null:
		old_camera = _find_player_camera()
	
	# print("[CinematicManager] ACTIVATE rig=", target_rig.name, " old_cam=", old_camera, " trans_camera=", _trans_camera)
	
	current_control_mode = control_mode
	emit_signal("control_mode_changed", control_mode)

	# CinematicManager handles all transitions
	var trans_time = target_rig.transition_time if "transition_time" in target_rig else 0.0
	
	# print("[CinematicManager] trans_time=", trans_time, " old_camera!=trans=", old_camera != _trans_camera)
	
	if trans_time > 0 and old_camera and old_camera != _trans_camera:
		# print("[CinematicManager] Starting ENTER transition")
		_start_transition(old_camera, new_cam, trans_time, target_rig)
	else:
		# print("[CinematicManager] Applying rig directly (no transition)")
		_apply_rig(target_rig)

	emit_signal("cinematic_started", target_rig.name)

func deactivate_rig():
	# print("[CinematicManager] DEACTIVATE called, active_rig=", active_rig, " _is_exit_transition=", _is_exit_transition)
	# Guard: if we're already in an exit transition, don't interrupt it
	if _is_exit_transition:
		# print("[CinematicManager] Skipping - exit transition already in progress")
		return
	
	if not active_rig:
		return
	
	var rig_cam = active_rig.get_camera() if active_rig.has_method("get_camera") else null
	var trans_time = active_rig.transition_time if "transition_time" in active_rig else 0.0
	var player_cam = _find_player_camera()
	
	# print("[CinematicManager] rig_cam=", rig_cam, " trans_time=", trans_time, " player_cam=", player_cam)
	
	if active_rig.has_method("deactivate"):
		# Try to call with restore_camera=false to prevent rigs from snapping back 
		# to player camera automatically (we handle the transition).
		# We check if it's one of our known rig types or just try to pass the arg.
		# Note: In GDScript, calling a method with extra args that are not defined throws an error.
		# But since we updated CinematicRig and CinematicPathRig, they accept it.
		# For safety, we can use call() but it might still error if signature mismatch.
		# Ideally we use get_method_argument_count but that's complex in 3.x.
		# We will assuming standard rigs are updated. If active_rig is custom, this might fail unless updated.
		# Safe fallback: check if it's a known class type? No, duck typing involves risk.
		# Let's assume standard behavior for now as we control the codebase.
		active_rig.deactivate(false)
	else:
		# Fallback for very old rigs?
		if active_rig.has_method("deactivate"):
			active_rig.deactivate()
			
	active_rig = null
	current_control_mode = ControlMode.FREE
	emit_signal("control_mode_changed", ControlMode.FREE)
	
	# Start exit transition if we have valid cameras and transition time
	if trans_time > 0 and rig_cam and player_cam:
		# print("[CinematicManager] Starting EXIT transition")
		_start_exit_transition(rig_cam, player_cam, trans_time)
	else:
		# print("[CinematicManager] Immediate switch to player cam")
		# Immediate switch
		if player_cam:
			player_cam.current = true
		_is_transitioning = false
		_is_exit_transition = false
	
	emit_signal("cinematic_stopped")


func _start_exit_transition(from_cam: Camera, to_cam: Camera, duration: float):
	"""Start transition FROM rig camera TO player camera (current position)."""
	# CRITICAL: Capture from the VIEWPORT's current camera first (what's actually being rendered)
	var viewport_cam = get_viewport().get_camera()
	if viewport_cam:
		_force_update_camera_transform(viewport_cam)
		_source_transform = viewport_cam.global_transform
		_source_fov = viewport_cam.fov
		_source_near = viewport_cam.near
		_source_far = viewport_cam.far
	else:
		_force_update_camera_transform(from_cam)
		_source_transform = from_cam.global_transform
		_source_fov = from_cam.fov
		_source_near = from_cam.near
		_source_far = from_cam.far
	
	_exit_target_cam = to_cam
	_transition_duration = duration
	_transition_timer = 0.0
	_is_transitioning = true
	_is_exit_transition = true
	
	# Set trans_camera to SOURCE and make it current IMMEDIATELY
	_trans_camera.global_transform = _source_transform
	_trans_camera.fov = _source_fov
	_trans_camera.near = _source_near
	_trans_camera.far = _source_far
	_trans_camera.current = true
	
	# print("[CinematicManager] EXIT START: Source=", _source_transform.origin, " Target (initial)=", to_cam.global_transform.origin)

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

func _start_transition(from_cam: Camera, to_cam: Camera, duration: float, rig: Spatial):
	active_rig = rig
	
	# CRITICAL: Capture from the VIEWPORT's current camera first (what's actually being rendered)
	var viewport_cam = get_viewport().get_camera()
	if viewport_cam:
		_force_update_camera_transform(viewport_cam)
		_source_transform = viewport_cam.global_transform
		_source_fov = viewport_cam.fov
		_source_near = viewport_cam.near
		_source_far = viewport_cam.far
	else:
		_force_update_camera_transform(from_cam)
		_source_transform = from_cam.global_transform
		_source_fov = from_cam.fov
		_source_near = from_cam.near
		_source_far = from_cam.far
	
	# THEN activate the rig so it snaps to correct position
	if active_rig.has_method("activate"):
		active_rig.activate(false) # Don't set camera current yet
	
	_transition_duration = duration
	_transition_timer = 0.0
	_is_transitioning = true
	_is_exit_transition = false
	
	# Set trans_camera to SOURCE and make it current IMMEDIATELY
	_trans_camera.global_transform = _source_transform
	_trans_camera.fov = _source_fov
	_trans_camera.near = _source_near
	_trans_camera.far = _source_far
	_trans_camera.force_update_transform() # CRITICAL: Ensure Godot sees the new transform before render
	_trans_camera.current = true
	
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

func force_finish_transition():
	if _is_transitioning:
		# Force timer to end
		_transition_timer = _transition_duration
		# Calculate final step to apply state
		step(0)
		# Ensure flags are cleared (step might do it, but to be safe)
		_is_transitioning = false
		_is_exit_transition = false


func step(delta: float):
	if not _is_transitioning:
		return
	
	_transition_timer += delta
	var t = clamp(_transition_timer / _transition_duration, 0.0, 1.0)
	
	# Simple ease in-out (smoothstep)
	var weight = t * t * (3.0 - 2.0 * t)
	
	# CRITICAL FIX: "First Frame Lock"
	# If this is the very first step of the transition, force weight to 0.
	# The source transform is a snapshot of the viewport from BEFORE the physics step.
	# But we are running AFTER the physics step, so the target has already moved.
	# If we interpolate even a tiny bit (weight > 0), we immediately jump towards the new target position.
	# By forcing weight=0 for the first frame, we hold the visual state for 1 frame to match previous frame,
	# essentially "hiding" the physics jump that just occurred.
	if _transition_timer <= delta * 1.01:
		weight = 0.0
	
	# print("[CinematicManager] step: t=", t, " weight=", weight, " exit=", _is_exit_transition)
	
	if _is_exit_transition:
		# Exit transition: interpolate toward CURRENT player camera position
		if _exit_target_cam and is_instance_valid(_exit_target_cam):
			# Force update of target to eliminate 1-frame lag
			_force_update_camera_transform(_exit_target_cam)
			
			var target_transform = _exit_target_cam.global_transform
			var target_fov = _exit_target_cam.fov
			var target_near = _exit_target_cam.near
			var target_far = _exit_target_cam.far
			
			_trans_camera.global_transform = _source_transform.interpolate_with(target_transform, weight)
			_trans_camera.fov = lerp(_source_fov, target_fov, weight)
			_trans_camera.near = lerp(_source_near, target_near, weight)
			_trans_camera.far = lerp(_source_far, target_far, weight)
			
			if weight < 0.1 or weight > 0.9:
				pass
				# print("[CinematicManager] EXIT STEP: weight=", weight, " trans_pos=", _trans_camera.global_transform.origin, " player_cam_pos=", target_transform.origin)
			
			if t >= 1.0:
				# print("[CinematicManager] EXIT COMPLETE. Trans_pos=", _trans_camera.global_transform.origin, " Player_cam_pos=", target_transform.origin)
				_is_transitioning = false
				_is_exit_transition = false
				_exit_target_cam.current = true
				_exit_target_cam = null
	else:
		# Enter transition: interpolate toward LIVE rig camera
		if active_rig:
			# CRITICAL: Force update the rig logic FIRST to ensure it tracks the player's CURRENT position
			# This is necessary because CinematicManager.step() might run before the rig's _physics_process
			if active_rig.has_method("_update_rig"):
				# Determine delta to use. If it's the first frame (weight=0), use 0 to snap?
				# No, we want valid motion. Use the passed delta.
				active_rig._update_rig(delta)
				if active_rig.has_method("get_path_follow"):
					var pf = active_rig.get_path_follow()
					if pf: pf.force_update_transform()
				active_rig.force_update_transform()

				# Also force transform propagation!
				if active_rig.has_method("get_camera"):
					_force_update_camera_transform(active_rig.get_camera())
				
			var target_cam = active_rig.get_camera()
			if target_cam:
				# Force update of target to eliminate 1-frame lag
				_force_update_camera_transform(target_cam)
				
				var target_transform = target_cam.global_transform
				var target_fov = target_cam.fov
				var target_near = target_cam.near
				var target_far = target_cam.far
				
				var new_transform = _source_transform.interpolate_with(target_transform, weight)
				_trans_camera.global_transform = new_transform
				_trans_camera.fov = lerp(_source_fov, target_fov, weight)
				_trans_camera.near = lerp(_source_near, target_near, weight)
				_trans_camera.far = lerp(_source_far, target_far, weight)
				
				# Trace prints for first and last frames
				# if weight < 0.1 or weight > 0.9:
				# 	print("[CinematicManager] ENTER STEP: weight=", weight, " trans_pos=", _trans_camera.global_transform.origin, " target_pos=", target_transform.origin)
				
				if t >= 1.0:
					# print("[CinematicManager] ENTER COMPLETE. Trans_pos=", _trans_camera.global_transform.origin, " Rig_cam_pos=", target_transform.origin)
					_is_transitioning = false
					target_cam.current = true

func _force_update_camera_transform(cam: Camera):
	"""Forces immediate transform propagation for a camera and its parents."""
	if not cam: return
	
	# Force update from root down to avoid stale world transforms
	var path = []
	var curr = cam
	while curr and curr is Spatial:
		path.push_front(curr)
		curr = curr.get_parent()
		if curr == get_tree().root: break
	
	for node in path:
		node.force_update_transform()

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
