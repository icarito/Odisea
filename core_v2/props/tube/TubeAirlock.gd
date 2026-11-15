extends Area

# TubeAirlock.gd - Automatic airlock for pedestrian tubes
# Detects player and triggers scene transition to another dome/spawn point.
#
# Transición seamless: al entrar, las puertas se cierran y se precarga la escena destino
# en background (SceneManager.request_scene_preload). El swap ocurre detrás de las
# puertas cerradas, sin fade ni cartel, con el jugador sostenido por el AirlockManager
# (la cámara sigue viva durante la carga).
#
# Determinismo: el gating espera el SELLO de la puerta (la IrisDoor anima su cierre) en
# _physics_process, contado en ticks de física — el mismo tick entre grabación y replay.
# No se espera la precarga asíncrona (drift ~1-2cm > umbral); el swap la oculta.

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

# El swap se dispara recién cuando la puerta quedó sellada (set_active(false) anima el
# cierre; si swapeáramos antes, el tubo de origen se destruiría con la puerta abierta y se
# vería el cambio brusco). La espera se cuenta en ticks de física (determinista). Si no hay
# puerta reportable, no se bloquea. Tope de seguridad para no quedar trabado.
const DOOR_CLOSED_EPSILON := 0.05
const MAX_DOOR_CLOSE_WAIT_FRAMES := 90
var _awaiting_seal := false
var _seal_wait_frames := 0

var _preload_requested := false
var _preload_started := false
var _triggered_player: Node = null
# Seam de test: si está seteado, se usa en lugar de /root/SceneManager.
var scene_manager_override = null

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	var sm := _resolve_scene_manager()
	if sm and sm.has_signal("scene_ready"):
		if not sm.is_connected("scene_ready", self, "_on_scene_ready"):
			sm.connect("scene_ready", self, "_on_scene_ready")
	if sm and sm.has_signal("transition_failed"):
		if not sm.is_connected("transition_failed", self, "_on_transition_failed"):
			sm.connect("transition_failed", self, "_on_transition_failed")
	set_physics_process(false)

func _resolve_scene_manager() -> Node:
	if scene_manager_override != null and is_instance_valid(scene_manager_override):
		return scene_manager_override
	return get_node_or_null("/root/SceneManager")

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
	var sm := _resolve_scene_manager()
	if sm != null and sm.has_method("is_transitioning") and sm.is_transitioning():
		return

	if target_dome != "":
		_has_triggered = true
		_triggered_player = body
		# monitoring no se puede tocar en caliente durante un callback de body_entered
		# (Godot lo bloquea: "Function blocked during in/out signal"); set_deferred lo aplica
		# despues de que la señal termine de procesarse.
		set_deferred("monitoring", false)
		close_doors()
		_begin_seamless_preload()
		_awaiting_seal = true
		_seal_wait_frames = 0
		set_physics_process(true)

func _begin_seamless_preload() -> void:
	_preload_requested = true
	_preload_started = false
	var sm := _resolve_scene_manager()
	if sm and sm.has_method("request_scene_preload") and not sm.has_preloaded_scene(target_dome):
		sm.request_scene_preload(target_dome)
		_preload_started = true

# El gating corre en _physics_process (no en _process): el grabador OYS cuantiza por
# tick de física, así que tanto el sello de la puerta como el disparo quedan alineados al
# mismo tick entre grabación y replay.
func _physics_process(_delta: float) -> void:
	if not _has_triggered:
		return
	if _awaiting_seal:
		_seal_wait_frames += 1
		# Si el jugador salió del volumen durante la espera (monitoring apagado, conserva
		# movimiento), cancelar el ciclo y rearmar en vez de teletransportarlo desde afuera.
		if not _is_player_inside(_triggered_player):
			_cancel_pending()
			return
		if not _is_door_sealed() and _seal_wait_frames < MAX_DOOR_CLOSE_WAIT_FRAMES:
			return
		_awaiting_seal = false
	set_physics_process(false)
	_transition_to_target()

func _is_player_inside(player: Node) -> bool:
	if not is_instance_valid(player) or not (player is Spatial):
		return false
	var shape_node := get_node_or_null("CollisionShape")
	if shape_node and shape_node.shape is BoxShape:
		# El CollisionShape real de TubeAirlock.tscn NO está centrado en el Area (está
		# desplazado +1 en Z, cubre Z local 0..2). Transformar la posición al ESPACIO
		# GLOBAL de la forma (incluye desplazamiento, rotación y escala) y comparar con
		# sus extents; no asumir que la forma coincide con el origen del Area.
		var box := shape_node.shape as BoxShape
		var local: Vector3 = shape_node.global_transform.affine_inverse().xform((player as Spatial).global_transform.origin)
		return abs(local.x) <= box.extents.x and abs(local.y) <= box.extents.y and abs(local.z) <= box.extents.z
	# Sin forma declarada (tests/fallback): geometría del Area centrada en el origen.
	var local_area: Vector3 = global_transform.affine_inverse().xform((player as Spatial).global_transform.origin)
	var extents := Vector3(2, 2, 1)
	return abs(local_area.x) <= extents.x and abs(local_area.y) <= extents.y and abs(local_area.z) <= extents.z

func _is_door_sealed() -> bool:
	var door := get_node_or_null("IrisDoorV2")
	var state_node := _find_door_state_node(door)
	if not is_instance_valid(state_node):
		return true  # sin puerta o estado ilegible: no bloquear
	if "is_active" in state_node and bool(state_node.get("is_active")):
		return false
	if "target_progress" in state_node and float(state_node.get("target_progress")) > DOOR_CLOSED_EPSILON:
		return false
	if "anim_progress" in state_node and float(state_node.get("anim_progress")) > DOOR_CLOSED_EPSILON:
		return false
	return true

func _find_door_state_node(door: Node) -> Node:
	if not is_instance_valid(door):
		return null
	if ("is_active" in door) or ("anim_progress" in door) or ("target_progress" in door):
		return door
	var pending: Array = [door]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node != door and (("is_active" in node) or ("anim_progress" in node) or ("target_progress" in node)):
			return node
		for child in node.get_children():
			pending.push_back(child)
	return null

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
	var sm := _resolve_scene_manager()
	if sm:
		var airlock_manager = get_node_or_null("/root/AirlockManager")
		if airlock_manager != null and airlock_manager.has_method("notify_transition"):
			airlock_manager.notify_transition(target_dome)
		sm.goto_scene(target_dome, _build_seamless_params())
	else:
		printerr("[TubeAirlock] SceneManager not found")

# Si la transición falla o expira, `notify_transition` pudo dejar el lift del AirlockManager
# armado sin llegar al swap. SceneManager lo limpia en _reset_runtime_state; acá rearmamos
# este airlock para que el jugador pueda reintentar (puertas abiertas + monitoring otra vez).
func _on_transition_failed(path: String, _reason: String) -> void:
	if String(path) != target_dome:
		return
	_cancel_pending()

func _cancel_pending() -> void:
	_has_triggered = false
	_preload_requested = false
	_preload_started = false
	_awaiting_seal = false
	_seal_wait_frames = 0
	_triggered_player = null
	set_physics_process(false)
	monitoring = true
	open_doors()

func open_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(true)

func close_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(false)
