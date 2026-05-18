extends Node
class_name ZeroGravityController

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

export var base_speed := 8.0
export var vertical_speed := 5.0
export var acceleration := 15.0
export var friction := 0.95
export var sprint_multiplier := 2.0
export var rotation_speed := 3.0

var velocity := Vector3.ZERO
var _body: KinematicBody = null
var _camera_rig: Spatial = null

var yaw := 0.0
var pitch := 0.0

var _camera: Camera = null

func _ready() -> void:
	_body = get_parent() as KinematicBody
	if _body:
		_camera_rig = _body.get_node_or_null("CameraRig")
		if _camera_rig:
			_camera = _camera_rig.find_node("Camera", true, false) as Camera
	
	# Start disabled. We rely entirely on PlayerControllerV2 step delegation.
	set_physics_process(false)
	set_process(false)

func step_zero_g(dt: float, input: InputDataV2) -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_camera_rig):
		return

	# 1. Update camera yaw & pitch on the canonical body properties
	if input:
		var mouse_d = input.mouse_delta
		var sens = 0.005
		if "mouse_sensitivity" in _body:
			sens = _body.mouse_sensitivity
			
		_body.yaw -= mouse_d.x * sens
		_body.pitch -= mouse_d.y * sens
		
		# Q/E continuous yaw
		if input.rotate_left:
			_body.yaw += rotation_speed * dt
		if input.rotate_right:
			_body.yaw -= rotation_speed * dt
			
		_body.pitch = clamp(_body.pitch, deg2rad(-85.0), deg2rad(85.0))
		
		# Synchronize local copy
		yaw = _body.yaw
		pitch = _body.pitch

	# 2. Update Camera Rig Basis
	_camera_rig.transform.basis = Basis(Vector3.UP, _body.yaw) * Basis(Vector3.RIGHT, _body.pitch)
	_camera_rig.force_update_transform()

	# 3. Calculate Global 0G Movement Directions relative to the horizontal camera yaw
	# This perfectly aligns with standard air control horizontal directional vectors!
	var cam_node = _camera if is_instance_valid(_camera) else _camera_rig
	var camera_basis = cam_node.global_transform.basis
	var forward = -camera_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
		
	var right = camera_basis.x
	right.y = 0.0
	if right.length_squared() > 0.001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT
		
	var up = Vector3.UP

	var target_velocity := Vector3.ZERO
	var move_dir := Vector3.ZERO
	
	if input:
		move_dir = right * input.move_vec.x + forward * (-input.move_vec.y)
		var vert_dir = 0.0
		if input.jump:
			vert_dir += 1.0
		if input.crouch:
			vert_dir -= 1.0
			
		var speed_mult = sprint_multiplier if input.sprint else 1.0
		
		target_velocity = move_dir * (base_speed * speed_mult) + up * (vert_dir * vertical_speed * speed_mult)

	# 4. Interpolate and apply velocity directly on the KinematicBody's canonical velocity
	if target_velocity.length_squared() > 0.001:
		_body.velocity = _body.velocity.linear_interpolate(target_velocity, acceleration * dt)
	else:
		_body.velocity *= pow(friction, dt * 60.0)

	# 5. Move the body via move_and_slide with Vector3.UP for correct physics interactions
	_body.velocity = _body.move_and_slide(_body.velocity, Vector3.UP)
	velocity = _body.velocity # Sync local copy

	# 6. Update wish_direction so PilotAnimatorV2 rotates the player visual Pivot correctly
	if "movement_logic" in _body and is_instance_valid(_body.movement_logic):
		_body.movement_logic.wish_direction = move_dir
		
	if "animator" in _body and is_instance_valid(_body.animator) and _body.animator.has_method("step_animator"):
		_body.animator.step_animator(dt, _body.velocity)
