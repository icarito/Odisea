extends StaticBody
class_name CoolantTank

# CoolantTank.gd - Cryocoolant source tank (FD-264 / FD-266).
# Manages coolant supply level and baseline pressure without causing player defeat when empty.

export(float, 0.0, 1.0) var tank_level: float = 1.0 setget set_tank_level
# drain_rate es la tasa base de vaciado por segundo cuando la fuga está al 100% (default ~0.015 => ~66s para vaciarse entero)
export(float, 0.0, 10.0) var drain_rate: float = 0.015

signal level_changed(new_level)

onready var _level_band: CSGCylinder = get_node_or_null("LevelBand")
onready var _sight_column: CSGCylinder = get_node_or_null("LevelGauge/SightColumn")

const GAUGE_MIN_Y := 0.6
const GAUGE_MAX_HEIGHT := 2.2

func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("coolant_source")
	_update_visuals()


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	# El drenaje se calcula en CoolantFlowAdapter según las fugas activas presurizadas de la rama.


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

	if _sight_column == null:
		_sight_column = get_node_or_null("LevelGauge/SightColumn")
	if _sight_column:
		var current_h := GAUGE_MAX_HEIGHT * tank_level
		_sight_column.visible = current_h > 0.01
		_sight_column.height = max(0.02, current_h)
		_sight_column.translation.y = GAUGE_MIN_Y + current_h * 0.5


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
