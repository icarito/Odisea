extends Node

# FD-324 F4 — host opcional del Suit OS del Ark-Run.
#
# Se cuelga de RaceHudRoot (o de la escena base) cuando se integre el slice. Registra
# las apps y, a 10 Hz (no por frame), alimenta la navegación desde el piloto y desde
# SpinFrame. Sin EngineIgnitionRoot (F5) el estado queda IDLE y a_axial = 0.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const UPDATE_INTERVAL := 0.1

var _accum := 0.0


func _ready() -> void:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return
	if suit_os.has_method("ensure_ark_run_apps"):
		suit_os.ensure_ark_run_apps()
	if suit_os.has_method("apply_ark_run_default_pins"):
		suit_os.apply_ark_run_default_pins()


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var suit_os = tree.root.get_node_or_null("SuitOS")
	if suit_os == null:
		return
	var nav = suit_os.get_screen("ship:ark_nav") if suit_os.has_method("get_screen") else null
	if nav == null:
		return
	var pilot = _player(tree)
	if pilot == null:
		return
	nav.update_navigation(pilot.global_transform.origin, _scene_omega(tree), _axial_accel(tree))
	_refresh_ignition(nav, tree)


func _player(tree) -> Node:
	var players: Array = tree.get_nodes_in_group("player")
	if players.empty() or not (players[0] is Spatial):
		return null
	return players[0]


func _scene_omega(tree) -> float:
	var scene = tree.current_scene
	if scene != null and "spin_omega" in scene:
		return float(scene.spin_omega)
	return SpinFrame.omega_for()


func _axial_accel(tree) -> float:
	var scene = tree.current_scene
	if scene == null:
		return 0.0
	var ignition = scene.get_node_or_null("EngineIgnitionRoot")
	if ignition != null:
		if ignition.has_method("get_axial_accel"):
			return float(ignition.get_axial_accel())
		if "a_axial" in ignition:
			return float(ignition.a_axial)
	if "a_axial" in scene:
		return float(scene.a_axial)
	return 0.0


func _refresh_ignition(nav, tree) -> void:
	var scene = tree.current_scene
	if scene == null:
		return
	var ignition = scene.get_node_or_null("EngineIgnitionRoot")
	if ignition == null:
		return
	if ignition.has_method("get_ignition_state"):
		nav.set_ignition_state(String(ignition.get_ignition_state()), _countdown(ignition))
	elif "state" in ignition:
		nav.set_ignition_state(String(ignition.state), _countdown(ignition))


func _countdown(ignition) -> float:
	var value = ignition.get("countdown")
	return float(value) if value != null else 0.0
