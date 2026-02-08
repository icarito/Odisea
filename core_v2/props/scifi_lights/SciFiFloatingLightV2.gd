class_name SciFiFloatingLightV2
extends KinematicBody

export var float_amplitude := 0.2
export var float_speed := 2.0
export var patrol_speed := 2.0
export var is_patrolling := false

var _time_accumulator := 0.0
var _start_pos := Vector3.ZERO
var _patrol_points := []
var _current_patrol_index := 0
var _patrol_progress := 0.0

func _init():
	add_to_group("replay_sync")

func _ready():
	_start_pos = translation
	if is_patrolling:
		# Use parent's Position3D children as waypoints if we want to separate logic?
		# Or just look for children of THIS node?
		# Typically waypoints are siblings or children of a parent container.
		# Let's assume specific child nodes named "Waypoint*" or just all Position3D children.
		for child in get_children():
			if child is Position3D:
				_patrol_points.append(child.translation)

		# If no children, check parent for "Path" node? Too complex.
		# Let's stick to children. If user wants path, they add Position3D children.
		if _patrol_points.empty():
			is_patrolling = false
		else:
			# Start at first point
			translation = _patrol_points[0]
			_start_pos = translation # Floating is relative to this

func _physics_process(delta):
	_time_accumulator += delta

	var base_pos = _start_pos

	if is_patrolling and _patrol_points.size() > 1:
		var p1 = _patrol_points[_current_patrol_index]
		var p2 = _patrol_points[(_current_patrol_index + 1) % _patrol_points.size()]
		var dist = p1.distance_to(p2)

		if dist > 0.001:
			_patrol_progress += (patrol_speed * delta) / dist
		else:
			_patrol_progress = 1.0

		if _patrol_progress >= 1.0:
			_patrol_progress -= 1.0
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
			p1 = _patrol_points[_current_patrol_index]
			p2 = _patrol_points[(_current_patrol_index + 1) % _patrol_points.size()]

		base_pos = p1.linear_interpolate(p2, _patrol_progress)

		# Optional: Rotate to face movement direction
		var dir = (p2 - p1).normalized()
		if dir.length_squared() > 0.01:
			# Simple look_at logic, can be improved for smoothness
			var target_look = global_transform.origin + dir
			look_at(target_look, Vector3.UP)

	# Floating effect
	var float_offset = Vector3(0, sin(_time_accumulator * float_speed) * float_amplitude, 0)

	translation = base_pos + float_offset

func restore_snapshot(data: Dictionary):
	if "time" in data:
		_time_accumulator = data["time"]
	if "patrol_idx" in data:
		_current_patrol_index = data["patrol_idx"]
	if "patrol_prog" in data:
		_patrol_progress = data["patrol_prog"]

	# Re-run physics process with 0 delta to update position based on restored state
	_physics_process(0)

func get_snapshot() -> Dictionary:
	return {
		"time": _time_accumulator,
		"patrol_idx": _current_patrol_index,
		"patrol_prog": _patrol_progress
	}
