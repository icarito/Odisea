extends Node
class_name ZeroGravityController

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

export var base_speed := 8.0
export var vertical_speed := 5.0
export var acceleration := 15.0
export var friction := 0.95
export var sprint_multiplier := 2.0
export var rotation_speed := 3.0

# New 6-DOF export variables
export var roll_speed: float = 90.0
export var rotation_smooth: float = 8.0
export var movement_force: float = 12.0

var velocity := Vector3.ZERO
var _body: KinematicBody = null
var _camera_rig: Spatial = null
var _pilot_mesh: Spatial = null

var yaw := 0.0
var pitch := 0.0
var roll_angle := 0.0

var _camera: Camera = null

func _ready() -> void:
	_body = get_parent() as KinematicBody
	if _body:
		_camera_rig = _body.get_node_or_null("CameraRig")
		if _camera_rig:
			_camera = _camera_rig.find_node("Camera", true, false) as Camera

		# Locate pilot mesh in PlayerControllerV2 structure: $Visual/Pivot
		_pilot_mesh = _body.get_node_or_null("Visual/Pivot")

		# Ensure ControllerManager knows about us
		var cm = _body.get_node_or_null("ControllerManager")
		if cm and "zero_gravity_controller" in cm:
			cm.zero_gravity_controller = self
	
	# Start disabled. We rely entirely on PlayerControllerV2 step delegation.
	set_physics_process(false)
	set_process(false)

func step_zero_g(dt: float, input: InputDataV2) -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_camera_rig):
		return

	# 1. Update camera yaw & pitch from mouse delta
	if input:
		var mouse_d = input.mouse_delta
		var sens = 0.005
		if "mouse_sensitivity" in _body:
			sens = _body.mouse_sensitivity
			
		_body.yaw -= mouse_d.x * sens
		_body.pitch -= mouse_d.y * sens
		_body.pitch = clamp(_body.pitch, deg2rad(-85.0), deg2rad(85.0))
		
		# 2. Update roll from input
		var roll_input = 0.0
		# Q rolls Left, E rolls Right.
		# Positive rotation around FORWARD (-Z) is clockwise looking forward -> Roll Right.
		if input.roll_left:
			roll_input -= 1.0
		if input.roll_right:
			roll_input += 1.0

		if roll_input != 0.0:
			roll_angle += deg2rad(roll_speed) * dt * roll_input

		# Synchronize local copy
		yaw = _body.yaw
		pitch = _body.pitch

	# 3. Update Camera Rig Basis (Yaw and Pitch only)
	_camera_rig.transform.basis = Basis(Vector3.UP, _body.yaw) * Basis(Vector3.RIGHT, _body.pitch)
	_camera_rig.force_update_transform()

	# 4. Calculate 6-DOF target rotation for the mesh
	# We combine CameraRig's orientation (Yaw*Pitch) with our Roll accumulation.
	var rig_basis = _camera_rig.transform.basis
	var target_quat = rig_basis.get_rotation_quat() * Quat(Vector3.FORWARD, roll_angle)

	# 5. Slerp Pilot Mesh towards target orientation
	if is_instance_valid(_pilot_mesh):
		_pilot_mesh.transform.basis = _pilot_mesh.transform.basis.slerp(Basis(target_quat), rotation_smooth * dt)

	# 6. Movement WASD in CameraRig's direction
	var move_dir := Vector3.ZERO
	if input:
		# Use CameraRig global basis for movement direction
		var rig_global_basis = _camera_rig.global_transform.basis

		var forward = -rig_global_basis.z
		var right = rig_global_basis.x
		var up = rig_global_basis.y

		move_dir = right * input.move_vec.x + forward * (-input.move_vec.y)

		if input.jump:
			move_dir += up
		if input.crouch:
			move_dir -= up
			
		var speed_mult = sprint_multiplier if input.sprint else 1.0
		
		# Apply movement force (push)
		_body.velocity += move_dir * movement_force * speed_mult * dt

	# 7. Apply friction/damping
	if move_dir.length_squared() < 0.001:
		_body.velocity *= pow(friction, dt * 60.0)
	else:
		# Soft limit speed to base_speed * mult
		var max_speed = base_speed * (sprint_multiplier if input.sprint else 1.0)
		if _body.velocity.length() > max_speed:
			_body.velocity = _body.velocity.normalized() * max_speed

	# 8. Move the body
	_body.velocity = _body.move_and_slide(_body.velocity, Vector3.UP)
	velocity = _body.velocity # Sync local copy

	# 9. Visuals update
	if "animator" in _body and is_instance_valid(_body.animator) and _body.animator.has_method("step_animator"):
		_body.animator.step_animator(dt, _body.velocity)
