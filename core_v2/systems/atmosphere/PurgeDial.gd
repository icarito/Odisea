extends Spatial
class_name PurgeDial

# PurgeDial.gd - Deterministic tuning dial minigame for atmosphere pressure purge (FD-258 / FD-255).

# Current dial position in range 0.0 .. 1.0.
export(float) var value: float = 0.0
# Target center position for green stable pressure zone (0.0 .. 1.0).
export(float) var target: float = 0.62
# Half-width tolerance of the green zone around target.
export(float) var tolerance: float = 0.06
# Time in seconds required to hold value inside green zone to lock and purge.
export(float) var hold_duration: float = 1.2
# NodePath to the target PressureSection to purge.
export(NodePath) var section_path: NodePath

signal dial_locked()
signal dial_slipped()

var _hold_timer: float = 0.0
var _is_locked: bool = false


func _ready() -> void:
	add_to_group("replay_sync")


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	var is_in_zone: bool = abs(value - target) <= tolerance
	if is_in_zone:
		if not _is_locked:
			_hold_timer += delta
			if _hold_timer >= hold_duration:
				_is_locked = true
				emit_signal("dial_locked")
				_trigger_purge()
	else:
		if _hold_timer > 0.0 and not _is_locked:
			emit_signal("dial_slipped")
		_hold_timer = 0.0
		_is_locked = false


func nudge(delta_value: float) -> void:
	value = clamp(value + delta_value, 0.0, 1.0)


func get_proximity() -> float:
	var max_distance: float = max(target, 1.0 - target)
	if max_distance <= 0.0:
		return 1.0
	return clamp(1.0 - abs(value - target) / max_distance, 0.0, 1.0)


func is_locked() -> bool:
	return _is_locked


func get_hold_timer() -> float:
	return _hold_timer


func reset() -> void:
	_hold_timer = 0.0
	_is_locked = false


func _trigger_purge() -> void:
	if section_path != null and not section_path.is_empty():
		var section = get_node_or_null(section_path)
		if section and section.has_method("purge"):
			section.purge()


func get_snapshot() -> Dictionary:
	return {
		"value": value,
		"hold_timer": _hold_timer,
		"is_locked": _is_locked
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("value"):
		value = float(data["value"])
	if data.has("hold_timer"):
		_hold_timer = float(data["hold_timer"])
	if data.has("is_locked"):
		_is_locked = bool(data["is_locked"])
