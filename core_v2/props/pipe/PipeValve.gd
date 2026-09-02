extends InteractableBaseV2
class_name PipeValve
tool

# PipeValve.gd - Rotating valve that emits state changes.
# Extends InteractableBaseV2 for deterministic animation.

# --- EXPORTED TUNING ---
export(float) var valve_speed: float = 2.0 setget set_valve_speed
# Note: start_open is handled by InteractableBaseV2's starts_active

# --- SIGNALS ---
signal valve_state_changed(is_open)

# --- INTERNAL STATE ---
var _wheel: Spatial
var _indicator: GeometryInstance
var _initialized := false

const COLOR_CLOSED := Color( 0.95, 0.15, 0.1 )
const COLOR_OPEN := Color( 0.15, 0.95, 0.35 )

func set_valve_speed(v: float) -> void:
	valve_speed = v
	if valve_speed > 0:
		anim_duration = 1.0 / valve_speed
	else:
		anim_duration = 1.0

	if Engine.editor_hint:
		_update_speed()

func _update_speed() -> void:
	if anim_duration > 0:
		anim_speed = 1.0 / anim_duration
	else:
		anim_speed = 1.0

func _ready():
	# Se declara aquí también, aunque InteractableBaseV2 lo herede: una válvula nunca
	# puede perder sincronización de replay si cambia su clase base en el futuro. Los
	# checkpoints usan este mismo grupo; no existe una ruta paralela para válvulas.
	add_to_group("replay_sync")
	_wheel = get_node_or_null("Wheel")
	_indicator = get_node_or_null("StatusIndicator/StatusLight")
	if _indicator == null:
		_indicator = get_node_or_null("IndicatorLight")
	_initialized = true

	# Sync speed
	set_valve_speed(valve_speed)

	# Call parent ready
	._ready()

func _update_visuals() -> void:
	"""Interpolate wheel rotation based on animation progress."""
	if not _initialized or not _wheel:
		_wheel = get_node_or_null("Wheel")
		if not _wheel: return

	if _indicator == null:
		_indicator = get_node_or_null("StatusIndicator/StatusLight")
		if _indicator == null:
			_indicator = get_node_or_null("IndicatorLight")

	# Rota 180 grados en eje Z
	var eased = _ease_in_out(anim_progress)
	var angle = lerp(0.0, PI, eased)

	_wheel.rotation.z = angle

	if _indicator:
		var mat: SpatialMaterial = null
		if _indicator is CSGPrimitive:
			mat = _indicator.material as SpatialMaterial
			if mat:
				mat = mat.duplicate()
				_indicator.material = mat
		elif _indicator is MeshInstance:
			mat = _indicator.get_surface_material(0) as SpatialMaterial
			if mat:
				mat = mat.duplicate()
				_indicator.set_surface_material(0, mat)

		if mat:
			var color: Color = COLOR_CLOSED.linear_interpolate(COLOR_OPEN, eased)
			mat.albedo_color = color
			mat.emission = color
			mat.emission_enabled = true
			mat.emission_energy = 1.0

func _on_animation_completed() -> void:
	._on_animation_completed()
	emit_signal("valve_state_changed", is_active)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	var snap = .get_snapshot()
	snap["valve_speed"] = valve_speed
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("valve_speed"):
		valve_speed = data["valve_speed"]
	.restore_snapshot(data)
