extends Node

# FD-324 F4 — host opcional del Suit OS del Ark-Run.
#
# Se cuelga de RaceHudRoot cuando se integra el slice. Registra las apps y, a
# 10 Hz (no por frame), alimenta posición/velocidad/a_axial, los destinos con
# nombre y la ruta activa desde el piloto, SpinFrame y ArkRunCanonicalRoute.
# Sin EngineIgnitionRoot (F5) el estado queda IDLE y a_axial = 0.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const ThrusterInputScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const RopeSwingScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const UPDATE_INTERVAL := 0.1
const THRUSTERS_SCREEN_ID := "player:thrusters"
const ROPE_SCREEN_ID := "player:rope"
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
	var pilot = _player(tree)
	if pilot == null:
		return
	var scene = _scene(tree)
	var nav = _screen(suit_os, "ship:ark_nav")
	if nav != null:
		nav.update_navigation(pilot.global_transform.origin, _scene_omega(tree),
			_axial_accel(tree), _velocity_of(pilot))
		if scene != null:
			_sync_route(nav, scene)
		_refresh_ignition(nav, tree)
	_refresh_propulsion(suit_os, pilot, scene)


func _screen(suit_os, screen_id: String):
	if suit_os == null or not suit_os.has_method("get_screen"):
		return null
	return suit_os.get_screen(screen_id)


# Apps reubicables: el host empuja la lectura del slice; la app y el hold salen del
# slot donde el jugador la haya puesto (SuitOS es la única fuente de "dónde está").
func _refresh_propulsion(suit_os, pilot, scene) -> void:
	_update_thrusters(suit_os, pilot, scene)
	_update_rope(suit_os, pilot, scene)


func _update_thrusters(suit_os, pilot, scene) -> void:
	var screen = _screen(suit_os, THRUSTERS_SCREEN_ID)
	if screen == null or not screen.has_method("set_thruster_state"):
		return
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	var remaining := 0.0
	var maximum := 0.0
	if physics != null:
		remaining = _float_property(physics, "spin_thruster_dv_remaining", 0.0)
		maximum = _float_property(physics, "spin_thruster_dv_max", 0.0)
	screen.set_thruster_state(remaining, maximum, _thrusting(scene))


func _thrusting(scene) -> bool:
	var thruster = _thruster_input(scene)
	if thruster == null or not thruster.has_method("read_left_trigger") \
			or not thruster.has_method("read_keyboard_pressed"):
		return false
	var deadzone := _float_property(thruster, "deadzone", ThrusterInputScript.DEFAULT_DEADZONE)
	return ThrusterInputScript.is_thrusting(
		thruster.read_left_trigger(), thruster.read_keyboard_pressed(), deadzone)


func _update_rope(suit_os, pilot, scene) -> void:
	var screen = _screen(suit_os, ROPE_SCREEN_ID)
	if screen == null or not screen.has_method("set_rope_state"):
		return
	var rope_input = _rope_input(scene)
	if rope_input == null:
		screen.set_rope_state(false, false, 0.0)
		return
	var attached := false
	if rope_input.has_method("is_attached"):
		attached = bool(rope_input.is_attached())
	var length := 0.0
	if attached:
		var rope = rope_input.get_rope() if rope_input.has_method("get_rope") else null
		if rope != null and rope.has_method("get_rope_length"):
			length = float(rope.get_rope_length())
	screen.set_rope_state(attached, _anchor_ready(rope_input, pilot), length)


func _thruster_input(scene):
	if slice != null and is_instance_valid(slice) and "thruster_input" in slice:
		return slice.thruster_input
	if scene == null:
		return null
	return scene.get_node_or_null("ExplosionController/ArkRunThrusterInput")


func _rope_input(scene):
	if slice != null and is_instance_valid(slice) and "rope_input" in slice:
		return slice.rope_input
	if scene == null:
		return null
	return scene.get_node_or_null("TraversalRoot/Rope")


# EN RANGO = hay al menos un anclaje dentro de rango y cono desde la mirada actual.
func _anchor_ready(rope_input, pilot) -> bool:
	if rope_input == null or pilot == null or not is_instance_valid(pilot):
		return false
	var anchors = rope_input.get("_anchors")
	if typeof(anchors) != TYPE_ARRAY:
		return false
	var forward: Vector3 = -pilot.global_transform.basis.z
	if forward.length_squared() < 0.000001:
		return false
	var max_range := _float_property(rope_input, "max_range", 55.0)
	var cone_deg := _float_property(rope_input, "cone_deg", 38.0)
	var best: Dictionary = RopeSwingScript.select_best_anchor(
		pilot.global_transform.origin, forward.normalized(), anchors, max_range, cone_deg)
	return bool(best.get("hit", false))


func _float_property(obj, property_name: String, default_value: float) -> float:
	if obj == null or not (property_name in obj):
		return default_value
	var value = obj.get(property_name)
	if typeof(value) == TYPE_REAL or typeof(value) == TYPE_INT:
		return float(value)
	return default_value


# Helpers deterministas de slot: leen la acción del slot que HOY ocupa la app. Si el
# jugador la mueve, el índice (y la acción) siguen solos porque salen de SuitOS.
func is_thrusters_slot_pressed() -> bool:
	return _slot_app_pressed(THRUSTERS_SCREEN_ID)


func is_rope_slot_pressed() -> bool:
	return _slot_app_pressed(ROPE_SCREEN_ID)


func _slot_app_pressed(screen_id: String) -> bool:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return false
	var index := -1
	if screen_id == THRUSTERS_SCREEN_ID and suit_os.has_method("thrusters_slot_index"):
		index = int(suit_os.thrusters_slot_index())
	elif screen_id == ROPE_SCREEN_ID and suit_os.has_method("rope_slot_index"):
		index = int(suit_os.rope_slot_index())
	if index < 0:
		return false
	var number := index + 1
	for action in ["slot_%d" % number, "hud_slot_%d" % number]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


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
