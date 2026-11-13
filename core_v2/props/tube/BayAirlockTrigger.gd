extends Area
class_name BayAirlockTrigger

# BayAirlockTrigger.gd — Area de esclusa que, al entrar el jugador, enruta a la
# Bahía de Máquinas por el MISMO camino que el pedestal del RingHub
# (`RingHubLightState.enter_machine_bay`, RingHubLightState.gd:187): arma el
# payload de retorno {wakeup, light_state, player_snapshot} y llama a
# SceneManager.goto_scene("…/MachineBay.tscn"). Así el retorno de la bahía
# (MachineLevel.return_to_ring_hub) sigue recibiendo el payload y no se repite el
# despertar, sin tocar SceneManager/AirlockManager (que posee otro worker).
#
# Guard de doble disparo y gracia post-carga: mismo patrón que TubeAirlock.gd.

var _has_triggered := false
const _POST_TRANSITION_GRACE_FRAMES := 20
var _scene_ready_frame := -1

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_signal("scene_ready") and not sm.is_connected("scene_ready", self, "_on_scene_ready"):
		sm.connect("scene_ready", self, "_on_scene_ready")

func _on_scene_ready(_path, scene_root, _params) -> void:
	if is_instance_valid(scene_root) and (scene_root == get_tree().current_scene or _is_ancestor(scene_root)):
		_scene_ready_frame = Engine.get_physics_frames()

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
	if not body.is_in_group("player"):
		return
	if _scene_ready_frame >= 0 and Engine.get_physics_frames() - _scene_ready_frame < _POST_TRANSITION_GRACE_FRAMES:
		return
	_has_triggered = true
	# monitoring no se puede tocar en caliente dentro de un callback de body_entered.
	set_deferred("monitoring", false)
	_enter_machine_bay()

func _enter_machine_bay() -> void:
	var level: Node = get_tree().current_scene
	if level != null:
		var light_state = level.get_node_or_null("LightState")
		if light_state != null and light_state.has_method("enter_machine_bay"):
			light_state.enter_machine_bay()
			return
	# Fallback (nivel de test sin LightState): misma escena destino que el pedestal.
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_method("goto_scene"):
		sm.goto_scene("res://core_v2/levels/machines/MachineBay.tscn", {"wait_for_fade_out": true})
	else:
		printerr("[BayAirlockTrigger] sin LightState.enter_machine_bay ni SceneManager")
