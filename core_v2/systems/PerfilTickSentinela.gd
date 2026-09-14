extends Node

# Sentinela para acotar el tramo de scripts dentro del tick de fisica.
#
# process_priority ordena tambien los _physics_process, asi que con dos nodos en los
# extremos (uno con prioridad minima y otro con maxima) queda encerrado todo lo que corre
# en GDScript durante el tick. Lo que sobra al restar ese tramo de TIME_PHYSICS_PROCESS es
# el paso del servidor de fisica, que no se puede medir de otra forma desde el juego.
#
# Existe porque en un telefono de gama media el tick cuesta ~15 ms con CERO cuerpos
# activos, y hacia falta saber cuanto de eso es el broadphase del servidor y cuanto son
# nuestros scripts, antes de seguir optimizando a ciegas.
#
# PerformanceMonitor crea los dos; no se instancia a mano.

export(bool) var es_fin := false
# false = acota _physics_process ("· scripts del tick"); true = acota _process
# ("· scripts del frame", lado idle). Los dos lados comparten mecanismo.
export(bool) var es_idle := false

var _monitor: Node = null

func _ready() -> void:
	_monitor = get_parent()
	var prioridad := 10000 if es_fin else -10000
	process_priority = prioridad
	if es_idle:
		# process_priority ordena los _process igual que los _physics_process.
		set_physics_process(false)
	else:
		set_process(false)

func _physics_process(_delta: float) -> void:
	if _monitor == null or not _monitor.perfil_corrida_activo():
		return
	if es_fin:
		_monitor.perfil_fin("· scripts del tick")
	else:
		_monitor.perfil_inicio("· scripts del tick")

func _process(_delta: float) -> void:
	if _monitor == null or not _monitor.perfil_corrida_activo():
		return
	if es_fin:
		_monitor.perfil_fin("· scripts del frame")
	else:
		_monitor.perfil_inicio("· scripts del frame")
