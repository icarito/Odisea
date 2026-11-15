extends Area
class_name HangarTransition

# HangarTransition.gd - FD-289 §7.5 / §7.9 (descenso del domo -> hangar, tracker #319)
#
# Frontera interior -> interior entre el pozo del blast door del domo y el hangar
# (`Dome_Intro_Hangar.tscn`). NO es un airlock: domo y hangar son interiores presurizados,
# asi que no hay ciclo de presurizacion, ni AirlockControllerV2, ni target_airlock_path.
#
# Transición: se conserva el fade existente. El trayecto NO es seamless todavía: el destino
# (Spawn_FromDomeIntro) no tiene un pozo/plataforma equivalente y el trigger libera el rig
# cinematográfico del pozo, así que sin fade aparece un corte de cámara/entorno. Requiere un
# buffer de llegada equivalente + transferencia continua de cámara antes de migrar.
# (Se mantiene la precarga temprana al arrancar el descenso como optimización: no cambia la
# semántica del fade y adelanta la carga.)
#
# Dispara una sola vez (guard) y respeta POST_TRANSITION_GRACE_FRAMES desde que la escena
# termino de cargar, igual que TubeAirlock/BayAirlockTrigger: el spawn de destino puede
# quedar cerca del trigger y no debe rebotar a una transicion de vuelta.
#
# Ambas vias de descenso (plataforma movil + rampa de servicio) desembocan en este trigger:
# es un volumen que cubre el fondo del pozo.
#
# Determinismo: no usa randf ni reloj de pared; solo geometria y el grupo del jugador.

signal transition_requested(target_scene, target_spawn_id)

# Destino explicito. Si queda vacio, se toma la config del domo
# (`DomeSystemDirector.get_hangar_scene()` / `get_hangar_spawn_id()`, que leen
# `DomeEnvConfig_intro.tres`), para seguir la misma fuente que el resto del cableado.
export(String, FILE, "*.tscn") var target_scene := ""
export(String) var target_spawn_id := ""
export(bool) var use_dome_config := true
# Fuente de la config del domo (hangar_scene / hangar_spawn_id). Seam para tests.
export(NodePath) var director_path := NodePath("/root/DomeSystemDirector")

# Frames de gracia contados desde que SceneManager termino de cargar ESTA instancia de
# escena (el spawn de destino puede quedar cerca del trigger).
const POST_TRANSITION_GRACE_FRAMES := 20

var _has_triggered := false
var _scene_ready_frame := -1
# Seam de test: si esta seteado, se usa en lugar de /root/SceneManager.
var scene_manager_override = null

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	var sm := _resolve_scene_manager()
	if sm != null and sm.has_signal("scene_ready") and not sm.is_connected("scene_ready", self, "_on_scene_ready"):
		sm.connect("scene_ready", self, "_on_scene_ready")
	if sm != null and sm.has_signal("transition_failed") and not sm.is_connected("transition_failed", self, "_on_transition_failed"):
		sm.connect("transition_failed", self, "_on_transition_failed")
	# Precarga temprana: al arrancar el descenso de la plataforma (el jugador se subió),
	# se empieza a cargar el hangar en background. El pozo completo queda como tiempo de
	# buffer antes de llegar al trigger del fondo.
	var platform := get_parent().get_node_or_null("HangarPlatform") if get_parent() else null
	if is_instance_valid(platform) and platform.has_signal("descend_started") and not platform.is_connected("descend_started", self, "_begin_seamless_preload"):
		platform.connect("descend_started", self, "_begin_seamless_preload")

func _resolve_scene_manager() -> Node:
	if scene_manager_override != null and is_instance_valid(scene_manager_override):
		return scene_manager_override
	return get_node_or_null("/root/SceneManager")

func _on_scene_ready(_path, scene_root, _params) -> void:
	if is_instance_valid(scene_root) and (scene_root == get_tree().current_scene or _is_ancestor(scene_root)):
		_scene_ready_frame = Engine.get_physics_frames()

# True si "node" es un ancestro de este trigger en el arbol de escena.
func _is_ancestor(node: Node) -> bool:
	var p: Node = get_parent()
	while is_instance_valid(p):
		if p == node:
			return true
		p = p.get_parent()
	return false

func _on_body_entered(body: Node) -> void:
	if _has_triggered:
		return
	if body == null or not body.is_in_group("player"):
		return
	if _scene_ready_frame >= 0 and Engine.get_physics_frames() - _scene_ready_frame < POST_TRANSITION_GRACE_FRAMES:
		return
	_has_triggered = true
	# monitoring no se puede tocar en caliente durante el callback de body_entered.
	set_deferred("monitoring", false)
	# La camara cinematica del descenso es de ESTA escena: se libera antes del swap para que
	# CinematicManager no quede con un rig ya liberado y el jugador recupere el control limpio.
	_begin_seamless_preload()
	_release_transition_camera()
	_transition_to_target()

func resolve_target_scene() -> String:
	if target_scene.strip_edges() != "":
		return target_scene.strip_edges()
	if use_dome_config:
		var director = _resolve_director()
		if director != null and director.has_method("get_hangar_scene"):
			return String(director.get_hangar_scene()).strip_edges()
	return ""

func resolve_target_spawn_id() -> String:
	if target_spawn_id.strip_edges() != "":
		return target_spawn_id.strip_edges()
	if use_dome_config:
		var director = _resolve_director()
		if director != null and director.has_method("get_hangar_spawn_id"):
			return String(director.get_hangar_spawn_id()).strip_edges()
	return ""

func _resolve_director() -> Node:
	if director_path.is_empty():
		return null
	return get_node_or_null(director_path)

func is_triggered() -> bool:
	return _has_triggered

# Si la transición falla o expira, rearmamos el trigger para que el jugador pueda
# reintentar (el state del lift lo limpia SceneManager en _reset_runtime_state).
func _on_transition_failed(path: String, _reason: String) -> void:
	if String(path).strip_edges() != resolve_target_scene():
		return
	_has_triggered = false
	monitoring = true

# Pide al SceneManager precargar la escena del hangar en background. Idempotente y seguro
# si el manager no existe o ya está precargada.
func _begin_seamless_preload() -> void:
	var resolved := resolve_target_scene()
	if resolved == "":
		return
	var sm := _resolve_scene_manager()
	if sm and sm.has_method("request_scene_preload") and not sm.has_preloaded_scene(resolved):
		sm.request_scene_preload(resolved)

func _release_transition_camera() -> void:
	var cm = get_node_or_null("/root/CinematicManager")
	if cm != null and cm.has_method("is_active") and cm.has_method("deactivate_rig") and bool(cm.is_active()):
		cm.deactivate_rig()

func _transition_to_target() -> bool:
	var resolved_scene := resolve_target_scene()
	if resolved_scene == "":
		printerr("[HangarTransition] target_scene vacio (ni export ni DomeSystemDirector.hangar_scene)")
		return false
	var resolved_spawn := resolve_target_spawn_id()
	emit_signal("transition_requested", resolved_scene, resolved_spawn)

	var sm := _resolve_scene_manager()
	if sm == null or not sm.has_method("goto_scene"):
		printerr("[HangarTransition] SceneManager ausente")
		return false

	# Frontera interior -> interior: change_scene puro. preserve_player_state=false reubica al
	# jugador en el SpawnPointV2 del hangar; wait_for_fade_out evita el corte seco.
	# (Aún NO es seamless: falta un buffer de llegada equivalente y transferencia continua de
	# cámara entre el pozo y el hangar. Ver comentario de cabecera.)
	sm.goto_scene(resolved_scene, {
		"target_spawn_id": resolved_spawn,
		"spawn_id": resolved_spawn,
		"preserve_player_state": false,
		"wait_for_fade_out": true,
	})
	return true
