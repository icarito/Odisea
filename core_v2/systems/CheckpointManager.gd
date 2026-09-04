extends Node

# CheckpointManager.gd
# Autoload system to track registered and active checkpoints.

var registered_checkpoints := []
var active_checkpoint_pos: Vector3 = Vector3.ZERO
var active_checkpoint_yaw: float = 0.0
var active_checkpoint_pitch: float = 0.0
var active_replay_snapshot: Dictionary = {}

var default_respawn_position: Vector3 = Vector3.ZERO
var default_respawn_yaw: float = 0.0
var default_respawn_pitch: float = 0.0
var default_replay_snapshot: Dictionary = {}
var _default_snapshot_scene_id: int = 0
var _default_snapshot_ice_path: String = ""

# Cache del perfilador: buscar el autoload por path en cada tick cuesta, y ese costo
# alcanza para que un replay pierda pasos de fisica y derive. Se resuelve una vez.
var _pm_perfil = null
var _pm_perfil_buscado := false

func _ready() -> void:
	# El autoload entra al árbol antes que la escena del nivel. El snapshot inicial se
	# toma en el primer tick físico de ESA escena, cuando ya terminaron todos los _ready()
	# y Room3D/CoolantTank/IceLevel ya pertenecen a replay_sync.
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	# Envoltorio de perfilado (ver PerformanceMonitor.perfil_corrida_iniciar): el cuerpo
	# puede tener varios return, asi que se mide desde afuera y no por dentro.
	if not _pm_perfil_buscado:
		_pm_perfil_buscado = true
		_pm_perfil = get_node_or_null("/root/PerformanceMonitor")
	if _pm_perfil != null and _pm_perfil._perfil_corrida_on:
		_pm_perfil.perfil_inicio("CheckpointManager")
		_paso_fisica(_delta)
		_pm_perfil.perfil_fin("CheckpointManager")
		return
	_paso_fisica(_delta)

func _paso_fisica(_delta: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var scene_id: int = scene.get_instance_id()
	# Dome_Intro puede montarse bajo el bootstrap sin reemplazar current_scene. En ese
	# caso el id del root no cambia, pero sí aparece un IceLevel nuevo; si conservamos
	# el snapshot anterior/vacío, el respawn deja tanques drenados y el hielo salta sobre
	# el piloto en el primer tick. La ruta del IceLevel identifica el mundo criogénico
	# real que se debe capturar.
	var ice_path: String = _get_active_ice_path()
	if scene_id == _default_snapshot_scene_id and ice_path == _default_snapshot_ice_path:
		return
	# El bootstrap puede conservar el mismo root mientras reemplaza Dome_Intro. En ese
	# caso una ruta de hielo distinta también es otro mundo: conservar un checkpoint
	# anterior deja un snapshot vacío que gana al spawn inicial durante el respawn.
	if scene_id != _default_snapshot_scene_id or ice_path != _default_snapshot_ice_path:
		active_checkpoint_pos = Vector3.ZERO
		active_checkpoint_yaw = 0.0
		active_checkpoint_pitch = 0.0
		active_replay_snapshot.clear()
	_default_snapshot_scene_id = scene_id
	_default_snapshot_ice_path = ice_path
	_cache_default_spawn()


func _get_active_ice_path() -> String:
	for level in get_tree().get_nodes_in_group("ice_level"):
		if is_instance_valid(level) and level.is_inside_tree():
			return String(level.get_path())
	return ""

func _cache_default_spawn() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		default_respawn_position = p.global_transform.origin
		default_respawn_yaw = p.yaw
		default_respawn_pitch = p.pitch
	default_replay_snapshot = capture_replay_sync_state()

func register_checkpoint(console: Node) -> void:
	if not registered_checkpoints.has(console):
		registered_checkpoints.append(console)

func set_active_checkpoint(pos: Vector3, yaw: float, pitch: float) -> void:
	active_checkpoint_pos = pos
	active_checkpoint_yaw = yaw
	active_checkpoint_pitch = pitch
	active_replay_snapshot = capture_replay_sync_state()

	# Deactivate other checkpoints to ensure visual consistency (only one is active)
	for cp in registered_checkpoints:
		if is_instance_valid(cp):
			var cp_pos = cp.global_transform.origin
			if cp_pos.distance_squared_to(pos) > 0.01:
				if cp.has_method("deactivate"):
					cp.deactivate()

func get_respawn_transform() -> Dictionary:
	# Una posición sola no es un checkpoint válido: sin su replay_sync asociado dejaría
	# Room3D, tanques e IceLevel en el estado de la muerte. Volver al snapshot inicial.
	if active_checkpoint_pos != Vector3.ZERO and not active_replay_snapshot.empty():
		restore_replay_sync_state(active_replay_snapshot)
		return {
			"position": active_checkpoint_pos,
			"yaw": active_checkpoint_yaw,
			"pitch": active_checkpoint_pitch
		}

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		restore_replay_sync_state(default_replay_snapshot)
		var p = players[0]
		return {
			"position": p.initial_transform.origin,
			"yaw": p.yaw,
			"pitch": p.pitch
		}

	return {
		"position": default_respawn_position,
		"yaw": default_respawn_yaw,
		"pitch": default_respawn_pitch
	}

# Support auto-checkpoints triggered by room triggers or areas
func trigger_auto_checkpoint(pos: Vector3, yaw: float = 0.0, pitch: float = 0.0) -> void:
	set_active_checkpoint(pos, yaw, pitch)

func capture_replay_sync_state() -> Dictionary:
	var snapshot: Dictionary = {}
	for node in get_tree().get_nodes_in_group("replay_sync"):
		if is_instance_valid(node) and node.has_method("get_snapshot"):
			snapshot[String(node.get_path())] = node.get_snapshot()
	return snapshot

func restore_replay_sync_state(snapshot: Dictionary) -> void:
	for path in snapshot.keys():
		var node: Node = get_node_or_null(NodePath(path))
		if is_instance_valid(node) and node.has_method("restore_snapshot"):
			node.restore_snapshot(snapshot[path])

