extends HUDableComponent
class_name MultiToolScreen

# MultiToolScreen.gd - HUDable screen source for Multi-tool status (FD-296 F2)

const WidgetScene = preload("res://core_v2/ui/hud/MultiToolWidget.tscn")

export(NodePath) var multitool_path: NodePath = NodePath("")

func _init() -> void:
	hud_screen_id = "player:multitool"
	hud_screen_title = "Multi-tool"
	hud_widget_scene = WidgetScene
	default_relevance = 0.1

func _ready() -> void:
	call_deferred("_bind_tool")

func _bind_tool() -> void:
	var tool_node = _get_tool()
	if is_instance_valid(tool_node) and tool_node.has_signal("tool_state_changed"):
		if not tool_node.is_connected("tool_state_changed", self, "_on_tool_state_changed"):
			tool_node.connect("tool_state_changed", self, "_on_tool_state_changed")

func widget_snapshot() -> Dictionary:
	var tool_node = _get_tool()
	var mode_name: String = "LASER"
	var charge_info: Dictionary = {"active": 0, "max": 18}

	if is_instance_valid(tool_node):
		if tool_node.has_method("get_mode_name"):
			mode_name = tool_node.get_mode_name()
		if tool_node.has_method("get_charge_info"):
			charge_info = tool_node.get_charge_info()

	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"mode": mode_name,
		"charge": charge_info,
		"source": "online"
	}

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	var tool_node = _get_tool()

	if is_instance_valid(tool_node):
		if tool_node.has_method("get_mode_name") and tool_node.get_mode_name() == "GLOO":
			rel += 0.3
		if tool_node.has_method("get_charge_info"):
			var charge: Dictionary = tool_node.get_charge_info()
			if int(charge.get("active", 0)) > 0:
				rel += 0.3

	if context.get("multitool_active", false):
		rel += 0.3

	return clamp(rel, 0.0, 1.0)

func _on_tool_state_changed() -> void:
	notify_state_changed()

func _get_tool() -> Node:
	if not String(multitool_path).empty():
		var n = get_node_or_null(multitool_path)
		if is_instance_valid(n):
			return n

	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("get_mode_name"):
		return parent

	if is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("multitool")
		if not nodes.empty():
			return nodes[0]

	return null
