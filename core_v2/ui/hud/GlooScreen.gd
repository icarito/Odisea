extends HUDableComponent
class_name GlooScreen

# GlooScreen.gd - Pantalla equipable del gloo del multi-tool (FD-296 F2 / FD-298).
#
# Igual que LaserScreen: el gloo es un objeto equipable del HUD (Equipped.GLOO en
# MultiToolV2), no un modo que se cicla.

const WidgetScene = preload("res://core_v2/ui/hud/GlooWidget.tscn")

export(NodePath) var multitool_path: NodePath = NodePath("")

func _init() -> void:
	hud_screen_id = "player:gloo"
	hud_screen_title = "Gloo"
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
	var active_count := 0
	var max_count := 0
	if is_instance_valid(tool_node):
		if tool_node.has_method("get_equipped_name"):
			equipped = tool_node.get_equipped_name() == "GLOO"
		if tool_node.has_method("get_charge_info"):
			var charge: Dictionary = tool_node.get_charge_info()
			active_count = int(charge.get("active", 0))
			max_count = int(charge.get("max", 0))
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"equipped": equipped,
		"active": active_count,
		"max": max_count,
		"source": "online"
	}

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	var tool_node = _get_tool()
	if is_instance_valid(tool_node):
		if tool_node.has_method("get_equipped_name") and tool_node.get_equipped_name() == "GLOO":
			rel += 0.5
		if tool_node.has_method("get_charge_info"):
			var charge: Dictionary = tool_node.get_charge_info()
			if int(charge.get("active", 0)) > 0:
				rel += 0.2
	return clamp(rel, 0.0, 1.0)

func hud_gamepad_actions() -> Array:
	return [{
		"button": "a", "op": "equip", "label": tr("Equipar Gloo"),
		"icon": "", "enabled": true, "confirm": true
	}]

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op == "equip":
		var tool_node = _get_tool()
		if is_instance_valid(tool_node) and tool_node.has_method("set_equipped"):
			var desired: bool = bool(args.get("desired", true))
			tool_node.set_equipped(2 if desired else 0) # 2=GLOO, 0=NONE
			notify_state_changed()
			return {"ok": true, "result": "equipped", "tool": "GLOO", "on": desired}
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
