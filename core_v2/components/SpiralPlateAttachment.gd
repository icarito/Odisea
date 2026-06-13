extends Spatial
class_name SpiralPlateAttachment

# Keeps authored lights/props in WorldRotator canonical space, or optionally
# attaches them to a generated TerraceSpiral plate.
#
# Use AUTHORED_CANONICAL for axis/corridor lights placed in the editor.
# Use PLATE only for objects that must follow one generated MultiMesh plate.

enum AttachmentMode {
	AUTHORED_CANONICAL,
	PLATE
}

export(NodePath) var rotator_path := NodePath("")
export(int, "AUTHORED_CANONICAL", "PLATE") var attachment_mode := AttachmentMode.AUTHORED_CANONICAL
export(int, 0, 31) var spiral_index := 0
export(int, 0, 10000) var plate_index := 0
export(Vector3) var local_offset := Vector3.ZERO
export(Vector3) var local_rotation_degrees := Vector3.ZERO
export(bool) var follow_selected_plate := false
export(bool) var update_every_frame := true

var _rotator: Spatial = null
var _authored_canonical_transform := Transform.IDENTITY
var _has_authored_canonical_transform := false

func _ready() -> void:
	_resolve_rotator()
	_capture_authored_canonical_transform()
	_update_attachment()
	set_process(update_every_frame)

func _process(_delta: float) -> void:
	_update_attachment()

func force_update() -> void:
	_update_attachment()

func _resolve_rotator() -> void:
	if not rotator_path.is_empty():
		_rotator = get_node_or_null(rotator_path) as Spatial
		if _rotator == null and get_parent():
			_rotator = get_parent().get_node_or_null(rotator_path) as Spatial
		if _rotator != null:
			return

	var node: Node = self
	while node != null:
		if node.has_method("get_plate_canonical_transform") and node.has_method("get_platforms"):
			_rotator = node as Spatial
			return
		node = node.get_parent()

func _update_attachment() -> void:
	if _rotator == null or not is_instance_valid(_rotator):
		_resolve_rotator()
	if _rotator == null or not is_instance_valid(_rotator):
		return

	if attachment_mode == AttachmentMode.AUTHORED_CANONICAL:
		if not _has_authored_canonical_transform:
			_capture_authored_canonical_transform()
		if _has_authored_canonical_transform:
			global_transform = _rotator.global_transform * _authored_canonical_transform
		return

	if not _rotator.has_method("get_platforms") or not _rotator.has_method("get_plate_canonical_transform"):
		return

	var platforms: Array = _rotator.get_platforms()
	if platforms.empty():
		if _rotator.has_method("_auto_register_platforms"):
			_rotator.call("_auto_register_platforms")
			platforms = _rotator.get_platforms()
	if platforms.empty():
		return

	var target_spiral: int = spiral_index
	var target_plate: int = plate_index
	if follow_selected_plate:
		if _rotator.has_method("get_selected_spiral_index"):
			target_spiral = int(_rotator.get_selected_spiral_index())
		if _rotator.has_method("get_selected_plate_index"):
			target_plate = int(_rotator.get_selected_plate_index())

	target_spiral = _wrap_index(target_spiral, platforms.size())
	var spiral: Spatial = platforms[target_spiral] as Spatial
	if spiral == null:
		return
	if _rotator.has_method("_force_spiral_update"):
		_rotator.call("_force_spiral_update", spiral)
	var plate_count: int = _rotator.get_plate_count(spiral) if _rotator.has_method("get_plate_count") else 0
	if plate_count <= 0:
		return
	target_plate = int(clamp(target_plate, 0, plate_count - 1))

	var plate_canonical: Transform = _rotator.get_plate_canonical_transform(spiral, target_plate)
	var offset_basis := Basis(
			Vector3(deg2rad(local_rotation_degrees.x), deg2rad(local_rotation_degrees.y), deg2rad(local_rotation_degrees.z)))
	var local_tx := Transform(offset_basis, local_offset)
	global_transform = _rotator.global_transform * plate_canonical * local_tx

func _capture_authored_canonical_transform() -> void:
	if _rotator == null or not is_instance_valid(_rotator):
		return
	_authored_canonical_transform = _rotator.global_transform.affine_inverse() * global_transform
	_has_authored_canonical_transform = true

func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	var wrapped := value % size
	if wrapped < 0:
		wrapped += size
	return wrapped
