class_name SciFiFloatingLight
extends KinematicBody

export var float_amplitude := 0.2
export var float_speed := 2.0
export var patrol_speed := 2.0
export var is_patrolling := false

var is_active := true
var _time_accumulator := 0.0
var _start_pos := Vector3.ZERO
var _patrol_points := []
var _current_patrol_index := 0
var _patrol_progress := 0.0

var _omni_light: OmniLight = null
var _mesh: MeshInstance = null
var _light_energy_max := 2.0

signal activated()
signal deactivated()

func _init():
	add_to_group("replay_sync")

func _ready():
	_start_pos = translation
	# Cache references
	for child in get_children():
		if child is OmniLight and not _omni_light:
			_omni_light = child
			_light_energy_max = child.light_energy
		elif child is MeshInstance and not _mesh:
			_mesh = child
	
	if is_patrolling:
		for child in get_children():
			if child is Position3D:
				_patrol_points.append(child.translation)

		if _patrol_points.empty():
			is_patrolling = false
		else:
			translation = _patrol_points[0]
			_start_pos = translation

func set_active(value: bool, _immediate: bool = false) -> void:
	if is_active == value:
		return
	is_active = value
	_update_light()
	if is_active:
		emit_signal("activated")
	else:
		emit_signal("deactivated")

func interact() -> void:
	set_active(not is_active)

func _update_light():
	if _omni_light:
		_omni_light.light_energy = _light_energy_max if is_active else 0.0
	if _mesh and _mesh.material_override is SpatialMaterial:
		_mesh.material_override.emission_energy = 3.0 if is_active else 0.0

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

		var dir = (p2 - p1).normalized()
		if dir.length_squared() > 0.01:
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
	if "active" in data:
		is_active = data["active"]
		_update_light()
	_physics_process(0)

func get_snapshot() -> Dictionary:
	return {
		"time": _time_accumulator,
		"patrol_idx": _current_patrol_index,
		"patrol_prog": _patrol_progress,
		"active": is_active
	}
