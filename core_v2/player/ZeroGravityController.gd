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
var _last_rolled_basis := Basis.IDENTITY

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

# Called by ControllerManager on zero-g entry with the standard CameraRig.
func set_camera_rig(rig: Spatial) -> void:
	_camera_rig = rig
	_camera = _find_camera(_camera_rig)
	_refresh_runtime_refs()
	yaw        = _body.yaw   if "yaw"   in _body else yaw
	pitch      = _body.pitch if "pitch" in _body else pitch
	roll_angle = 0.0
	_last_sync_yaw   = yaw
	_last_sync_pitch = pitch
	_last_sync_roll  = roll_angle

func reset_visual_state() -> void:
	roll_angle = 0.0
	# Do NOT zero velocity — ControllerManager already captured it for transfer.
	_refresh_runtime_refs()
	if is_instance_valid(_pilot_mesh):
		_pilot_mesh.transform = Transform()

func sync_state_from_rig() -> void:
	if is_instance_valid(_camera_rig):
		_sync_state_from_rig_basis(_camera_rig.transform.basis)

func _sync_state_from_rig_basis(basis: Basis) -> void:
	# Extract yaw/pitch/roll from the rig's current basis.
	var forward := -basis.z
	var forward_h := Vector3(forward.x, 0.0, forward.z)
	var yaw_val := yaw
	if forward_h.length_squared() > 0.0001:
		yaw_val = atan2(-forward_h.normalized().x, -forward_h.normalized().z)
	var pitch_val := asin(clamp(forward.normalized().y, -1.0, 1.0))
	var yp_basis := Basis(Vector3.UP, yaw_val) * Basis(Vector3.RIGHT, pitch_val)
	var roll_basis := yp_basis.inverse() * basis
	var roll_val := atan2(-roll_basis.x.y, roll_basis.x.x)
	yaw = yaw_val
	pitch = pitch_val
	roll_angle = roll_val
	if _body:
		_body.yaw = yaw
		_body.pitch = pitch
	_last_sync_yaw = yaw
	_last_sync_pitch = pitch
	_last_sync_roll = roll_angle

func get_standard_exit_orientation() -> Dictionary:
	# Use camera global forward (includes SpringArm 180°) — same as movement basis.
	var forward := -_last_rolled_basis.z
	var exit_yaw := yaw
	var forward_h := Vector3(forward.x, 0.0, forward.z)
	if forward_h.length_squared() > 0.0001:
		exit_yaw = atan2(-forward_h.normalized().x, -forward_h.normalized().z)
	var min_p: float = deg2rad(_body.min_pitch) if _body and "min_pitch" in _body else deg2rad(-85.0)
	var max_p: float = deg2rad(_body.max_pitch) if _body and "max_pitch" in _body else deg2rad(85.0)
	var exit_pitch := clamp(asin(clamp(forward.normalized().y, -1.0, 1.0)), min_p, max_p)
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
	var active_rig := _camera_rig

	var sens: float = _body.mouse_sensitivity if "mouse_sensitivity" in _body else 0.005
	var invert_y: bool = _body.invert_mouse_y if "invert_mouse_y" in _body else false

	# 1. Apply incremental rotations in local player space.
	#    Yaw rotates around the rig's local Y (world-Y projected out of roll).
	#    Pitch rotates around the rig's local X (right axis).
	#    Roll (Q/E) rotates around the rig's local -Z (forward).
	#    SpringArm has 180° Y baked in, so the rig's local -Z points opposite to
	#    camera view. We negate roll so Q/E match what the player sees.
	var cur_basis := active_rig.transform.basis.orthonormalized()
	if input:
		var mouse_y := -input.mouse_delta.y if invert_y else input.mouse_delta.y
		var roll_input := 0.0
		if input.roll_left:  roll_input -= 1.0
		if input.roll_right: roll_input += 1.0
		var droll := roll_input * deg2rad(_setting("roll_speed_deg", DEFAULT_ROLL_SPEED_DEG)) * dt
		roll_angle += droll

		# Use the rig's own local axes for incremental rotation.
		var local_right :=  cur_basis.x
		var local_up    :=  cur_basis.y
		var local_fwd   := -cur_basis.z  # rig -Z = camera forward (after SpringArm flip)
		var dyaw   := -input.mouse_delta.x * sens
		var dpitch := -mouse_y * sens
		# Clamp pitch: extract current pitch from basis to enforce limits.
		var cur_pitch := asin(clamp(cur_basis.z.y, -1.0, 1.0))
		var min_p: float = deg2rad(_body.min_pitch) if "min_pitch" in _body else deg2rad(-85.0)
		var max_p: float = deg2rad(_body.max_pitch) if "max_pitch" in _body else deg2rad(85.0)
		var new_pitch := clamp(cur_pitch + dpitch, min_p, max_p)
		dpitch = new_pitch - cur_pitch
		cur_basis = Basis(local_up, dyaw) * cur_basis
		cur_basis = Basis(local_right, dpitch) * cur_basis
		# Roll the rig around its forward axis. Negate because SpringArm's 180°Y
		# mirrors the visual roll — negative droll = roll right as seen through camera.
		cur_basis = Basis(local_fwd, -droll) * cur_basis
		cur_basis = cur_basis.orthonormalized()
		# Sync scalar accumulators for exit orientation and body.
		var fwd_h := Vector3(cur_basis.z.x, 0.0, cur_basis.z.z)
		if fwd_h.length_squared() > 0.0001:
			yaw = atan2(fwd_h.normalized().x, fwd_h.normalized().z)
		pitch = -asin(clamp(cur_basis.z.y, -1.0, 1.0))

	active_rig.transform.basis = cur_basis
	active_rig.force_update_transform()

	if "yaw"   in _body: _body.yaw   = yaw
	if "pitch" in _body: _body.pitch = pitch
	_last_sync_yaw   = yaw
	_last_sync_pitch = pitch
	_last_sync_roll  = roll_angle

	# 3. Movement: use the active camera's global basis (includes SpringArm 180° bake),
	#    same source CinematicManager uses in normal mode.
	var cam_basis := _camera.global_transform.basis if is_instance_valid(_camera) else cur_basis
	_last_rolled_basis = cam_basis
	var move_dir := Vector3.ZERO
	if input:
		var fwd   := -cam_basis.z
		var right :=  cam_basis.x
		var up    :=  cam_basis.y
		move_dir = right * input.move_vec.x + fwd * (-input.move_vec.y)
		if input.jump:   move_dir += up
		if input.crouch: move_dir -= up
		if move_dir.length_squared() > 1.0:
			move_dir = move_dir.normalized()

	_update_wish_direction(move_dir)

	# 4. Velocity.
	if move_dir.length_squared() < 0.001:
		_body.velocity *= pow(float(_setting("idle_damping", DEFAULT_IDLE_DAMPING)), dt * 60.0)
	else:
		var speed_mult: float = float(_setting("sprint_multiplier", DEFAULT_SPRINT_MULTIPLIER)) if input and input.sprint else 1.0
		var target_velocity := move_dir * float(_setting("max_speed", DEFAULT_MAX_SPEED)) * speed_mult
		var accel_t: float = clamp(float(_setting("acceleration", DEFAULT_ACCELERATION)) * dt, 0.0, 1.0)
		_body.velocity = _body.velocity.linear_interpolate(target_velocity, accel_t)

	# 5. Move the body.
	_body.velocity = _body.move_and_slide(_body.velocity, Vector3.UP)
	velocity = _body.velocity

	# 6. Camera follow (Y-lag, etc.) — call the body's own updater if available.
	if _body.has_method("_update_camera_view"):
		_body._update_camera_view(dt)

	# 7. Visuals.
	var mesh_basis_before_anim := _pilot_mesh.transform.basis if is_instance_valid(_pilot_mesh) else Basis()
	if "animator" in _body and is_instance_valid(_body.animator) and _body.animator.has_method("step_animator"):
		_body.animator.step_animator(dt, _body.velocity)
	_update_visual_mesh(dt, input, mesh_basis_before_anim)

func _refresh_runtime_refs() -> void:
	if not is_instance_valid(_body):
		return
	_settings = _body.get_node_or_null("Logic/ZeroGravity")
	# Always use the standard CameraRig — OTS, SpringArm, zoom stay intact.
	_camera_rig = _body.get_node_or_null("CameraRig") as Spatial
	_camera = _find_camera(_camera_rig)
	_pilot_mesh = _body.get_node_or_null("Visual/Pivot")
	if _settings and _settings.has_method("configure_camera_rig"):
		_settings.configure_camera_rig(_camera_rig)

func _setting(name: String, fallback):
	if _settings and name in _settings:
		return _settings.get(name)
	return fallback

func _find_camera(node: Node) -> Camera:
	if node == null:
		return null
	if node is Camera:
		return node as Camera
	for i in range(node.get_child_count()):
		var cam := _find_camera(node.get_child(i))
		if cam:
			return cam
	return null

func _get_movement_basis() -> Basis:
	return _last_rolled_basis

func _update_wish_direction(move_dir: Vector3) -> void:
	if "movement_logic" in _body and is_instance_valid(_body.movement_logic):
		_body.movement_logic.wish_direction = move_dir

func _update_visual_mesh(dt: float, input: InputDataV2, preserved_basis: Basis) -> void:
	if not is_instance_valid(_pilot_mesh):
		return

	var smooth: float = float(_setting("mesh_rotation_smooth", DEFAULT_MESH_ROTATION_SMOOTH))
	var deadzone: float = float(_setting("mesh_align_input_deadzone", DEFAULT_MESH_ALIGN_INPUT_DEADZONE))
	var has_input: bool = input != null and (
		abs(input.move_vec.x) > deadzone or
		abs(input.move_vec.y) > deadzone or
		input.jump or input.crouch
	)

	# Target mesh orientation = camera orientation rotated 180° around Y
	# (mesh faces away from camera, sharing the same roll and pitch).
	var target_basis := _last_rolled_basis * Basis(Vector3.UP, PI)

	if has_input:
		_pilot_mesh.transform.basis = preserved_basis.slerp(target_basis, clamp(smooth * dt, 0.0, 1.0))
	else:
		# Idle: still slerp toward camera-facing so mesh settles correctly on entry.
		_pilot_mesh.transform.basis = preserved_basis.slerp(target_basis, clamp(smooth * dt, 0.0, 1.0))

	_apply_mesh_center_offset()

func _apply_mesh_center_offset() -> void:
	var offset: Vector3 = _setting("mesh_center_offset", DEFAULT_MESH_CENTER_OFFSET)
	_pilot_mesh.transform.origin = offset - _pilot_mesh.transform.basis.xform(offset)
