tool
extends StaticBody
class_name CoolantTank

# CoolantTank.gd - Cryocoolant source tank (FD-264).
# Manages coolant supply level and baseline pressure without causing player defeat when empty.

export(float, 0.0, 1.0) var tank_level: float = 1.0 setget set_tank_level
export(float, 0.0, 10.0) var drain_rate: float = 0.0

signal level_changed(new_level)

onready var _level_band: CSGCylinder = get_node_or_null("LevelBand")


func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("coolant_source")
	_update_visuals()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	if drain_rate > 0.0 and tank_level > 0.0:
		set_tank_level(max(0.0, tank_level - drain_rate * delta))


func set_tank_level(v: float) -> void:
	var old_level := tank_level
	tank_level = clamp(v, 0.0, 1.0)
	if tank_level != old_level:
		emit_signal("level_changed", tank_level)
		_update_visuals()


func get_pressure() -> float:
	# Base tank pressure proportional to fluid level
	return tank_level


func _update_visuals() -> void:
	if not is_inside_tree():
		return
	if _level_band == null:
		_level_band = get_node_or_null("LevelBand")
	if _level_band:
		_level_band.visible = tank_level > 0.01
		var mat = _level_band.material
		if mat is ShaderMaterial:
			mat.set_shader_param("emission_strength", 1.4 * tank_level)


func get_snapshot() -> Dictionary:
	return {
		"tank_level": tank_level,
		"drain_rate": drain_rate
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("drain_rate"):
		drain_rate = float(data["drain_rate"])
	if data.has("tank_level"):
		set_tank_level(float(data["tank_level"]))
