extends Node
class_name ZeroGravityController

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

const DEFAULT_MAX_SPEED := 8.0
const DEFAULT_SPRINT_MULTIPLIER := 2.0
const DEFAULT_ACCELERATION := 15.0
const DEFAULT_IDLE_DAMPING := 0.95
const DEFAULT_ROLL_SPEED_DEG := 90.0
const DEFAULT_MESH_ROTATION_SMOOTH := 8.0
const DEFAULT_MESH_CENTER_OFFSET := Vector3(0.0, 1.0, 0.0)
const DEFAULT_MESH_ALIGN_INPUT_DEADZONE := 0.1

var velocity := Vector3.ZERO
var _body: KinematicBody = null
var _camera_rig: Spatial = null
var _pilot_mesh: Spatial = null
var _settings: Node = null

var yaw := 0.0
var pitch := 0.0
var roll_angle := 0.0

var _last_sync_yaw := 0.0
var _last_sync_pitch := 0.0
var _last_sync_roll := 0.0

var _camera: Camera = null

func _ready() -> void:
	_body = get_parent() as KinematicBody
	if _body:
		_refresh_runtime_refs()

		# Ensure ControllerManager knows about us
		var cm = _body.get_node_or_null("ControllerManager")
		if cm and "zero_gravity_controller" in cm:
			cm.zero_gravity_controller = self
	
	# Start disabled. We rely entirely on PlayerControllerV2 step delegation.
	set_physics_process(false)
	set_process(false)

func set_camera_rig(rig: Spatial) -> void:
	_camera_rig = rig
	_camera = _find_camera(_camera_rig)
	if _settings and _settings.has_method("configure_camera_rig"):
		_settings.configure_camera_rig(_camera_rig)
	if _camera_rig and _camera_rig.has_method("reset_follow_state"):
		_camera_rig.reset_follow_state(_body)

func reset_visual_state() -> void:
	roll_angle = 0.0
	velocity = Vector3.ZERO
	_refresh_runtime_refs()
	if is_instance_valid(_pilot_mesh):
		_pilot_mesh.transform = Transform()

func sync_state_from_rig() -> void:
	if _camera_rig and _camera_rig.has_method("get_orientation_euler"):
		var eulers = _camera_rig.get_orientation_euler()
		yaw = eulers.x
		pitch = eulers.y
		roll_angle = eulers.z
		
		if _body:
			_body.yaw = yaw
			_body.pitch = pitch
			
		_last_sync_yaw = yaw
		_last_sync_pitch = pitch
		_last_sync_roll = roll_angle

func get_standard_exit_orientation() -> Dictionary:
	_refresh_runtime_refs()
	var basis: Basis = _get_movement_basis()
	var forward: Vector3 = -basis.z
	
	var exit_yaw := 0.0
	var exit_pitch := 0.0
	
	# Project forward vector onto the horizontal plane
	var forward_h := Vector3(forward.x, 0.0, forward.z)
	if forward_h.length_squared() > 0.0001:
		forward_h = forward_h.normalized()
		exit_yaw = atan2(-forward_h.x, -forward_h.z)
	else:
		exit_yaw = _body.yaw if _body else yaw
		
	var min_p: float = deg2rad(_body.min_pitch) if _body and "min_pitch" in _body else deg2rad(-85.0)
	var max_p: float = deg2rad(_body.max_pitch) if _body and "max_pitch" in _body else deg2rad(85.0)
	
	var forward_norm = forward.normalized()
	exit_pitch = clamp(asin(forward_norm.y), min_p, max_p)
	
	return {
		"yaw": wrapf(exit_yaw, -PI, PI),
		"pitch": exit_pitch
	}

func step_zero_g(dt: float, input: InputDataV2) -> void:
	if not is_instance_valid(_body):
		return
	if not is_instance_valid(_camera_rig):
		_refresh_runtime_refs()
	if not is_instance_valid(_camera_rig):
		return

	# Detect external changes (e.g. from tests or transition) and push to the rig
	var current_ext_yaw = _body.yaw if _body else yaw
	var current_ext_pitch = _body.pitch if _body else pitch
	if current_ext_yaw != _last_sync_yaw or current_ext_pitch != _last_sync_pitch or roll_angle != _last_sync_roll:
		if _camera_rig:
			if _camera_rig.has_method("set_orientation_euler"):
				_camera_rig.set_orientation_euler(current_ext_yaw, current_ext_pitch, roll_angle)
			else:
				_camera_rig.transform.basis = Basis(Vector3.UP, current_ext_yaw) * Basis(Vector3.RIGHT, current_ext_pitch) * Basis(Vector3.FORWARD, roll_angle)
				_camera_rig.force_update_transform()

	# 1. Update camera orientation from mouse delta & roll
	if input:
		var mouse_d = input.mouse_delta
		var sens = 0.005
		if "mouse_sensitivity" in _body:
			sens = _body.mouse_sensitivity
		var invert_y: bool = _body.invert_mouse_y if "invert_mouse_y" in _body else false
		var mouse_y: float = -mouse_d.y if invert_y else mouse_d.y
		
		var roll_input := 0.0
		if input.roll_left:
			roll_input -= 1.0
		if input.roll_right:
			roll_input += 1.0
		
		var roll_speed = deg2rad(_setting("roll_speed_deg", DEFAULT_ROLL_SPEED_DEG))
		var roll_rate = roll_input * roll_speed

		# Yaw, pitch, roll accumulation
		yaw   -= input.mouse_delta.x * sens
		pitch -= mouse_y * sens
		var min_p: float = deg2rad(_body.min_pitch) if "min_pitch" in _body else deg2rad(-89.0)
		var max_p: float = deg2rad(_body.max_pitch) if "max_pitch" in _body else deg2rad(89.0)
		pitch = clamp(pitch, min_p, max_p)
		roll_angle += roll_rate * dt

		# Write to CameraRig root: yaw + pitch + roll (same as normal mode + roll)
		var yp_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
		var forward_axis := -yp_basis.z
		_camera_rig.transform.basis = Basis(forward_axis, roll_angle) * yp_basis
		_camera_rig.force_update_transform()

		if _body:
			_body.yaw = yaw
			_body.pitch = pitch
		_last_sync_yaw = yaw
		_last_sync_pitch = pitch
		_last_sync_roll = roll_angle

		# Zoom via standard orbit system.
		if _body.has_method("_update_camera_orbit_state"):
			_body._update_camera_orbit_state(dt, input, false, false)

	# 4. Movement WASD in the rendered camera's direction.
	var move_dir := Vector3.ZERO
	if input:
		var movement_basis = _get_movement_basis()

		var forward = -movement_basis.z
		var right = movement_basis.x
		var up = movement_basis.y

		move_dir = right * input.move_vec.x + forward * (-input.move_vec.y)

		if input.jump:
			move_dir += up
		if input.crouch:
			move_dir -= up
		if move_dir.length_squared() > 1.0:
			move_dir = move_dir.normalized()

	_update_wish_direction(move_dir)

	# 5. Approach target drift velocity, or damp when no thrust is active.
	if move_dir.length_squared() < 0.001:
		_body.velocity *= pow(float(_setting("idle_damping", DEFAULT_IDLE_DAMPING)), dt * 60.0)
	else:
		var speed_mult: float = float(_setting("sprint_multiplier", DEFAULT_SPRINT_MULTIPLIER)) if input and input.sprint else 1.0
		var target_velocity: Vector3 = move_dir * float(_setting("max_speed", DEFAULT_MAX_SPEED)) * speed_mult
		var accel_t: float = clamp(float(_setting("acceleration", DEFAULT_ACCELERATION)) * dt, 0.0, 1.0)
		_body.velocity = _body.velocity.linear_interpolate(target_velocity, accel_t)

	# 6. Move the body
	_body.velocity = _body.move_and_slide(_body.velocity, Vector3.UP)
	velocity = _body.velocity # Sync local copy

	if _camera_rig and _camera_rig.has_method("update_follow"):
		_camera_rig.update_follow(_body, dt)

	# 7. Visuals update
	var mesh_basis_before_anim := _pilot_mesh.transform.basis if is_instance_valid(_pilot_mesh) else Basis()
	if "animator" in _body and is_instance_valid(_body.animator) and _body.animator.has_method("step_animator"):
		_body.animator.step_animator(dt, _body.velocity)
	_update_visual_mesh(dt, input, mesh_basis_before_anim)

func _refresh_runtime_refs() -> void:
	if not is_instance_valid(_body):
		return
	_settings = _body.get_node_or_null("Logic/ZeroGravity")
	_camera_rig = _body.get_node_or_null("CameraRig") as Spatial
	if _camera_rig == null:
		_camera_rig = _body.get_node_or_null("ZeroGCameraRig") as Spatial
	_camera = _find_camera(_camera_rig)
	_pilot_mesh = _body.get_node_or_null("Visual/Pivot")
	if _settings and _settings.has_method("configure_camera_rig"):
		_settings.configure_camera_rig(_camera_rig)

func _setting(name: String, fallback):
	if _settings and name in _settings:
		return _settings.get(name)
	return fallback

func _apply_zero_g_zoom_delta(zoom_delta: float) -> void:
	if abs(zoom_delta) <= 0.01 or not _camera_rig:
		return
	var min_len := 0.75
	var max_len := 50.0
	if _body:
		if "orbit_zoom_min_length" in _body:
			min_len = max(float(_body.orbit_zoom_min_length), 0.1)
		if "orbit_zoom_max_length" in _body:
			max_len = max(float(_body.orbit_zoom_max_length), min_len)
	if _camera_rig.has_method("set_camera_distance"):
		var current_distance := float(_camera_rig.camera_distance) if "camera_distance" in _camera_rig else float(_setting("camera_distance", 4.0))
		_camera_rig.set_camera_distance(clamp(current_distance + zoom_delta, min_len, max_len))

func _find_camera(node: Node) -> Camera:
	if node == null:
		return null
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam = _find_camera(node.get_child(i))
		if cam:
			return cam
	return null

func _get_movement_basis() -> Basis:
	if _camera_rig and _camera_rig.has_method("get_movement_basis"):
		return _camera_rig.get_movement_basis()
	if is_instance_valid(_camera):
		return _camera.global_transform.basis
	return _camera_rig.global_transform.basis if is_instance_valid(_camera_rig) else Basis.IDENTITY

func _update_wish_direction(move_dir: Vector3) -> void:
	if "movement_logic" in _body and is_instance_valid(_body.movement_logic):
		_body.movement_logic.wish_direction = move_dir

func _update_visual_mesh(dt: float, input: InputDataV2, preserved_basis: Basis) -> void:
	if not is_instance_valid(_pilot_mesh):
		return
	var align_deadzone: float = float(_setting("mesh_align_input_deadzone", DEFAULT_MESH_ALIGN_INPUT_DEADZONE))
	var is_moving_forward: bool = input != null and input.move_vec.y < -align_deadzone
	
	var current_euler = preserved_basis.get_euler()
	var flat_basis = Basis(Vector3.UP, current_euler.y)

	if not is_moving_forward:
		_pilot_mesh.transform.basis = flat_basis
		return

	var movement_basis := _get_movement_basis()
	var forward := -movement_basis.z
	var forward_h := Vector3(forward.x, 0.0, forward.z)
	if forward_h.length_squared() <= 0.0001:
		_pilot_mesh.transform.basis = flat_basis
		return
		
	forward_h = forward_h.normalized()
	var target_yaw := atan2(-forward_h.x, -forward_h.z)
	var target_basis := Basis(Vector3.UP, target_yaw)
	var smooth: float = float(_setting("mesh_rotation_smooth", DEFAULT_MESH_ROTATION_SMOOTH))
	_pilot_mesh.transform.basis = flat_basis.slerp(target_basis, clamp(smooth * dt, 0.0, 1.0))

func _apply_mesh_center_offset() -> void:
	var offset: Vector3 = _setting("mesh_center_offset", DEFAULT_MESH_CENTER_OFFSET)
	_pilot_mesh.transform.origin = offset - _pilot_mesh.transform.basis.xform(offset)
