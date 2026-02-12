extends InteractableBaseV2
class_name IrisDoorV2
tool

# IrisDoorV2.gd - Deterministic Iris Door Mechanism
# Rotates child nodes (blades) to open/close an aperture.

export(float) var rotation_angle := 90.0 # Degrees to rotate each blade to open
export(Vector3) var rotation_axis := Vector3(0, 0, 1) # Axis of rotation
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1
export(NodePath) var blades_container_path := NodePath(".")

var _blades: Array = []
var _start_rotations: Array = [] # Stores Vector3 (degrees)
var _initialized := false

func _ready():
	_initialize()
	._ready()

func _initialize():
	_blades.clear()
	_start_rotations.clear()

	var container = get_node_or_null(blades_container_path)
	if not container:
		return

	for child in container.get_children():
		if child is Spatial:
			_blades.append(child)
			_start_rotations.append(child.rotation_degrees)

	_initialized = true

func _update_visuals() -> void:
	if not _initialized:
		return

	var eased = _apply_easing(anim_progress)
	var angle_rad = deg2rad(rotation_angle) * eased

	for i in range(_blades.size()):
		var blade = _blades[i]
		if not is_instance_valid(blade):
			continue

		var start_rot = _start_rotations[i]

		# Reset to start rotation
		blade.rotation_degrees = start_rot
		# Apply rotation around local axis
		if rotation_axis.length_squared() > 0.001:
			blade.rotate_object_local(rotation_axis.normalized(), angle_rad)

		if blade is CollisionObject or blade is CSGShape:
			if blade.has_method("force_update_transform"):
				blade.force_update_transform()

func _apply_easing(t: float) -> float:
	match easing_type:
		0: return t # Linear
		1: return _ease_in_out(t)
		2: return _ease_in(t)
		3: return _ease_out(t)
	return t

func get_snapshot() -> Dictionary:
	var snap = .get_snapshot()
	# Serialize start rotations
	var rots = []
	for r in _start_rotations:
		rots.append([r.x, r.y, r.z])
	snap["start_rots"] = rots
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_rots"):
		var rots = data["start_rots"]
		_start_rotations.clear()
		for r in rots:
			_start_rotations.append(Vector3(r[0], r[1], r[2]))
	.restore_snapshot(data)

func _process(_delta):
	if Engine.editor_hint:
		if not _initialized:
			_initialize()
