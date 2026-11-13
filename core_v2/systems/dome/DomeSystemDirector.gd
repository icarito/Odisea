extends Node

# DomeSystemDirector.gd — máquina de beats del domo criogénico (FD-289 §7.1, T2).
#
# Se registra como autoload `DomeSystemDirector` en project.godot: el singleton ya expone el
# nombre global, así que este script NO declara class_name (declararlo es un error de parseo
# "class conflicts with the AutoLoad singleton"). Se accede al tipo por preload/load.
#
# Autoload. Es el "director" del domo: lee un DomeEnvConfig (T1) y dispara en orden los
# eventos del timeline (beat 1→5), mantiene el contador de redes HEALTHY leyendo un
# DomeNetworkStatus (T1) y, al llegar a 4/4, anuncia que el blast door puede abrir y el
# hangar está listo. NO simula las máquinas ni las redes: el cableado real vive en las
# escenas del domo (T6/T7) y en BlastDoorController (T3), que escuchan las señales de acá.
#
# Determinismo (AGENTS.md §5.3): la lógica es por eventos (no hay randf/randomize ni
# Engine.get_frames_drawn) y get_snapshot()/restore_snapshot() reproducen el estado exacto
# sin re-emitir señales al restaurar. Pertenece a 'replay_sync'.
#
# Los ids de red de DomeEnvConfig_intro.tres (criocoolant/energia/aire/plasma) no coinciden
# con los nombres de evento del timeline (coolant_healthy/energy_healthy/air_healthy/
# plasma_healthy). network_event_aliases traduce uno al otro cuando el director auto-avanza
# un beat a partir de DomeNetworkStatus.network_healthy. También se puede ignorar la
# traducción y llamar notify_event() explícitamente desde la máquina que se reparó.

# Configuración del domo (DomeEnvConfig_v2 .tres). Si es null, se intenta cargar desde
# env_config_path en _ready(). Documentado en el Inspector.
export(Resource) var env_config: Resource = null

# Ruta de respaldo al DomeEnvConfig .tres cuando env_config no está seteado en el editor.
# Documentado en el Inspector.
export(String) var env_config_path: String = "res://core_v2/systems/dome/DomeEnvConfig_intro.tres"

# Ruta al nodo DomeNetworkStatus dentro de la escena del domo. Como este director es un
# autoload, la escena puede resolverlo por NodePath (wiring de T6/T7) o llamar a
# register_network_status(). Documentado en el Inspector.
export(NodePath) var network_status_path: NodePath = NodePath()

# Puente red→evento del timeline para el auto-avance por network_healthy. Cada entrada mapea
# un id de DomeNetworkStatus ("aire") al evento del timeline ("air_healthy"). Documentado en
# el Inspector.
export(Dictionary) var network_event_aliases: Dictionary = {
	"criocoolant": "coolant_healthy",
	"energia": "energy_healthy",
	"plasma": "plasma_healthy",
	"aire": "air_healthy",
}

# Si es true, la señal airlock_exit dispara SceneManager.goto_scene(target) cuando hay un
# destino válido. Ponerlo en false en tests o escenas que manejan la transición por su
# cuenta. Documentado en el Inspector.
export(bool) var auto_load_airlock_scene: bool = true

# Se emite por cada entrada del timeline que se dispara (en orden de beat). El consumidor
# (T6/T7) traduce `action` al prop/máquina que corresponde.
signal timeline_event(event, action, beat)
# 4/4 redes HEALTHY: el blast door puede abrirse (lo escucha BlastDoorController, T3).
signal blast_door_open()
# 4/4 redes HEALTHY: el hangar/sótano está listo (transición de descenso, T4).
signal hangar_ready()
# Fin del vertical slice del domo: pide la transición de escena al hangar/exterior.
signal airlock_exit(target)

var _config: Resource = null
var _network_status: Node = null
var _expected_beat: int = 1
var _fired_beats: Dictionary = {}
var _pending_events: Dictionary = {}
var _healthy_count: int = 0
var _expected_networks: int = 4
var _blast_door_open: bool = false
var _hangar_ready: bool = false


func _ready() -> void:
	add_to_group("replay_sync")
	# Estado puro dirigido por eventos/llamadas: sin ticks por cuadro (FD-224 no tiene nada
	# que apagar acá, pero dejarlo explícito evita que SessionManager espere stepping).
	set_process(false)
	set_physics_process(false)

	_apply_config(_resolve_config())
	_resolve_network_status()

	# La señal es la vía canónica (FD-289 §7.1). El propio director la conecta a SceneManager
	# para que emitir `airlock_exit` sea suficiente; auto_load_airlock_scene permite desactivar
	# la carga forzada cuando la escena maneja la transición por su cuenta.
	if not is_connected("airlock_exit", self, "_on_airlock_exit"):
		connect("airlock_exit", self, "_on_airlock_exit")


# --- CONFIGURACIÓN ---

# Entrega el DomeEnvConfigV2 a usar. Idempotente y usable antes de entrar al árbol (tests).
func set_config(config: Resource) -> void:
	_apply_config(config)


func get_config() -> Resource:
	return _config


# Registra el DomeNetworkStatus del domo y se conecta a sus señales. Idempotente.
func register_network_status(status: Node) -> void:
	if status == null:
		return
	if status == _network_status:
		return
	_disconnect_network_status()
	_network_status = status
	_healthy_count = _read_healthy_count()
	if not _network_status.is_connected("network_healthy", self, "_on_network_healthy"):
		_network_status.connect("network_healthy", self, "_on_network_healthy")
	if not _network_status.is_connected("all_healthy", self, "_on_all_healthy"):
		_network_status.connect("all_healthy", self, "_on_all_healthy")


func get_network_status() -> Node:
	return _network_status


# --- ENTRADAS DE GAMEPLAY (llamadas por T6/T7) ---

# Beat 1: el jugador acciona el interruptor principal y el intento revela la fuga de coolant.
func request_first_power_attempt() -> void:
	notify_event("on_first_power_attempt")


# Dispara el evento del timeline `event` si es el próximo beat esperado. Devuelve true si se
# disparó ahora; false si no existe, ya se disparó, o quedó en espera por orden.
# Out-of-order: un evento de un beat futuro se guarda y se re-evalúa cuando la secuencia
# llega a él, así una red que sana antes de tiempo no saltea beats.
func notify_event(event: String) -> bool:
	var entry: Dictionary = _find_timeline_entry(event)
	if entry.empty():
		return false
	var beat: int = int(entry.get("beat", 0))
	if beat <= 0:
		return false
	if _fired_beats.has(beat):
		return false
	if beat == _expected_beat:
		_fire_entry(entry)
		_advance_expected()
		return true
	if beat > _expected_beat:
		_pending_events[event] = entry
	return false


# Pide la salida por la esclusa. Emite airlock_exit(target); si target es vacío usa el
# exterior_airlock_scene de la config. No fuerza carga alguna por sí solo: la conexión
# interna (auto_load_airlock_scene) decide si llama a SceneManager.
func request_airlock_exit(target: String = "") -> void:
	var path: String = String(target).strip_edges()
	if path == "":
		path = get_airlock_scene()
	if path == "":
		return
	emit_signal("airlock_exit", path)


# --- LECTURA DE ESTADO ---

func get_current_beat() -> int:
	return _expected_beat - 1


func get_expected_beat() -> int:
	return _expected_beat


func is_event_fired(event: String) -> bool:
	var entry: Dictionary = _find_timeline_entry(event)
	if entry.empty():
		return false
	return _fired_beats.has(int(entry.get("beat", 0)))


func is_beat_fired(beat: int) -> bool:
	return _fired_beats.has(beat)


func get_fired_beats() -> Array:
	var beats: Array = _fired_beats.keys()
	beats.sort()
	return beats


func get_healthy_count() -> int:
	return _healthy_count


func get_expected_networks() -> int:
	return _expected_networks


func is_all_healthy() -> bool:
	return _expected_networks > 0 and _healthy_count >= _expected_networks


func is_blast_door_open() -> bool:
	return _blast_door_open


func is_hangar_ready() -> bool:
	return _hangar_ready


# --- ACCESO A LA CONFIG ---

func get_hangar_scene() -> String:
	if _config == null:
		return ""
	return String(_config.hangar_scene)


func get_hangar_spawn_id() -> String:
	if _config == null:
		return ""
	return String(_config.hangar_spawn_id)


func get_airlock_scene() -> String:
	if _config == null:
		return ""
	return String(_config.exterior_airlock_scene)


# --- SNAPSHOT (Core V2 §5.3) ---

func get_snapshot() -> Dictionary:
	var pending: Array = _pending_events.keys()
	pending.sort()
	return {
		"v": 1,
		"expected_beat": _expected_beat,
		"fired_beats": get_fired_beats(),
		"pending_events": pending,
		"healthy_count": _healthy_count,
		"expected_networks": _expected_networks,
		"blast_door_open": _blast_door_open,
		"hangar_ready": _hangar_ready,
	}


# Restaura el estado sin emitir señales: un replay no debe re-disparar el timeline ni la
# apertura del blast door. El DomeNetworkStatus se re-lee para mantener el contador coherente.
func restore_snapshot(data: Dictionary) -> void:
	if data.empty():
		return
	_fired_beats.clear()
	var fired = data.get("fired_beats", [])
	for beat in fired:
		_fired_beats[int(beat)] = true
	_pending_events.clear()
	var pending = data.get("pending_events", [])
	for event in pending:
		var entry: Dictionary = _find_timeline_entry(String(event))
		if not entry.empty():
			_pending_events[String(event)] = entry
	_expected_beat = int(data.get("expected_beat", _first_beat()))
	_expected_networks = int(data.get("expected_networks", _expected_networks))
	_healthy_count = int(data.get("healthy_count", _read_healthy_count()))
	_blast_door_open = bool(data.get("blast_door_open", false))
	_hangar_ready = bool(data.get("hangar_ready", false))


# --- INTERNOS ---

func _resolve_config() -> Resource:
	if env_config != null:
		return env_config
	var path: String = String(env_config_path).strip_edges()
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _resolve_network_status() -> void:
	if network_status_path == NodePath():
		return
	if not is_inside_tree():
		return
	var resolved: Node = get_node_or_null(network_status_path)
	if resolved != null:
		register_network_status(resolved)


func _apply_config(config: Resource) -> void:
	# Aceptamos cualquier Resource que cumpla el contrato de DomeEnvConfigV2 (T1). No se usa
	# el nombre global DomeEnvConfigV2 como tipo: no está en el registro de clases de
	# project.godot, así que el parser lo rechaza. Duck typing por métodos/propiedades.
	_config = config if config != null and config.has_method("network_count") else null
	_expected_beat = _first_beat()
	_expected_networks = _config.network_count() if _config != null else 4
	if _expected_networks <= 0:
		_expected_networks = 4


func _first_beat() -> int:
	if _config == null:
		return 1
	var lowest: int = 0
	for entry in _config.timeline:
		if not entry is Dictionary:
			continue
		var beat: int = int(entry.get("beat", 0))
		if beat <= 0:
			continue
		if lowest == 0 or beat < lowest:
			lowest = beat
	return lowest if lowest > 0 else 1


func _find_timeline_entry(event: String) -> Dictionary:
	if _config == null or event == "":
		return {}
	for entry in _config.timeline:
		if entry is Dictionary and String(entry.get("event", "")) == event:
			return entry
	return {}


func _fire_entry(entry: Dictionary) -> void:
	var beat: int = int(entry.get("beat", 0))
	var event: String = String(entry.get("event", ""))
	var action: String = String(entry.get("action", ""))
	_fired_beats[beat] = true
	emit_signal("timeline_event", event, action, beat)


func _advance_expected() -> void:
	_expected_beat += 1
	_flush_pending()


func _flush_pending() -> void:
	var progressed: bool = true
	while progressed:
		progressed = false
		var events: Array = _pending_events.keys()
		events.sort()
		for event in events:
			var entry: Dictionary = _pending_events[event]
			if int(entry.get("beat", 0)) == _expected_beat:
				_pending_events.erase(event)
				_fire_entry(entry)
				_expected_beat += 1
				progressed = true
				break


func _on_network_healthy(network_id: String) -> void:
	_healthy_count = _read_healthy_count()
	var alias: String = String(network_event_aliases.get(network_id, ""))
	if alias == "":
		alias = network_id + "_healthy"
	notify_event(alias)


func _on_all_healthy() -> void:
	_healthy_count = _expected_networks
	if not _blast_door_open:
		_blast_door_open = true
		emit_signal("blast_door_open")
	if not _hangar_ready:
		_hangar_ready = true
		emit_signal("hangar_ready")


func _on_airlock_exit(target: String) -> void:
	if not auto_load_airlock_scene:
		return
	if String(target).strip_edges() == "":
		return
	if Engine.is_editor_hint():
		return
	if not is_inside_tree():
		return
	SceneManager.goto_scene(target)


func _read_healthy_count() -> int:
	if _network_status != null and _network_status.has_method("healthy_count"):
		return int(_network_status.healthy_count())
	return _healthy_count


func _disconnect_network_status() -> void:
	if _network_status == null:
		return
	if _network_status.is_connected("network_healthy", self, "_on_network_healthy"):
		_network_status.disconnect("network_healthy", self, "_on_network_healthy")
	if _network_status.is_connected("all_healthy", self, "_on_all_healthy"):
		_network_status.disconnect("all_healthy", self, "_on_all_healthy")
	_network_status = null
