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

var _last_sync_yaw   := 0.0
var _last_sync_pitch := 0.0
var _last_sync_roll  := 0.0

var _camera: Camera = null
var _last_rolled_basis := Basis.IDENTITY
var _camera_child_basis := Basis.IDENTITY
var _ots_logic: Node = null
var _ots_offset_parent: Spatial = null
var _spring_arm = null
var _ots_logic_was_processing := true

func _ready() -> void:
	_body = get_parent() as KinematicBody
	if _body:
		_refresh_runtime_refs()
		var cm = _body.get_node_or_null("ControllerManager")
		if cm and "zero_gravity_controller" in cm:
			cm.zero_gravity_controller = self
	set_physics_process(false)
	set_process(false)

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
	_camera_child_basis = _get_camera_child_basis()
	_last_rolled_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	_snap_camera_rig_y()
	_clear_spring_arm_camera_offset()
	_begin_zero_g_ots()

func reset_visual_state() -> void:
	roll_angle = 0.0
	_refresh_runtime_refs()
	_end_zero_g_ots()
	_snap_camera_rig_y()
	if is_instance_valid(_pilot_mesh):
		_restore_standard_visual_mesh()

func get_standard_exit_orientation() -> Dictionary:
	var min_p: float = deg2rad(_body.min_pitch) if _body and "min_pitch" in _body else deg2rad(-85.0)
	var max_p: float = deg2rad(_body.max_pitch) if _body and "max_pitch" in _body else deg2rad(85.0)
	return {"yaw": wrapf(yaw, -PI, PI), "pitch": clamp(pitch, min_p, max_p)}

func step_zero_g(dt: float, input: InputDataV2) -> void:
	if not is_instance_valid(_body):
		return
	if not is_instance_valid(_camera_rig):
		_refresh_runtime_refs()
	if not is_instance_valid(_camera_rig):
		return

	var sens: float    = _body.mouse_sensitivity if "mouse_sensitivity" in _body else 0.005
	var invert_y: bool = _body.invert_mouse_y    if "invert_mouse_y"    in _body else false

	if _last_sync_yaw == 0.0 and _last_sync_pitch == 0.0:
		yaw = _body.yaw if "yaw" in _body else yaw
		pitch = _body.pitch if "pitch" in _body else pitch

	# 1. Accumulate yaw / pitch / roll.
	if input:
		var mouse_y := -input.mouse_delta.y if invert_y else input.mouse_delta.y
		yaw   -= input.mouse_delta.x * sens
		pitch -= mouse_y * sens
		pitch = wrapf(pitch, -PI, PI)
		var roll_input := 0.0
		if input.roll_left:  roll_input += 1.0
		if input.roll_right: roll_input -= 1.0
		roll_angle += roll_input * deg2rad(_setting("roll_speed_deg", DEFAULT_ROLL_SPEED_DEG)) * dt

	if "yaw"   in _body: _body.yaw   = yaw
	if "pitch" in _body: _body.pitch = pitch
	if "roll_angle" in _body: _body.roll_angle = roll_angle
	if _body.has_method("_update_camera_orbit_state"):
		var zero_g_pitch := pitch
		var orbit_input := InputDataV2.new()
		if input:
			orbit_input.zoom_delta = input.zoom_delta
			orbit_input.fov_override = input.fov_override
		_body._update_camera_orbit_state(dt, orbit_input, false, false)
		yaw = _body.yaw if "yaw" in _body else yaw
		pitch = zero_g_pitch
		if "pitch" in _body: _body.pitch = pitch

	# 2. Write to rig root with yaw + pitch + roll.
	var yp_basis     := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var roll_basis   := Basis(Vector3.FORWARD, roll_angle)
	var rolled_basis := roll_basis * yp_basis
	rolled_basis = rolled_basis.orthonormalized()
	var prefix: Basis = _body.get("camera_basis_prefix") if "camera_basis_prefix" in _body else Basis.IDENTITY
	_last_rolled_basis = rolled_basis

	# Apply full rotation to rig (roll first, then yaw + pitch)
	_camera_rig.transform.basis = prefix * rolled_basis
	if "base_rig_y" in _body:
		_camera_rig.transform.origin.y = _body.base_rig_y * 0.5
	_camera_rig.force_update_transform()

	if "yaw"   in _body: _body.yaw   = yaw
	if "pitch" in _body: _body.pitch = pitch
	_last_sync_yaw   = yaw
	_last_sync_pitch = pitch
	_last_sync_roll  = roll_angle

	# 3. Movement direction based on full camera view (yaw/pitch/roll).
	var move_dir := Vector3.ZERO
	var has_movement := false
	if input:
		var fwd   := rolled_basis.z
		var right := -rolled_basis.x
		var up    := rolled_basis.y
		move_dir = right * input.move_vec.x + fwd * (-input.move_vec.y)
		if input.jump:   move_dir += up
		if input.crouch: move_dir -= up
		if move_dir.length_squared() > 1.0:
			move_dir = move_dir.normalized()
		has_movement = move_dir.length_squared() > 0.01

	# Mesh follows the desired movement direction only when moving
	if has_movement:
		_update_wish_direction(move_dir)
	else:
		# When idle, don't update wish direction (mesh stays in place)
		_update_wish_direction(Vector3.ZERO)

	# 4. Velocity.
	if move_dir.length_squared() < 0.001:
		_body.velocity *= pow(float(_setting("idle_damping", DEFAULT_IDLE_DAMPING)), dt * 60.0)
	else:
		var speed_mult := float(_setting("sprint_multiplier", DEFAULT_SPRINT_MULTIPLIER)) if input and input.sprint else 1.0
		var target_v   := move_dir * float(_setting("max_speed", DEFAULT_MAX_SPEED)) * speed_mult
		var accel_t    := clamp(float(_setting("acceleration", DEFAULT_ACCELERATION)) * dt, 0.0, 1.0)
		_body.velocity = _body.velocity.linear_interpolate(target_v, accel_t)

	# 5. Move.
	_body.velocity = _body.move_and_slide(_body.velocity, Vector3.UP)
	velocity = _body.velocity

	# 6. Camera zoom/FOV follow. Zero-g keeps the rig Y snapped; the standard
	#    Y-lag lerp makes the camera dip during mode transitions.
	_update_zero_g_camera_view(dt)
	_apply_zero_g_ots()

	# 7. Visuals.
	var mesh_basis_before := _pilot_mesh.transform.basis if is_instance_valid(_pilot_mesh) else Basis()
	if "animator" in _body and is_instance_valid(_body.animator) and _body.animator.has_method("step_animator"):
		_body.animator.step_animator(dt, _body.velocity)
	_update_visual_mesh(dt, mesh_basis_before, has_movement, rolled_basis)

func _refresh_runtime_refs() -> void:
	if not is_instance_valid(_body):
		return
	_settings   = _body.get_node_or_null("Logic/ZeroGravity")
	_camera_rig = _body.get_node_or_null("CameraRig") as Spatial
	_camera     = _find_camera(_camera_rig)
	_pilot_mesh = _body.get_node_or_null("Visual/Pivot")
	_ots_logic = _body.get_node_or_null("Logic/OverTheShoulder")
	_spring_arm = _body._find_spring_arm(_camera_rig) if _body.has_method("_find_spring_arm") and _camera_rig else null
	_ots_offset_parent = _spring_arm.get_parent() as Spatial if _spring_arm and _spring_arm.get_parent() is Spatial else null
	if _settings and _settings.has_method("configure_camera_rig"):
		_settings.configure_camera_rig(_camera_rig)

func _setting(name: String, fallback):
	if _settings and name in _settings:
		return _settings.get(name)
	return fallback

func _find_camera(node: Node) -> Camera:
	if node == null: return null
	if node is Camera: return node as Camera
	for i in range(node.get_child_count()):
		var cam := _find_camera(node.get_child(i))
		if cam: return cam
	return null

func _get_camera_child_basis() -> Basis:
	if not is_instance_valid(_camera_rig) or not is_instance_valid(_camera):
		return Basis.IDENTITY
	var basis := Basis.IDENTITY
	var curr: Node = _camera
	while curr and curr != _camera_rig and curr is Spatial:
		basis = (curr as Spatial).transform.basis * basis
		curr = curr.get_parent()
	return basis.orthonormalized()

func _get_movement_basis() -> Basis:
	return _last_rolled_basis

func _begin_zero_g_ots() -> void:
	if _ots_logic:
		_ots_logic_was_processing = _ots_logic.is_physics_processing()
		_ots_logic.set_physics_process(false)
	_apply_zero_g_ots()

func _end_zero_g_ots() -> void:
	if is_instance_valid(_ots_offset_parent):
		_ots_offset_parent.translation = Vector3.ZERO
	_clear_spring_arm_camera_offset()
	if _ots_logic:
		_ots_logic.set_physics_process(_ots_logic_was_processing)

func _apply_zero_g_ots() -> void:
	if not is_instance_valid(_ots_offset_parent):
		return
	_clear_spring_arm_camera_offset()
	var current_len := _get_effective_zero_g_arm_length()
	var distance_min := float(_ots_logic.get("distance_min")) if _ots_logic and "distance_min" in _ots_logic else 1.5
	var distance_max := float(_ots_logic.get("distance_max")) if _ots_logic and "distance_max" in _ots_logic else 4.5
	var span := max(distance_max - distance_min, 0.001)
	var weight := 1.0 - clamp((current_len - distance_min) / span, 0.0, 1.0)
	var curve_power := float(_ots_logic.get("curve_power")) if _ots_logic and "curve_power" in _ots_logic else 1.5
	weight = pow(weight, curve_power)
	var side := float(_ots_logic.get("max_side_offset")) if _ots_logic and "max_side_offset" in _ots_logic else 0.75
	var height := float(_ots_logic.get("max_height_offset")) if _ots_logic and "max_height_offset" in _ots_logic else -0.65
	var pivot_z := float(_ots_logic.get("max_pivot_z_offset")) if _ots_logic and "max_pivot_z_offset" in _ots_logic else 0.2
	var right_side := bool(_ots_logic.get("right_side")) if _ots_logic and "right_side" in _ots_logic else true
	var parent := _ots_offset_parent.get_parent() as Spatial
	if not is_instance_valid(parent):
		return
	# X (side) and Z (pivot_z) rotate with the body (player), not the rig.
	# In zero-g, the rig rotates independently (roll), so we need to compensate.
	# Calculate offset in body-space, then de-rotate it by the roll angle.
	var body_local_xz := Vector3(
		side * weight * (1.0 if right_side else -1.0),
		0.0,
		pivot_z * weight
	)
	var world_offset := _body.global_transform.basis.xform(body_local_xz)
	# Compensate: remove the rig's roll rotation from the entire offset vector.
	# The rig rolls around the forward axis: -yp_basis.z
	# So we de-rotate the offset by +roll_angle around that same axis (opposite of rig's rotation).
	var forward_axis := -_last_rolled_basis.z
	var de_roll_basis := Basis(forward_axis, roll_angle)
	world_offset = de_roll_basis.xform(world_offset)
	# Y (height) stays anchored to player-body world UP — does NOT rotate with roll.
	# The world_up projection of the OTS contribution is invariant to roll angle θ
	# because xform_inv(world_up * h) contributes exactly h in world Y regardless of θ.
	var world_up := _body.global_transform.basis.y.normalized()
	world_offset += world_up * height * weight
	# NOTE: Removed hierarchy compensation. In zero-g with roll, the camera should follow
	# the natural hierarchy rotation so it finds the shoulder/neck even when the mesh is inverted.
	_ots_offset_parent.translation = parent.global_transform.basis.xform_inv(world_offset)

func _get_effective_zero_g_arm_length() -> float:
	if _spring_arm and is_instance_valid(_spring_arm):
		var current_len = _spring_arm.get("current_length")
		if current_len != null:
			return float(current_len)
		var spring_len = _spring_arm.get("spring_length")
		if spring_len != null:
			return float(spring_len)
	if "current_spring_length" in _body:
		return float(_body.current_spring_length)
	return 5.0

func _update_zero_g_camera_view(dt: float) -> void:
	if "current_spring_length" in _body and "base_spring_length_3d" in _body:
		_body.current_spring_length = lerp(_body.current_spring_length, _body.base_spring_length_3d, 4.0 * dt)
	if "_cached_spring_arm" in _body and _body._cached_spring_arm and is_instance_valid(_body._cached_spring_arm):
		_body._cached_spring_arm.spring_length = _body.current_spring_length
	if "_cached_cam" in _body and _body._cached_cam and is_instance_valid(_body._cached_cam) and "base_fov" in _body:
		if abs(_body._cached_cam.fov - _body.base_fov) > 0.01:
			_body._cached_cam.fov = lerp(_body._cached_cam.fov, _body.base_fov, 4.0 * dt)
	_snap_camera_rig_y()

func _snap_camera_rig_y() -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_camera_rig):
		return
	# In zero-g, don't reset origin.x/z — let the OTS offset subnodes handle it.
	# Only snap Y to base_rig_y to keep camera at correct height.
	if "base_rig_y" in _body:
		_camera_rig.transform.origin.y = _body.base_rig_y
	if "_camera_rig_y_smoothed_global" in _body:
		_body._camera_rig_y_smoothed_global = _camera_rig.global_transform.origin.y
	if "_camera_rig_airborne_anchor_global" in _body:
		_body._camera_rig_airborne_anchor_global = _camera_rig.global_transform.origin.y
	if "_camera_rig_airborne_rise_time" in _body:
		_body._camera_rig_airborne_rise_time = 0.0
	if "_camera_rig_was_grounded" in _body:
		_body._camera_rig_was_grounded = true
	if "_camera_rig_y_initialized" in _body:
		_body._camera_rig_y_initialized = true

func _clear_spring_arm_camera_offset() -> void:
	if _spring_arm and is_instance_valid(_spring_arm) and _spring_arm.has_method("set_camera_local_offset"):
		_spring_arm.set_camera_local_offset(Vector3.ZERO)

func _update_wish_direction(move_dir: Vector3) -> void:
	if "movement_logic" in _body and is_instance_valid(_body.movement_logic):
		_body.movement_logic.wish_direction = move_dir

func _update_visual_mesh(dt: float, preserved_basis: Basis, has_movement: bool, yp_basis: Basis) -> void:
	if not is_instance_valid(_pilot_mesh):
		return
	var smooth: float = float(_setting("mesh_rotation_smooth", DEFAULT_MESH_ROTATION_SMOOTH))
	# Mesh follows movement direction only when moving (no roll), while camera orbits freely
	var target_basis := yp_basis if has_movement else preserved_basis
	_pilot_mesh.transform.basis = preserved_basis.slerp(target_basis, clamp(smooth * dt, 0.0, 1.0))
	_apply_mesh_center_offset()

func _restore_standard_visual_mesh() -> void:
	if not is_instance_valid(_pilot_mesh):
		return
	var forward := _pilot_mesh.transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3(sin(yaw), 0.0, cos(yaw))
	forward = forward.normalized()
	_pilot_mesh.transform.basis = Basis(Vector3.UP, atan2(forward.x, forward.z))
	_pilot_mesh.transform.origin = Vector3.ZERO

func _apply_mesh_center_offset() -> void:
	var offset: Vector3 = _setting("mesh_center_offset", DEFAULT_MESH_CENTER_OFFSET)
	_pilot_mesh.transform.origin = offset - _pilot_mesh.transform.basis.xform(offset)
