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
var _snap_visual_next_frame := false

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
	_snap_visual_next_frame = true

func reset_visual_state() -> void:
	roll_angle = 0.0
	_refresh_runtime_refs()
	if is_instance_valid(_pilot_mesh):
		_pilot_mesh.transform = Transform()

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
		pitch = clamp(pitch, deg2rad(-89.0), deg2rad(89.0))
		var roll_input := 0.0
		if input.roll_left:  roll_input += 1.0
		if input.roll_right: roll_input -= 1.0
		roll_angle += roll_input * deg2rad(_setting("roll_speed_deg", DEFAULT_ROLL_SPEED_DEG)) * dt

	if "yaw"   in _body: _body.yaw   = yaw
	if "pitch" in _body: _body.pitch = pitch
	if _body.has_method("_update_camera_orbit_state"):
		var orbit_input := InputDataV2.new()
		if input:
			orbit_input.zoom_delta = input.zoom_delta
			orbit_input.fov_override = input.fov_override
		_body._update_camera_orbit_state(dt, orbit_input, false, false)
		yaw = _body.yaw if "yaw" in _body else yaw
		pitch = _body.pitch if "pitch" in _body else pitch

	# 2. Write to rig root. Same as PlayerControllerV2 normal mode plus roll.
	#    Subnodes (Yaw, Pitch, OTS, SpringArm) are NOT touched.
	var yp_basis     := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var forward_axis := -yp_basis.z
	var rolled_basis := Basis(forward_axis, roll_angle) * yp_basis
	var prefix: Basis = _body.get("camera_basis_prefix") if "camera_basis_prefix" in _body else Basis.IDENTITY
	_camera_rig.transform.basis = prefix * rolled_basis
	_camera_rig.force_update_transform()

	if "yaw"   in _body: _body.yaw   = yaw
	if "pitch" in _body: _body.pitch = pitch
	_last_sync_yaw   = yaw
	_last_sync_pitch = pitch
	_last_sync_roll  = roll_angle

	# 3. Movement uses the effective camera orientation, but exit/visual state keeps
	#    the zero-g rig basis so SpringArm bakes do not leak into controller state.
	var movement_basis := (rolled_basis * _camera_child_basis).orthonormalized()
	_last_rolled_basis = rolled_basis
	var move_dir := Vector3.ZERO
	if input:
		var fwd   := -movement_basis.z
		var right :=  movement_basis.x
		var up    :=  movement_basis.y
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
		var speed_mult := float(_setting("sprint_multiplier", DEFAULT_SPRINT_MULTIPLIER)) if input and input.sprint else 1.0
		var target_v   := move_dir * float(_setting("max_speed", DEFAULT_MAX_SPEED)) * speed_mult
		var accel_t    := clamp(float(_setting("acceleration", DEFAULT_ACCELERATION)) * dt, 0.0, 1.0)
		_body.velocity = _body.velocity.linear_interpolate(target_v, accel_t)

	# 5. Move.
	_body.velocity = _body.move_and_slide(_body.velocity, Vector3.UP)
	velocity = _body.velocity

	# 6. Y-lag camera follow. Zoom is handled by _update_camera_orbit_state above.
	if _body.has_method("_update_camera_view"):
		_body._update_camera_view(dt)

	# 7. Visuals.
	var mesh_basis_before := _pilot_mesh.transform.basis if is_instance_valid(_pilot_mesh) else Basis()
	if "animator" in _body and is_instance_valid(_body.animator) and _body.animator.has_method("step_animator"):
		_body.animator.step_animator(dt, _body.velocity)
	_update_visual_mesh(dt, mesh_basis_before)

func _refresh_runtime_refs() -> void:
	if not is_instance_valid(_body):
		return
	_settings   = _body.get_node_or_null("Logic/ZeroGravity")
	_camera_rig = _body.get_node_or_null("CameraRig") as Spatial
	_camera     = _find_camera(_camera_rig)
	_pilot_mesh = _body.get_node_or_null("Visual/Pivot")
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

func _update_wish_direction(move_dir: Vector3) -> void:
	if "movement_logic" in _body and is_instance_valid(_body.movement_logic):
		_body.movement_logic.wish_direction = move_dir

func _update_visual_mesh(dt: float, preserved_basis: Basis) -> void:
	if not is_instance_valid(_pilot_mesh):
		return
	var smooth: float = float(_setting("mesh_rotation_smooth", DEFAULT_MESH_ROTATION_SMOOTH))
	var target_basis := _last_rolled_basis
	if _snap_visual_next_frame:
		_pilot_mesh.transform.basis = target_basis
		_snap_visual_next_frame = false
	else:
		_pilot_mesh.transform.basis = preserved_basis.slerp(target_basis, clamp(smooth * dt, 0.0, 1.0))
	_apply_mesh_center_offset()

func _apply_mesh_center_offset() -> void:
	var offset: Vector3 = _setting("mesh_center_offset", DEFAULT_MESH_CENTER_OFFSET)
	_pilot_mesh.transform.origin = offset - _pilot_mesh.transform.basis.xform(offset)
