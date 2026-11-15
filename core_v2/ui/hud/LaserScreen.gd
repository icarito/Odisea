extends HUDableComponent
class_name LaserScreen

# LaserScreen.gd - Pantalla equipable del laser del multi-tool (FD-296 F2 / FD-298).
#
# El laser deja de ser un "modo" que se cicla: es un objeto del HUD como la Linterna.
# Se equipa desde su widget/slot (Equipped.LASER en MultiToolV2) y el boton de uso
# (tool_fire_primary) lo dispara. El enfoque del estado vive en MultiToolV2; esta
# pantalla solo lo lee y actua sobre el.

const WidgetScene = preload("res://core_v2/ui/hud/LaserWidget.tscn")

export(NodePath) var multitool_path: NodePath = NodePath("")

func _init() -> void:
	hud_screen_id = "player:laser"
	hud_screen_title = "Láser"
	hud_widget_scene = WidgetScene
	default_relevance = 0.1
	allowed_actions_list = ["equip"]

func _ready() -> void:
	call_deferred("_bind_tool")

func _bind_tool() -> void:
	var tool_node = _get_tool()
	if is_instance_valid(tool_node) and tool_node.has_signal("tool_state_changed"):
		if not tool_node.is_connected("tool_state_changed", self, "_on_tool_state_changed"):
			tool_node.connect("tool_state_changed", self, "_on_tool_state_changed")

func widget_snapshot() -> Dictionary:
	var tool_node = _get_tool()
	var equipped := false
	if is_instance_valid(tool_node) and tool_node.has_method("get_equipped_name"):
		equipped = tool_node.get_equipped_name() == "LASER"
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"equipped": equipped,
		"source": "online"
	}

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	var tool_node = _get_tool()
	if is_instance_valid(tool_node) and tool_node.has_method("get_equipped_name") \
			and tool_node.get_equipped_name() == "LASER":
		rel += 0.5
	return clamp(rel, 0.0, 1.0)

# Tap de hombro sobre el slot (FD-304): equipa el laser.
func hud_gamepad_actions() -> Array:
	return [{
		"button": "a", "op": "equip", "label": tr("Equipar Láser"),
		"icon": "", "enabled": true, "confirm": true
	}]

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op == "equip":
		var tool_node = _get_tool()
		if is_instance_valid(tool_node) and tool_node.has_method("set_equipped"):
			var desired: bool = bool(args.get("desired", true))
			tool_node.set_equipped(1 if desired else 0) # 1=LASER, 0=NONE
			notify_state_changed()
			return {"ok": true, "result": "equipped", "tool": "LASER", "on": desired}
		return {"ok": false, "error": "Multi-tool not found"}
	return {"ok": false, "error": "Action '%s' not supported" % op}

func _on_tool_state_changed() -> void:
	notify_state_changed()

func _get_tool() -> Node:
	if not String(multitool_path).empty():
		var n = get_node_or_null(multitool_path)
		if is_instance_valid(n):
			return n
	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("set_equipped"):
		return parent
	if is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("multitool")
		if not nodes.empty():
			return nodes[0]
	return null
