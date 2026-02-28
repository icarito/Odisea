extends InteractableBaseV2
class_name IrisDoorV2
tool

# IrisDoorV2.gd - Mathematically Perfect Iris Door Mechanism (v6.1 GAP FIX VERSION)
# Automates pivot positioning and ensures hermetic closure by overlapping tips.

export(float) var rotation_angle := -95.0 setget set_rotation_angle
export(Vector3) var rotation_axis := Vector3(0, 0, 1) setget set_rotation_axis
export(float) var offset_per_blade := 0.005 setget set_offset_per_blade
export(float) var iris_radius := 0.5 setget set_iris_radius
export(bool) var rebuild_now := false setget set_rebuild_now # Manual trigger
export(bool) var rebuild_at_runtime := true
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1
export(NodePath) var blades_container_path := NodePath(".")

func set_rotation_angle(v: float) -> void:
	rotation_angle = v
	_update_visuals()

func set_rotation_axis(v: Vector3) -> void:
	rotation_axis = v
	_update_visuals()

func set_offset_per_blade(v: float) -> void:
	offset_per_blade = v
	_initialize()
	_setup_mathematical_positions()
	_update_visuals()

func set_iris_radius(v: float) -> void:
	iris_radius = v
	_setup_mathematical_positions()
	_update_visuals()

func set_rebuild_now(_v: bool) -> void:
	_initialize()
	_setup_mathematical_positions()
	_update_visuals()

var _blades: Array = []
var _start_rotations: Array = []
var _initialized := false

func _ready():
	_initialize()
	if rebuild_at_runtime or Engine.editor_hint:
		_setup_mathematical_positions()
	._ready()

func _initialize():
	_blades.clear()
	_start_rotations.clear()

	var container = get_node_or_null(blades_container_path)
	if not container:
		return

	var children = container.get_children()
	for child in children:
		if child is Spatial and child.name.begins_with("BladePivot"):
			_blades.append(child)
	
	# Sort blades by name for consistent Z-stacking
	_blades.sort_custom(self, "_sort_blades")
	
	for i in range(_blades.size()):
		_start_rotations.append(_blades[i].rotation_degrees)

	_initialized = true

func _sort_blades(a, b):
	return a.name < b.name

func _setup_mathematical_positions():
	if not _initialized:
		_initialize()
	
	var count = _blades.size()
	if count == 0:
		return
	
	for i in range(count):
		var blade = _blades[i]
		var angle = (PI * 2.0 / count) * i
		var x = cos(angle) * iris_radius
		var y = sin(angle) * iris_radius
		
		# Position in circle with Z offset for stacking
		blade.transform.origin = Vector3(x, y, i * offset_per_blade)
		
		# Base Orientation: Pointing towards the center (CLOSED state)
		# We add PI (180 degrees) to the positional angle to look at (0,0)
		blade.rotation = Vector3(0, 0, angle + PI)
		
		# Update the start rotation buffer
		if _start_rotations.size() <= i:
			_start_rotations.append(blade.rotation_degrees)
		else:
			_start_rotations[i] = blade.rotation_degrees

func _update_visuals() -> void:
	if not _initialized:
		_initialize()
		if Engine.editor_hint: _setup_mathematical_positions()

	var eased = _apply_easing(anim_progress)
	# State Base (0.0): Offset 0
	# State Open (1.0): Offset +90 degrees (Tangential Outward)
	var open_angle_rad = deg2rad(90.0)
	var current_offset = lerp(0.0, open_angle_rad, eased)

	for i in range(_blades.size()):
		var blade = _blades[i]
		if not is_instance_valid(blade):
			continue

		var start_rot_deg = _start_rotations[i]
		# Apply base rotation + dynamic tangential offset
		blade.rotation_degrees.z = start_rot_deg.z + rad2deg(current_offset)

		if blade is CollisionObject or blade is CSGShape:
			if blade.has_method("force_update_transform"):
				blade.force_update_transform()

func _apply_easing(t: float) -> float:
	match easing_type:
		0: return t
		1: return _ease_in_out(t)
		2: return _ease_in(t)
		3: return _ease_out(t)
	return t

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
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
			_setup_mathematical_positions()
