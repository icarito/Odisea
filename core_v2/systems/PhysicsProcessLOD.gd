extends Reference
class_name PhysicsProcessLOD

# Apaga _physics_process de un nodo cuando el jugador esta lejos, con el mismo patron
# que AirlockLOD.gd (distancia + histeresis + chequeo cada N frames) pero aplicado al
# proceso en vez de a la visibilidad — para componentes que animan/simulan algo que
# de lejos ni se nota (GasParticleManager, PipeCoolantRun, FD-270).
#
# Solo toca _physics_process del nodo, nunca colision: mismo motivo que AirlockLOD,
# tocar formas de colision re-registra en el espacio de fisica y mete drift en replays
# deterministas. Esto es puramente "no simules lo que nadie va a ver moverse".
#
# La posicion de referencia se pasa como Vector3 de MUNDO ya resuelto, no como un
# Spatial cuya global_transform se lea despues: un mesh horneado (bake_pipe_network.gd,
# ver PipeCoolantRun) fusiona varios tramos en un solo MeshInstance cuya transform de
# NODO queda en la identidad — las coordenadas reales viven en los vertices del mesh,
# no en el arbol de transforms. Pedir el Vector3 ya calculado (ej. AABB del mesh) en
# _init() evita que el LOD compare distancia contra un origen que nunca se movio.
#
# Uso: instanciar en _ready() con la posicion de mundo ya resuelta, llamar
# should_process() desde _physics_process del dueño ANTES de decidir si hacer trabajo.
# El propio helper no llama set_physics_process() por el caller porque el owner puede
# tener otras razones para seguir/parar (ej. rampa de velocidad a cero en PipeCoolantRun).

var world_position: Vector3
var distance: float
var hysteresis: float
var frames_between_checks: int

var _active := true
var _frames := 0
var _tree: SceneTree = null
var _reference: Spatial = null


func _init(p_world_position: Vector3, p_tree: SceneTree, p_distance: float = 12.0, p_hysteresis: float = 4.0, p_frames_between_checks: int = 10) -> void:
	world_position = p_world_position
	_tree = p_tree
	distance = p_distance
	hysteresis = p_hysteresis
	frames_between_checks = p_frames_between_checks


# Devuelve true si el nodo debe seguir simulando este frame. Se puede llamar todos los
# frames: el chequeo real de distancia solo corre cada frames_between_checks.
func should_process() -> bool:
	_frames += 1
	if _frames < frames_between_checks:
		return _active
	_frames = 0
	var origin = _point_of_view()
	if origin == null:
		return _active
	var d: float = origin.distance_to(world_position)
	_active = d <= (distance if not _active else distance + hysteresis)
	return _active


# Para que un presupuesto global (AdaptiveVisualBudget) pueda ensanchar o acortar el
# radio segun cuanto aguante el dispositivo, sin crear una instancia nueva de LOD.
func set_distance(new_distance: float) -> void:
	distance = new_distance


func _point_of_view():
	if _tree == null:
		return null
	var vp: Viewport = _tree.root
	if vp != null:
		var cam := vp.get_camera()
		if cam != null:
			return cam.global_transform.origin
	if not is_instance_valid(_reference):
		var players = _tree.get_nodes_in_group("player")
		_reference = players[0] if not players.empty() and players[0] is Spatial else null
	if is_instance_valid(_reference):
		return _reference.global_transform.origin
	return null
