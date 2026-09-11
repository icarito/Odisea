extends HUDableComponent
class_name SystemStatusScreen

# SystemStatusScreen.gd - HUDable screen source for Ship System Status (FD-296 F2)

const WidgetScene = preload("res://core_v2/ui/hud/SystemStatusWidget.tscn")

export(NodePath) var bus_path: NodePath = NodePath("")

func _init() -> void:
	hud_screen_id = "ship:systems"
	hud_screen_title = "Sistemas de nave"
	hud_widget_scene = WidgetScene
	default_relevance = 0.1

func _ready() -> void:
	call_deferred("_bind_bus")

func _bind_bus() -> void:
	var bus = _get_bus()
	if is_instance_valid(bus) and bus.has_signal("systems_changed"):
		if not bus.is_connected("systems_changed", self, "_on_systems_changed"):
			bus.connect("systems_changed", self, "_on_systems_changed")

func widget_snapshot() -> Dictionary:
	var summary: Dictionary = {}
	var bus = _get_bus()
	if is_instance_valid(bus) and bus.has_method("get_summary"):
		summary = bus.get_summary()

	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"source": "online",
		"systems": summary
	}

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	var bus = _get_bus()

	if is_instance_valid(bus) and bus.has_method("get_summary"):
		var summary: Dictionary = bus.get_summary()
		var has_fallo: bool = false
		var has_degradado: bool = false

		for sys_id in summary.keys():
			var sys_data = summary[sys_id]
			if typeof(sys_data) == TYPE_DICTIONARY:
				var st: int = int(sys_data.get("state", 3))
				if st == 2: # STATE_FALLO
					has_fallo = true
				elif st == 1: # STATE_DEGRADADO
					has_degradado = true

		if has_fallo:
			rel += 0.6
		elif has_degradado:
			rel += 0.3

	return clamp(rel, 0.0, 1.0)

func allowed_actions() -> Array:
	return []

func perform_action(_op: String, _args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": "Acción no permitida"}

func _on_systems_changed(_summary: Dictionary) -> void:
	notify_state_changed()

func _get_bus() -> Node:
	if not String(bus_path).empty():
		var n = get_node_or_null(bus_path)
		if is_instance_valid(n):
			return n

	if is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("ship_system_bus")
		if not nodes.empty():
			return nodes[0]

	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("get_summary"):
		return parent

	return null
