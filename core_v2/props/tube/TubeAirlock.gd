extends Area

# TubeAirlock.gd - Automatic airlock for pedestrian tubes
# Detects player and triggers scene transition to another dome/spawn point.

export(String) var target_dome := ""
export(String) var target_spawn := ""
export(bool) var auto_open := true

# Evita el doble disparo: el target_dome suele ser la MISMA escena (otro spawn point), asi
# que tras la transicion el jugador puede reaparecer superpuesto con un airlock nuevo. Sin
# este guard, SceneManager.goto_scene() encola una segunda transicion ("Transition already
# in progress. Queued") que se ejecuta despues y devuelve al jugador cerca del punto de
# entrada — se vio como drift enorme y determinista en el replay (test_tube_airlock, dist=13.09).
var _has_triggered := false

# Frames de gracia contados desde que SceneManager termino de cargar ESTA instancia de
# escena (no desde _ready() de este nodo: la carga INICIAL de una escena de juego/test no
# pasa por goto_scene, asi que scene_ready no se emite ahi y un airlock usado desde
# el arranque dispara normal). El airlock de DESTINO de una transicion puede quedar
# geometricamente cerca del punto de spawn: en zero-g, sin friccion, el jugador conserva
# velocidad residual y puede cruzar el area en los primeros frames tras aparecer — eso
# disparaba una transicion de vuelta de inmediato (rebote infinito, ver dist=13.09 arriba).
const _POST_TRANSITION_GRACE_FRAMES := 20
var _scene_ready_frame := -1

# Espera diegetica de precarga: al entrar, las puertas se cierran y se pide al SceneManager
# precargar la escena destino en background. La transicion (swap seamless) recién se dispara
# cuando la precarga termino, o al vencer el tope para no quedar trabado si el loader falla.
const MAX_PRELOAD_WAIT_FRAMES := 120
var _preload_requested := false
var _wait_frames := 0
var _dump_until_frame := -1

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_signal("scene_ready"):
		if not sm.is_connected("scene_ready", self, "_on_scene_ready"):
			sm.connect("scene_ready", self, "_on_scene_ready")
	set_process(false)

func _on_scene_ready(_path, scene_root, _params) -> void:
	if is_instance_valid(scene_root) and (scene_root == get_tree().current_scene or _is_ancestor(scene_root)):
		_scene_ready_frame = Engine.get_physics_frames()

# True si "node" es un ancestro de este airlock en el arbol de escena.
func _is_ancestor(node: Node) -> bool:
	var p := get_parent()
	while is_instance_valid(p):
		if p == node:
			return true
		p = p.get_parent()
	return false

func _on_body_entered(body: Node) -> void:
	if OS.get_environment("ODISEA_DEBUG_SEAMLESS") == "1":
		print("[TubeAirlock] body_entered on ", name, " triggered=", _has_triggered, " ready_frame=", _scene_ready_frame, " phys_frame=", Engine.get_physics_frames(), " body_pos=", (body as Spatial).global_transform.origin if body is Spatial else Vector3.ZERO)
	if _has_triggered:
		return
	if not body.is_in_group("player"):
		return
	if _scene_ready_frame >= 0 and Engine.get_physics_frames() - _scene_ready_frame < _POST_TRANSITION_GRACE_FRAMES:
		return
	# Durante un swap seamless (add-before-free) el jugador sostenido por el AirlockManager
	# solapa el airlock idéntico de la escena nueva antes de ser reposicionado. Ese overlap
	# re-dispara una transición de vuelta (rebote) porque el grace de scene_ready del
	# airlock nuevo aún no está armado. Mientras SceneManager tenga una transición viva,
	# este airlock ignora entradas.
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_method("is_transitioning") and sm.is_transitioning():
		return

	if target_dome != "":
		_has_triggered = true
		# monitoring no se puede tocar en caliente durante un callback de body_entered
		# (Godot lo bloquea: "Function blocked during in/out signal"); set_deferred lo aplica
		# despues de que la señal termine de procesarse.
		set_deferred("monitoring", false)
		close_doors()
		_begin_seamless_preload()

func _begin_seamless_preload() -> void:
	_preload_requested = true
	_wait_frames = 0
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_method("request_scene_preload") and not sm.has_preloaded_scene(target_dome):
		print("[TubeAirlock] preload requested for ", target_dome, " sm=", sm != null)
		sm.request_scene_preload(target_dome)
	set_process(true)
	print("[TubeAirlock] _begin_seamless_preload done, process enabled")

func _process(_delta: float) -> void:
	if _dump_until_frame > 0 and OS.get_environment("ODISEA_DEBUG_SEAMLESS") == "1":
		if Engine.get_process_frames() >= _dump_until_frame:
			_dump_until_frame = -1
			set_process(false)
		else:
			var dump_player = _find_player()
			if is_instance_valid(dump_player) and dump_player is Spatial:
				print("[TubeAirlock] dump origin=", (dump_player as Spatial).global_transform.origin)
			return
	if not _preload_requested or not _has_triggered:
		return
	_wait_frames += 1
	if OS.get_environment("ODISEA_DEBUG_SEAMLESS") == "1" and _wait_frames == 70:
		for node in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(node) and node is Spatial:
				print("[TubeAirlock] DUMP pilot ", node.name, " path=", node.get_path(), " origin=", (node as Spatial).global_transform.origin)
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_method("has_preloaded_scene") and not sm.has_preloaded_scene(target_dome):
		# Espera diegetica: las puertas quedan cerradas hasta que la carga termina
		# (o vence el tope). Nunca se muestra un fondo negro.
		if _wait_frames % 30 == 0:
			print("[TubeAirlock] waiting preload frame=", _wait_frames)
		if _wait_frames < MAX_PRELOAD_WAIT_FRAMES:
			return
	print("[TubeAirlock] transition fired at frame=", _wait_frames)
	set_process(false)
	_transition_to_target()

func _build_seamless_params() -> Dictionary:
	return {
		"target_spawn_id": target_spawn,
		"preserve_player_state": false,
		"transition": "seamless",
		"fade_out": 0.0,
		"fade_in": 0.0,
		"wait_for_fade_out": false
	}

func _transition_to_target() -> void:
	_dump_until_frame = Engine.get_process_frames() + 120
	set_process(true)
	var sm = get_node_or_null("/root/SceneManager")
	if sm:
		var airlock_manager = get_node_or_null("/root/AirlockManager")
		if airlock_manager != null and airlock_manager.has_method("notify_transition"):
			airlock_manager.notify_transition(target_dome)
		sm.goto_scene(target_dome, _build_seamless_params())
	else:
		printerr("[TubeAirlock] SceneManager not found")

func _find_player() -> Node:
	var session = get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session.player):
		return session.player
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			return p
	return null

func open_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(true)

func close_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(false)
