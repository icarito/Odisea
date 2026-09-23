extends Spatial
class_name StreamedSceneChunkV2

# FD-314 - Chunk de colision con streaming por proximidad.
#
# A diferencia de DeferredSceneChunk (que carga una sola vez tras el gate de
# arranque), este loader:
#   1. espera el gate de arranque (mismo contrato que FD-032) para no pagar nada
#      en el frame jugable;
#   2. instancia `chunk_scene` recien cuando el jugador entra en `trigger_radius`
#      del ancla `trigger_center` (espacio local del nodo);
#   3. opcionalmente libera la instancia al alejarse (`free_on_exit`), devolviendo
#      shapes al mundo fisico en low-end.
#
# Solo contiene colision estatica de scaffold: nunca cuerpos de `replay_sync`
# (ver FD-314 §6). El visual del scaffold vive siempre en el shell, asi que un
# chunk jamas produce un frame con colision sin malla debajo.

export(PackedScene) var chunk_scene
# Colision SIN streaming: se carga entera al abrir el gate y no se libera nunca.
#
# El streaming por distancia de colision estatica resulto un mal negocio. El
# trigger es una esfera alrededor del CENTROIDE del chunk, asi que con geometria
# que se extiende mas alla del radio quedan coronas donde se pisa la malla y el
# chunk todavia no cargo — se atraviesa el piso estando encima. Calibrar el radio
# por chunk tapa el sintoma pero no la clase de bug.
#
# Y no hacia falta: Box3D guarda los estaticos en su PROPIO b3DynamicTree, saltea
# los pares estatico-estatico y resuelve las consultas en k*log(n), asi que unos
# cientos de shapes estaticas no le pesan. Medido en el Anbernic con A/B/A sobre
# el mismo replay (ms_physics mediana / p90):
#     streaming  18.63 / 29.76      todo cargado  18.48 / 26.16      streaming  19.73 / 33.99
# Cargar todo no cuesta mas, y el p90 hasta mejora: desaparecen los picos de
# instanciar y liberar chunks mientras se juega.
export(bool) var stream_by_distance := true
export(Vector3) var trigger_center := Vector3.ZERO
export(float) var trigger_radius := 15.0
export(float) var release_margin := 6.0
export(bool) var free_on_exit := true
export(bool) var wait_for_startup_gate := true
export(int, 0, 1200) var startup_wait_max_frames := 720
export(String) var startup_trace_label := ""
export(NodePath) var player_path := NodePath("")

var _loaded := false
var _load_pending := false
var _instance: Node = null
var _player: Spatial = null

func _ready() -> void:
	if Engine.editor_hint:
		return
	set_physics_process(false)
	if chunk_scene == null:
		return
	_mark_trace("streamed_chunk_ready")
	call_deferred("_arm_when_ready")

func _arm_when_ready() -> void:
	if wait_for_startup_gate:
		var session = get_node_or_null("/root/SessionManager")
		if session and session.has_method("is_startup_gate_open") and not bool(session.is_startup_gate_open()):
			_mark_trace("streamed_chunk_waiting_for_gate")
			if session.has_method("wait_until_startup_gate_open"):
				var wait_state = session.wait_until_startup_gate_open(startup_wait_max_frames)
				if wait_state is GDScriptFunctionState:
					yield(wait_state, "completed")
	if not is_instance_valid(self):
		return
	_mark_trace("streamed_chunk_armed")
	if not stream_by_distance:
		# Nada que vigilar: se carga una vez y el _physics_process no se enciende,
		# asi que no se paga una distancia por tick y por chunk para siempre.
		request_load()
		return
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if chunk_scene == null:
		return
	var player := _get_player()
	if player == null:
		return
	var distance := player.global_transform.origin.distance_to(to_global(trigger_center))
	if distance <= trigger_radius:
		if not _loaded and not _load_pending:
			request_load()
	elif _loaded and free_on_exit and distance > trigger_radius + release_margin:
		release()

func request_load() -> void:
	if _loaded or _load_pending or chunk_scene == null:
		return
	_load_pending = true
	call_deferred("_load_chunk")

func release() -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.queue_free()
	_instance = null
	_loaded = false

func is_chunk_loaded() -> bool:
	return _loaded

func _load_chunk() -> void:
	_load_pending = false
	if _loaded or not is_instance_valid(self):
		return
	var instance = chunk_scene.instance()
	if instance == null:
		return
	_instance = instance
	add_child(instance)
	_loaded = true
	_mark_trace("streamed_chunk_loaded")

func _get_player() -> Spatial:
	if _player != null and is_instance_valid(_player):
		return _player
	if player_path != NodePath(""):
		_player = get_node_or_null(player_path) as Spatial
	else:
		var players := get_tree().get_nodes_in_group("player")
		if not players.empty():
			_player = players[0] as Spatial
	return _player

func _mark_trace(event_name: String) -> void:
	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace == null or not startup_trace.has_method("mark"):
		return
	var label := startup_trace_label if startup_trace_label != "" else name
	startup_trace.mark(event_name, {
		"label": label,
		"chunk_scene": chunk_scene.resource_path if chunk_scene != null else "",
		"node_path": String(get_path())
	})
