extends Reference
class_name InteractableSlotScreen

# InteractableSlotScreen.gd - Envoltorio "pantalla" de un interactuable para fijarlo a un slot del
# HUD. Reusa el registry y el pipeline de widgets de SuitOS, que ya saben pintar un snapshot y
# despachar acciones: el widget del slot muestra la ficha (nombre/descripcion/verbo/icono) y
# acciona el interactuable al tocarlo.
#
# El id sale del path del nodo ("interactable:/root/.../ValveWestFloor1"), asi que es estable
# mientras el prop viva. Si el prop se libera, is_valid() da false y el slot cae a offline.

signal state_changed

var target_path: NodePath = NodePath()
var _target: Node = null
var _bound_signals: Array = []

func bind(node: Node) -> void:
	_target = node
	target_path = node.get_path() if node != null and node.is_inside_tree() else NodePath()
	if node == null:
		return
	for sig in ["activated", "deactivated", "interaction_completed"]:
		if node.has_signal(sig) and not node.is_connected(sig, self, "_forward_state"):
			node.connect(sig, self, "_forward_state")
			_bound_signals.append(sig)

func is_valid() -> bool:
	return is_instance_valid(_target)

func screen_id() -> String:
	return "interactable:%s" % String(target_path)

func screen_title() -> String:
	if is_valid() and "interaction_title" in _target:
		var custom := String(_target.interaction_title).strip_edges()
		if custom != "":
			return custom
	return _humanized()

func screen_icon() -> Texture:
	if is_valid() and "interaction_icon" in _target and _target.interaction_icon is Texture:
		return _target.interaction_icon
	return null

func relevance(_context: Dictionary = {}) -> float:
	return 0.0

func allowed_actions() -> Array:
	return ["interact"]

func widget_snapshot() -> Dictionary:
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"description": _description(),
		"action": _verb(),
		"icon": screen_icon(),
		"active": _is_active(),
		"focused": false,
		"source": "interactable" if is_valid() else "offline",
	}

func hud_gamepad_actions() -> Array:
	return [{"button": "a", "label": _verb(), "enabled": is_valid(), "op": "interact"}]

func perform_action(op: String, _args: Dictionary = {}) -> Dictionary:
	if op != "interact":
		return {"ok": false, "error": "Action '%s' no soportada" % op}
	if not is_valid():
		return {"ok": false, "error": "Interactuable liberado"}
	if _target.has_method("interact"):
		_target.call("interact")
		emit_signal("state_changed")
		return {"ok": true}
	return {"ok": false, "error": "No es interactuable"}

func _forward_state(_a = null, _b = null) -> void:
	emit_signal("state_changed")

func _verb() -> String:
	if is_valid() and _target.has_method("get_interaction_prompt"):
		return String(_target.call("get_interaction_prompt"))
	return "Interactuar"

func _description() -> String:
	if is_valid() and "interaction_description" in _target:
		return String(_target.interaction_description)
	return ""

func _is_active() -> bool:
	return bool(_target.is_active) if is_valid() and "is_active" in _target else false

func _humanized() -> String:
	var path_str := String(target_path)
	var node_name := path_str.get_file() if path_str != "" else "Interactuable"
	return node_name.replace("_", " ")
