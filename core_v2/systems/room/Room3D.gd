extends BaseZoneV2
class_name Room3D

# Room3D.gd - Environmental state per room (temperature, pressure, contamination) for FD-269.
# Aggregates deltas from sources (leaks, heaters, vents) and emits threshold signals.

# --- EXPORTED ENVIRONMENTAL STATE ---
export(float) var temperature: float = 20.0 setget set_temperature
export(float) var pressure: float = 1.0 setget set_pressure
export(float) var contamination: float = 0.0 setget set_contamination

# --- EXPORTED DISCRETE THRESHOLDS ---
export(float) var freezing_point: float = 0.0
export(float) var lethal_cold: float = -50.0
export(float) var absolute_cryo_threshold: float = -150.0
export(float) var fog_threshold: float = 0.3
export(float) var hazard_threshold: float = 0.7
export(float) var overpressure: float = 2.4

# --- EXPORTED DAMAGE TUNING ---
export(float) var cold_damage_per_second: float = 15.0
export(float) var vapor_damage_per_second: float = 20.0
export(float) var cryo_proximity_distance: float = 3.0
export(float) var cryo_shock_damage_per_second: float = 40.0
# En Dome_Intro, al cerrar ambas fugas el ambiente se recupera lentamente hasta 0°C.
# Queda apagado por defecto para no alterar otras salas/hazards.
export(bool) var recover_from_inactive_coolant_leaks: bool = false
export(float, 0.0, 10.0) var coolant_temperature_recovery_rate: float = 0.25

# --- SIGNALS ---
signal temperature_changed(new_value)
signal pressure_changed(new_value)
signal contamination_changed(new_value)

signal freezing_changed(is_freezing)
signal lethal_cold_changed(is_lethal_cold)
signal absolute_cryo_changed(is_absolute_cryo)
signal fog_changed(is_fog_active)
signal hazard_changed(is_hazard_active)
signal overpressure_changed(is_overpressured)

signal threshold_crossed(variable_name, threshold_name, is_triggered)

# --- INTERNAL THRESHOLD LATCHES ---
var _is_freezing: bool = false
var _is_lethal_cold: bool = false
var _is_absolute_cryo: bool = false
var _is_fog_active: bool = false
var _is_hazard_active: bool = false
var _is_overpressured: bool = false


func _ready() -> void:
	._ready()
	add_to_group("replay_sync")
	add_to_group("room_3d")
	_evaluate_thresholds(false)


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	_recover_temperature_without_coolant_flow(delta)
	_evaluate_thresholds(true)
	_apply_environmental_hazards(delta)


# --- PUBLIC API FOR SOURCES (DELTAS) ---

func add_temperature(delta_val: float) -> void:
	set_temperature(temperature + delta_val)


func add_pressure(delta_val: float) -> void:
	set_pressure(pressure + delta_val)


func add_contamination(delta_val: float) -> void:
	set_contamination(contamination + delta_val)


func set_temperature(val: float) -> void:
	val = max(-273.15, val)
	if not is_equal_approx(temperature, val):
		temperature = val
		emit_signal("temperature_changed", temperature)
		_evaluate_thresholds(true)


func set_pressure(val: float) -> void:
	val = max(0.0, val)
	if not is_equal_approx(pressure, val):
		pressure = val
		emit_signal("pressure_changed", pressure)
		_evaluate_thresholds(true)


func set_contamination(val: float) -> void:
	val = clamp(val, 0.0, 1.0)
	if not is_equal_approx(contamination, val):
		contamination = val
		emit_signal("contamination_changed", contamination)
		_evaluate_thresholds(true)


func _recover_temperature_without_coolant_flow(delta: float) -> void:
	if not recover_from_inactive_coolant_leaks or temperature >= freezing_point:
		return
	if get_tree() == null:
		return
	for leak in get_tree().get_nodes_in_group("coolant_leak"):
		if is_instance_valid(leak) and leak.has_method("get_leak_intensity"):
			if float(leak.call("get_leak_intensity")) > 0.0001:
				return
	set_temperature(min(freezing_point, temperature + coolant_temperature_recovery_rate * delta))


# --- QUERY HELPERS ---

func is_freezing() -> bool:
	return _is_freezing


func is_lethal_cold() -> bool:
	return _is_lethal_cold


func is_absolute_cryo() -> bool:
	return _is_absolute_cryo


func is_fog_active() -> bool:
	return _is_fog_active


func is_hazard_active() -> bool:
	return _is_hazard_active


func is_overpressured() -> bool:
	return _is_overpressured


# --- THRESHOLD EVALUATION ---

func _evaluate_thresholds(emit_signals: bool) -> void:
	var freezing := (temperature <= freezing_point)
	if freezing != _is_freezing:
		_is_freezing = freezing
		if emit_signals:
			emit_signal("freezing_changed", _is_freezing)
			emit_signal("threshold_crossed", "temperature", "freezing_point", _is_freezing)

	var lethal := (temperature <= lethal_cold)
	if lethal != _is_lethal_cold:
		_is_lethal_cold = lethal
		if emit_signals:
			emit_signal("lethal_cold_changed", _is_lethal_cold)
			emit_signal("threshold_crossed", "temperature", "lethal_cold", _is_lethal_cold)

	var abs_cryo := (temperature <= absolute_cryo_threshold)
	if abs_cryo != _is_absolute_cryo:
		_is_absolute_cryo = abs_cryo
		if emit_signals:
			emit_signal("absolute_cryo_changed", _is_absolute_cryo)
			emit_signal("threshold_crossed", "temperature", "absolute_cryo_threshold", _is_absolute_cryo)

	var fog := (contamination >= fog_threshold)
	if fog != _is_fog_active:
		_is_fog_active = fog
		if emit_signals:
			emit_signal("fog_changed", _is_fog_active)
			emit_signal("threshold_crossed", "contamination", "fog_threshold", _is_fog_active)

	var hazard := (contamination >= hazard_threshold)
	if hazard != _is_hazard_active:
		_is_hazard_active = hazard
		if emit_signals:
			emit_signal("hazard_changed", _is_hazard_active)
			emit_signal("threshold_crossed", "contamination", "hazard_threshold", _is_hazard_active)

	var overpress := (pressure > overpressure)
	if overpress != _is_overpressured:
		_is_overpressured = overpress
		if emit_signals:
			emit_signal("overpressure_changed", _is_overpressured)
			emit_signal("threshold_crossed", "pressure", "overpressure", _is_overpressured)


# --- ENVIRONMENTAL DAMAGE ---

func _apply_environmental_hazards(delta: float) -> void:
	var base_damage_to_apply := 0.0

	if _is_lethal_cold:
		base_damage_to_apply += cold_damage_per_second * delta

	if _is_hazard_active:
		base_damage_to_apply += vapor_damage_per_second * delta

	var players := get_tree().get_nodes_in_group("player")
	if players.empty():
		return

	for node in players:
		if not is_instance_valid(node) or not (node is Spatial):
			continue

		var player_damage := base_damage_to_apply
		var player_pos: Vector3 = (node as Spatial).global_transform.origin

		# Check cryogenic shock conditions (Absolute Cryo threshold OR proximity < 3m to active leak or cryo vent)
		var is_cryo_shock := _is_absolute_cryo
		if not is_cryo_shock:
			is_cryo_shock = _is_near_active_coolant_source(player_pos)

		if is_cryo_shock:
			player_damage += cryo_shock_damage_per_second * delta

		if player_damage <= 0.0:
			continue

		if node.has_method("take_damage"):
			node.call("take_damage", player_damage)
		elif node.has_method("apply_damage"):
			node.call("apply_damage", player_damage)
		elif node.has_method("damage"):
			node.call("damage", player_damage)


func _is_near_active_coolant_source(player_pos: Vector3) -> bool:
	if get_tree() == null:
		return false

	var prox_sq := cryo_proximity_distance * cryo_proximity_distance

	# 1. Active unsealed CoolantLeaks
	for leak in get_tree().get_nodes_in_group("coolant_leak"):
		if is_instance_valid(leak) and leak is Spatial:
			var intensity: float = float(leak.call("get_leak_intensity")) if leak.has_method("get_leak_intensity") else 0.0
			if intensity > 0.01:
				if (leak as Spatial).global_transform.origin.distance_squared_to(player_pos) <= prox_sq:
					return true

	# 2. Active unsealed LeakPatchPoints
	for patch in get_tree().get_nodes_in_group("gloo_patchable"):
		if is_instance_valid(patch) and patch is Spatial:
			var is_patched: bool = bool(patch.call("is_patched")) if patch.has_method("is_patched") else false
			if not is_patched:
				var associated_leak = patch.get("_leak") if "_leak" in patch else null
				if is_instance_valid(associated_leak) and associated_leak.has_method("get_leak_intensity"):
					if float(associated_leak.call("get_leak_intensity")) > 0.01:
						if (patch as Spatial).global_transform.origin.distance_squared_to(player_pos) <= prox_sq:
							return true

	# 3. Active CryoVents
	for vent in get_tree().get_nodes_in_group("cryo_vent"):
		if is_instance_valid(vent) and vent is Spatial:
			var is_active: bool = bool(vent.get("is_active")) if "is_active" in vent else false
			if is_active:
				if (vent as Spatial).global_transform.origin.distance_squared_to(player_pos) <= prox_sq:
					return true

	return false


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"temperature": temperature,
		"pressure": pressure,
		"contamination": contamination,
		"is_freezing": _is_freezing,
		"is_lethal_cold": _is_lethal_cold,
		"is_absolute_cryo": _is_absolute_cryo,
		"is_fog_active": _is_fog_active,
		"is_hazard_active": _is_hazard_active,
		"is_overpressured": _is_overpressured
	}


func restore_snapshot(data: Dictionary) -> void:
	var old_temperature: float = temperature
	var old_pressure: float = pressure
	var old_contamination: float = contamination
	if data.has("temperature"):
		temperature = float(data["temperature"])
	if data.has("pressure"):
		pressure = float(data["pressure"])
	if data.has("contamination"):
		contamination = float(data["contamination"])

	if data.has("is_freezing"):
		_is_freezing = bool(data["is_freezing"])
	if data.has("is_lethal_cold"):
		_is_lethal_cold = bool(data["is_lethal_cold"])
	if data.has("is_absolute_cryo"):
		_is_absolute_cryo = bool(data["is_absolute_cryo"])
	if data.has("is_fog_active"):
		_is_fog_active = bool(data["is_fog_active"])
	if data.has("is_hazard_active"):
		_is_hazard_active = bool(data["is_hazard_active"])
	if data.has("is_overpressured"):
		_is_overpressured = bool(data["is_overpressured"])

	_evaluate_thresholds(false)
	# Snapshot restoration bypasses the setters to restore the replay state atomically.
	# Re-emit the value notifications afterward so terminal dials redraw their cached
	# Viewport texture with the restored Room3D values.
	if not is_equal_approx(old_temperature, temperature):
		emit_signal("temperature_changed", temperature)
	if not is_equal_approx(old_pressure, pressure):
		emit_signal("pressure_changed", pressure)
	if not is_equal_approx(old_contamination, contamination):
		emit_signal("contamination_changed", contamination)
