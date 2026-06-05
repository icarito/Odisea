extends Node
class_name SGCCameraWarp

# FD-052: SGC Camera Warp
# WorldRotator stays authoritative for support alignment. This node only
# softens abrupt support snaps by applying a temporary counter-roll to the
# player's camera and easing it back to neutral.

export(float) var lerp_speed := 12.0
export(NodePath) var rotator_path := NodePath("../WorldRotator")
export(NodePath) var camera_yaw_path := NodePath("../Pilot/CameraRig/Yaw")
export(float) var snap_threshold_degrees := 3.0

var _rotator: Spatial = null
var _yaw: Spatial = null
var _last_rotator_roll := 0.0
var _camera_roll_offset := 0.0

func _ready() -> void:
	call_deferred("_resolve_nodes")

func _resolve_nodes() -> void:
	_rotator = get_node_or_null(rotator_path) as Spatial
	_yaw = get_node_or_null(camera_yaw_path) as Spatial
	if _rotator == null:
		push_warning("SGCCameraWarp: rotator not found at %s" % rotator_path)
	if _yaw == null:
		push_warning("SGCCameraWarp: camera yaw not found at %s" % camera_yaw_path)
	_last_rotator_roll = _get_rotator_roll()

func _physics_process(delta: float) -> void:
	if _rotator == null or _yaw == null:
		return
	var rotator_roll: float = _get_rotator_roll()
	var delta_roll: float = _wrap_angle(rotator_roll - _last_rotator_roll)
	_last_rotator_roll = rotator_roll
	if abs(delta_roll) >= deg2rad(snap_threshold_degrees):
		_camera_roll_offset -= delta_roll
	var t: float = min(1.0, lerp_speed * delta)
	_camera_roll_offset = lerp(_camera_roll_offset, 0.0, t)
	_yaw.rotation.z = _camera_roll_offset

func _get_rotator_roll() -> float:
	if _rotator == null:
		return 0.0
	return _rotator.transform.basis.get_euler().z

func _wrap_angle(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle
