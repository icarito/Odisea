extends Node

# FD-324 F4 — host opcional del Suit OS del Ark-Run.
#
# Se cuelga de RaceHudRoot cuando se integra el slice. Registra las apps y, a
# 10 Hz (no por frame), alimenta posición/velocidad/a_axial, los destinos con
# nombre y la ruta activa desde el piloto, SpinFrame y ArkRunCanonicalRoute.
# Sin EngineIgnitionRoot (F5) el estado queda IDLE y a_axial = 0.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const UPDATE_INTERVAL := 0.1
const ROUTE_DESTINATIONS := [
	{"id": "bridge", "label": "Puente", "waypoint": "Puente"},
	{"id": "core", "label": "Núcleo", "waypoint": "Núcleo"},
	{"id": "engine", "label": "Motor", "waypoint": "Motor"},
	{"id": "elevators", "label": "Ascensores", "waypoint": "Ascensor_45"},
]

var slice = null
var _accum := 0.0


func set_slice(node) -> void:
	slice = node


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
	if tree == null:
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
	var scene = _scene(tree)
	nav.update_navigation(pilot.global_transform.origin, _scene_omega(tree),
		_axial_accel(tree), _velocity_of(pilot))
	if scene != null:
		_sync_route(nav, scene)
	_refresh_ignition(nav, tree)


# Escena del slice: inyectada por ArkRunSlice; si no, la escena activa.
func _scene(tree):
	if slice != null and is_instance_valid(slice):
		return slice
	return tree.current_scene


func _player(tree) -> Node:
	if slice != null and is_instance_valid(slice) and "pilot" in slice \
			and is_instance_valid(slice.pilot):
		return slice.pilot
	var players: Array = tree.get_nodes_in_group("player")
	if players.empty() or not (players[0] is Spatial):
		return null
	return players[0]


func _velocity_of(pilot) -> Vector3:
	var value = pilot.get("velocity") if "velocity" in pilot else null
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.ZERO


func _scene_omega(tree) -> float:
	var scene = _scene(tree)
	if scene != null and "spin_omega" in scene:
		return float(scene.spin_omega)
	return SpinFrame.omega_for()


func _axial_accel(tree) -> float:
	var scene = _scene(tree)
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


# Enlaza destinos y ruta activa con ArkRunCanonicalRoute (proa→popa).
func _sync_route(nav, scene) -> void:
	if not scene.has_method("get_canonical_route"):
		return
	var route = scene.get_canonical_route()
	if route == null:
		return
	if "hull_radius" in nav and scene.has_method("get_hull_radius"):
		nav.hull_radius = float(scene.get_hull_radius())
	if "slice_length" in nav and scene.has_method("get_slice_length"):
		nav.slice_length = float(scene.get_slice_length())
	if nav.has_method("set_destinations"):
		nav.set_destinations(_route_destinations(route))
	if nav.has_method("set_route"):
		nav.set_route(route.route_to(_waypoint_for(String(nav.get_destination_id()))))


func _route_destinations(route) -> Array:
	var result: Array = []
	for entry in ROUTE_DESTINATIONS:
		var waypoint: Dictionary = route.get_named_waypoint(String(entry["waypoint"]))
		if waypoint.empty():
			continue
		result.append({
			"id": String(entry["id"]), "label": String(entry["label"]),
			"position": waypoint["position"],
		})
	return result


func _waypoint_for(destination_id: String) -> String:
	for entry in ROUTE_DESTINATIONS:
		if String(entry["id"]) == destination_id:
			return String(entry["waypoint"])
	return String(ROUTE_DESTINATIONS[0]["waypoint"])


func _refresh_ignition(nav, tree) -> void:
	var scene = _scene(tree)
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
