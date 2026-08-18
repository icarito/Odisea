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

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_signal("scene_ready"):
		if not sm.is_connected("scene_ready", self, "_on_scene_ready"):
			sm.connect("scene_ready", self, "_on_scene_ready")

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

	if target_dome != "":
		_has_triggered = true
		# monitoring no se puede tocar en caliente durante un callback de body_entered
		# (Godot lo bloquea: "Function blocked during in/out signal"); set_deferred lo aplica
		# despues de que la señal termine de procesarse.
		set_deferred("monitoring", false)
		_transition_to_target()

func _transition_to_target() -> void:
	var sm = get_node_or_null("/root/SceneManager")
	if sm:
		var params = {
			"target_spawn_id": target_spawn,
			"fade_out": 0.5,
			"fade_in": 0.5,
			"wait_for_fade_out": true
		}
		sm.goto_scene(target_dome, params)
	else:
		printerr("[TubeAirlock] SceneManager not found")

func open_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(true)

func close_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(false)
