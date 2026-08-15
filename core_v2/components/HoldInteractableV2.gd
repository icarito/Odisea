extends InteractableBaseV2
class_name HoldInteractableV2

# HoldInteractableV2.gd — interactuable de mantener presionado.
#
# A diferencia de una palanca, que conmuta de un golpe, esto acumula mientras el jugador
# sostiene la tecla de interacción y se descarga solo al soltarla. Sirve para bombear,
# tensar un resorte, cargar un mecanismo: cualquier cosa donde el esfuerzo tenga duración
# y el jugador vea cuánto lleva.
#
# El controlador solo avisa si está siendo sostenido (set_held); el tiempo se acumula acá,
# en _physics_process, que es donde el contrato de replay lo puede reproducir
# (AGENTS.md §5.3). Nada de _process ni de relojes del sistema.

# Segundos de sostener para llegar al 100%.
export(float) var hold_duration: float = 1.6
# Velocidad a la que cae el progreso al soltar, como fracción por segundo. En 0 el
# progreso se queda donde estaba: un mecanismo trinquete en vez de un resorte.
export(float) var release_rate: float = 0.8
# Si es true, al completar vuelve a cero y puede volver a cargarse.
export(bool) var repeatable: bool = true

signal hold_started()
signal hold_progress_changed(progress)
signal hold_completed()
signal hold_released(progress)

var _held: bool = false
var _hold_progress: float = 0.0
var _was_held: bool = false


func set_held(value: bool) -> void:
	if value == _held:
		return
	_held = value
	if _held:
		emit_signal("hold_started")
		# Sale del reposo: sin esto el culling de FD-224 lo deja congelado.
		set_physics_process(true)
	else:
		emit_signal("hold_released", _hold_progress)


func is_held() -> bool:
	return _held


func get_hold_progress() -> float:
	return _hold_progress


func reset_hold() -> void:
	_hold_progress = 0.0
	emit_signal("hold_progress_changed", _hold_progress)


func _wants_continuous_step() -> bool:
	# Mientras haya algo que acumular o que descargar, este prop necesita seguir corriendo
	# aunque su animación de apertura ya haya terminado.
	return _held or _hold_progress > 0.0


func step(dt: float) -> void:
	.step(dt)
	var previous: float = _hold_progress
	if _held:
		if hold_duration > 0.0:
			_hold_progress = min(_hold_progress + dt / hold_duration, 1.0)
		else:
			_hold_progress = 1.0
		if _hold_progress >= 1.0 and previous < 1.0:
			emit_signal("hold_completed")
			if repeatable:
				_hold_progress = 0.0
	else:
		_hold_progress = max(_hold_progress - release_rate * dt, 0.0)

	if abs(_hold_progress - previous) > 0.0001:
		emit_signal("hold_progress_changed", _hold_progress)
		_update_hold_visuals(_hold_progress)


func _update_hold_visuals(_progress: float) -> void:
	"""Gancho para las subclases: mover el pistón, comprimir el resorte, lo que sea."""
	pass


func get_snapshot() -> Dictionary:
	var snap: Dictionary = .get_snapshot()
	snap["hold_progress"] = _hold_progress
	snap["held"] = _held
	return snap


func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	if data.has("hold_progress"):
		_hold_progress = float(data["hold_progress"])
	if data.has("held"):
		_held = bool(data["held"])
	_update_hold_visuals(_hold_progress)
