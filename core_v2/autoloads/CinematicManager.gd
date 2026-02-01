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

# For interpolation
var _is_transitioning := false
var _transition_timer := 0.0
var _transition_duration := 0.0
var _trans_camera: Camera = null
var _source_transform: Transform
var _source_fov: float

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

func activate_rig_direct(target_rig: Spatial, control_mode: int = ControlMode.FREE):
	"""Activa un rig directamente por referencia (preferido sobre string ID)."""
	if not target_rig:
		printerr("[CinematicManager] activate_rig_direct called with null rig")
		return
	
	var new_cam = target_rig.get_camera() if target_rig.has_method("get_camera") else null
	if not new_cam:
		printerr("[CinematicManager] Rig has no camera: ", target_rig.name)
		return

	var old_cam = get_viewport().get_camera()
	current_control_mode = control_mode

	# Si el rig maneja su propia transición, no usamos la del Manager
	var rig_handles_transition = target_rig.has_method("_apply_transition_camera")
	var trans_time = target_rig.transition_time if "transition_time" in target_rig else 0.0
	
	if rig_handles_transition:
		# El rig (CinematicPathRig) maneja su propia transición
		_apply_rig(target_rig)
	elif trans_time > 0 and old_cam and old_cam != _trans_camera:
		_start_transition(old_cam, new_cam, trans_time, target_rig)
	else:
		_apply_rig(target_rig)

	var rig_name = target_rig.name
	emit_signal("cinematic_started", rig_name)

func deactivate_rig():
	if active_rig:
		# Si el rig maneja su propia restauración de cámara, dejarlo hacerlo
		var rig_handles_restore = active_rig.has_method("_restore_player_camera")
		active_rig.deactivate()
		active_rig = null
		
		if rig_handles_restore:
			# El rig restaura la cámara, no hacemos nada más
			current_control_mode = ControlMode.FREE
			_is_transitioning = false
			emit_signal("cinematic_stopped")
			return

	current_control_mode = ControlMode.FREE
	_is_transitioning = false

	# Return to player camera
	var player_cam = _find_player_camera()
	if player_cam:
		player_cam.current = true

	emit_signal("cinematic_stopped")

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
	_source_transform = from_cam.global_transform
	_source_fov = from_cam.fov
	_transition_duration = duration
	_transition_timer = 0.0
	_is_transitioning = true

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

func _process(delta):
	if _is_transitioning and active_rig:
		_transition_timer += delta
		var t = clamp(_transition_timer / _transition_duration, 0.0, 1.0)

		# Simple ease in-out
		var weight = t * t * (3.0 - 2.0 * t)

		var target_cam = active_rig.get_camera()
		if target_cam:
			_trans_camera.global_transform = _source_transform.interpolate_with(target_cam.global_transform, weight)
			_trans_camera.fov = lerp(_source_fov, target_cam.fov, weight)

			if t >= 1.0:
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
