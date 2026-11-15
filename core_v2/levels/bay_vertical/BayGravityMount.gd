extends Node
class_name BayGravityMount

# Montaje del modo de gravedad de la bahía sobre el stack cilíndrico real
# (CylinderRotator + ScaffoldStreamController). FD-322.
#
# La geometría/streaming viven en `CylinderRotator` (que mantiene el arco bajo el
# jugador plano, o sea piso caminable). Este nodo es el DUEÑO del modo de gravedad:
# lo lee/escribe en `GravityWorld` (agnóstico al modo, sin asumir "hacia afuera") y
# reconfigura una ruta mode-gated. La consola activa lo llama.
#
# Determinismo: el cambio es de estado (no un reloj). Modo + blend serializables.

const GRAVITY_MODE_THRUST := 0
const GRAVITY_MODE_SPIN := 1

signal gravity_mode_changed(mode)

export(NodePath) var gravity_world_path: NodePath = NodePath("/root/GravityWorld")
export(NodePath) var mode_bridge_path: NodePath = NodePath("")
export(int) var initial_mode := GRAVITY_MODE_SPIN

var _gravity_mode := GRAVITY_MODE_SPIN
var _gravity_blend := 1.0
var _bridge: Spatial = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	_gravity_mode = initial_mode
	if not mode_bridge_path.is_empty():
		_bridge = get_node_or_null(mode_bridge_path)
	_apply_mode(false)

func _gravity_world() -> Node:
	return get_node_or_null(gravity_world_path)

func get_gravity_mode() -> int:
	return _gravity_mode

func get_gravity_blend() -> float:
	return _gravity_blend

func toggle_gravity_mode() -> bool:
	var next := GRAVITY_MODE_SPIN if _gravity_mode == GRAVITY_MODE_THRUST else GRAVITY_MODE_THRUST
	return set_gravity_mode_mode(next)

func set_gravity_mode_mode(mode: int) -> bool:
	if mode == _gravity_mode:
		return false
	_gravity_mode = mode
	_apply_mode(true)
	return true

func _apply_mode(notify: bool) -> void:
	_gravity_blend = 1.0 if _gravity_mode == GRAVITY_MODE_SPIN else 0.0
	var gw := _gravity_world()
	if gw:
		if gw.has_method("set_gravity_mode"):
			gw.set_gravity_mode(_gravity_mode)
		if gw.has_method("set_gravity_blend"):
			gw.set_gravity_blend(_gravity_blend)
		if gw.has_method("set_spiral_blend"):
			gw.set_spiral_blend(_gravity_blend)
	# Ruta mode-gated: el puente sólo existe/solida en propulsión.
	if is_instance_valid(_bridge):
		var thrust: bool = _gravity_mode == GRAVITY_MODE_THRUST
		_set_bridge_solid(_bridge, thrust)
	if notify:
		emit_signal("gravity_mode_changed", _gravity_mode)

func _set_bridge_solid(node: Node, solid: bool) -> void:
	if node is CollisionObject:
		node.collision_layer = 1 if solid else 0
	if node is Spatial:
		node.visible = solid
	for child in node.get_children():
		_set_bridge_solid(child, solid)

func get_snapshot() -> Dictionary:
	return {"gravity_mode": _gravity_mode, "gravity_blend": _gravity_blend}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("gravity_mode"):
		_gravity_mode = int(data["gravity_mode"])
		_gravity_blend = float(data.get("gravity_blend", _gravity_blend))
		_apply_mode(false)
