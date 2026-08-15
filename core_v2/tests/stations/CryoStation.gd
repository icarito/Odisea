extends Spatial

# CryoStation.gd — cablea la lógica de la fuga de coolant con sus dos capas visuales.
#
# No tiene estado propio: todo sale de CoolantLeak.get_leak_intensity(), así que no
# necesita snapshot — el estado vive en CoolantLeak, que sí cumple el contrato de replay
# (AGENTS.md §5.3). Este nodo solo traduce esa intensidad a lo que se ve:
#   - la pluma del CryoVent (brillo y presencia)
#   - la niebla del FrostEmitter (el gas frío que ciega)

onready var _leak: Node = get_node_or_null("CoolantLeak")
onready var _vent: Node = get_node_or_null("Vent/CryoVent_C")
onready var _fog: Node = get_node_or_null("Fog")
onready var _pipes: Node = get_node_or_null("Pipes")

var _fog_active: bool = false

# Presión del circuito: a régimen la tubería corre pareja; con la fuga abierta pierde
# caudal y el flujo se apaga. Es la misma lectura que la niebla, pero desde el otro lado.
const PIPE_FLOW_HEALTHY := 1.0
const PIPE_FLOW_LEAKING := 0.3


func _ready() -> void:
	_apply(0.0)


func _physics_process(_delta: float) -> void:
	if _leak:
		_apply(_leak.get_leak_intensity())


func _apply(intensity: float) -> void:
	var active: bool = intensity > 0.01

	if _vent:
		_vent.set_active(active)
		if active:
			_vent.set_intensity(intensity)

	# FrostEmitter reconstruye sus visuales en cada set_active: solo en los cambios.
	if _fog and active != _fog_active:
		_fog_active = active
		_fog.set_active(active)

	if _pipes and _pipes.has_method("set_flow_intensity"):
		_pipes.set_flow_intensity(lerp(PIPE_FLOW_HEALTHY, PIPE_FLOW_LEAKING, intensity))
