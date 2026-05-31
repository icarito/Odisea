extends Spatial
class_name ZeroGCameraRig

# Dedicated no-collision camera rig for zero gravity. The camera is kept at a
# fixed local -Z offset so it matches the side used by the standard orbit rig.
export(float) var camera_distance := 4.0 setget set_camera_distance
export(float) var camera_fov := 75.0 setget set_camera_fov
export(float) var target_offset_y := 0.2 setget set_target_offset_y
export(float) var follow_smooth := 8.0

var _camera: Camera = null
var _orientation := Quat()
var _follow_local_origin := Vector3.ZERO
var _smoothed_global_origin := Vector3.ZERO
var _follow_initialized := false


func _ready() -> void:
	_ensure_children()
	_orientation = transform.basis.get_rotation_quat().normalized()
	_follow_local_origin = transform.origin
	_apply_camera_layout()
	set_active(false)

func apply_zero_g_settings(settings: Node) -> void:
	if settings == null:
		return
	if "camera_distance" in settings:
		camera_distance = float(settings.camera_distance)
	if "camera_fov" in settings:
		camera_fov = float(settings.camera_fov)
	if "camera_follow_smooth" in settings:
		follow_smooth = float(settings.camera_follow_smooth)
	_apply_camera_layout()

func set_camera_distance(value: float) -> void:
	camera_distance = max(0.1, value)
	_apply_camera_layout()

func set_camera_fov(value: float) -> void:
	camera_fov = clamp(value, 1.0, 179.0)
	_apply_camera_layout()

func set_target_offset_y(value: float) -> void:
	target_offset_y = value
	_apply_camera_layout()

func apply_orientation(yaw: float, pitch: float, roll: float) -> void:
	set_orientation_euler(yaw, pitch, roll)

func set_orientation_euler(yaw: float, pitch: float, roll: float) -> void:
	_orientation = (
		Quat(Vector3.UP, yaw)
		* Quat(Vector3.RIGHT, pitch)
		* Quat(Vector3.FORWARD, roll)
	).normalized()
	_apply_orientation_basis()

func set_orientation_basis(basis: Basis) -> void:
	_orientation = basis.orthonormalized().get_rotation_quat().normalized()
	_apply_orientation_basis()

func sync_orientation_from_transform() -> void:
	_orientation = transform.basis.orthonormalized().get_rotation_quat().normalized()
	_apply_orientation_basis()

func update_orientation_local(mouse_delta: Vector2, sens: float, roll_rate: float, dt: float) -> void:
	var current_basis := Basis(_orientation).orthonormalized()
	var local_right := current_basis.x.normalized()
	var local_forward := (-current_basis.z).normalized()

	var yaw_quat := Quat(Vector3.UP, -mouse_delta.x * sens)
	var pitch_quat := Quat(local_right, mouse_delta.y * sens)
	var roll_quat := Quat(local_forward, roll_rate * dt)

	_orientation = (roll_quat * pitch_quat * yaw_quat * _orientation).normalized()
	_apply_orientation_basis()

func reset_follow_state(target: Spatial = null) -> void:
	_follow_local_origin = transform.origin
	_smoothed_global_origin = global_transform.origin
	if target:
		_smoothed_global_origin = target.global_transform.xform(_follow_local_origin)
		var t: Transform = global_transform
		t.origin = _smoothed_global_origin
		global_transform = t
	_follow_initialized = true

func update_follow(target: Spatial, dt: float) -> void:
	if target == null:
		return
	var target_origin: Vector3 = target.global_transform.xform(_follow_local_origin)
	if not _follow_initialized or dt <= 0.0 or follow_smooth <= 0.0:
		_smoothed_global_origin = target_origin
		_follow_initialized = true
	else:
		var follow_t: float = clamp(1.0 - exp(-follow_smooth * dt), 0.0, 1.0)
		_smoothed_global_origin = _smoothed_global_origin.linear_interpolate(target_origin, follow_t)
	var t: Transform = global_transform
	t.origin = _smoothed_global_origin
	global_transform = t
	force_update_transform()

func get_orientation_euler() -> Vector3:
	var basis := transform.basis
	var forward := -basis.z
	
	var yaw_val := 0.0
	var forward_h := Vector3(forward.x, 0.0, forward.z)
	if forward_h.length_squared() > 0.0001:
		forward_h = forward_h.normalized()
		yaw_val = atan2(-forward_h.x, -forward_h.z)
	else:
		# Fallback to prevent NaN when looking directly UP or DOWN
		yaw_val = atan2(-basis.x.z, basis.x.x)
		
	var pitch_val := asin(clamp(forward.y, -1.0, 1.0))
	
	var yp_basis := Basis(Vector3.UP, yaw_val) * Basis(Vector3.RIGHT, pitch_val)
	var roll_basis := yp_basis.inverse() * basis
	var roll_val := atan2(-roll_basis.x.y, roll_basis.x.x)
	
	return Vector3(yaw_val, pitch_val, roll_val)

func set_active(active: bool) -> void:
	visible = active
	var cam := get_camera()
	if cam:
		cam.current = active

func get_camera() -> Camera:
	if not is_instance_valid(_camera):
		_camera = find_node("Camera", true, false) as Camera
	return _camera

func get_movement_basis() -> Basis:
	return global_transform.basis

func _ensure_children() -> void:
	var spring := get_node_or_null("SpringArm") as Spatial
	if spring == null:
		spring = Spatial.new()
		spring.name = "SpringArm"
		add_child(spring)
	if spring.get_node_or_null("Camera") == null:
		var cam := Camera.new()
		cam.name = "Camera"
		spring.add_child(cam)
	_camera = spring.get_node_or_null("Camera") as Camera

func _apply_camera_layout() -> void:
	var cam := get_camera()
	if cam == null:
		return
	cam.transform = Transform(Basis.IDENTITY, Vector3(0.0, target_offset_y, camera_distance))
	cam.fov = camera_fov
	cam.near = 0.01
	cam.far = 10000.0

func _apply_orientation_basis() -> void:
	transform.basis = Basis(_orientation).orthonormalized()
	force_update_transform()
