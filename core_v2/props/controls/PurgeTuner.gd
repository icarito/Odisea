extends HoldInteractableV2
class_name PurgeTuner

# PurgeTuner.gd — mando de sintonía de purga (FD-258).
#
# Reemplaza al uso forzado de una PipeValve como dial. Una válvula es binaria en todas las
# demás salas (cerrar corta la fuga, redirigir el flujo), así que usarla acá para "avanzar
# un valor de a pasos" le enseñaba al jugador dos gramáticas distintas para el mismo objeto.
#
# Acá el verbo es sostener: mientras se mantiene la interacción la aguja BARRE la escala, y
# se suelta cuando pasa por la zona verde. El acierto está en cuándo soltás, no en cuántas
# veces pulsaste.

# Vueltas de escala por segundo mientras se sostiene.
export(float) var sweep_speed: float = 0.42
export(NodePath) var dial_path: NodePath

onready var _dial: Node = get_node_or_null(dial_path)
onready var _knob: Spatial = get_node_or_null("Knob")


func _ready() -> void:
	._ready()
	interaction_text = "Sintonizar"
	# El barrido no termina nunca por sí solo: no hay progreso que "completar", se suelta.
	hold_duration = 0.0
	repeatable = false
	release_rate = 0.0


func step(dt: float) -> void:
	.step(dt)
	if not is_held() or _dial == null or not _dial.has_method("nudge"):
		return
	var value: float = _dial.value + sweep_speed * dt
	while value > 1.0:
		value -= 1.0
	_dial.nudge(value - _dial.value)
	if _knob:
		_knob.rotation.y = value * TAU
