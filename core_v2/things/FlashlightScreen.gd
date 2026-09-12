extends HUDableComponent
class_name FlashlightScreen

# FlashlightScreen.gd - HUDable screen source for Helmet Flashlight (FD-298)

const WidgetScene = preload("res://core_v2/ui/hud/FlashlightWidget.tscn")

export(NodePath) var flashlight_path: NodePath = NodePath("")

func _init() -> void:
	hud_screen_id = "player:flashlight"
	hud_screen_title = "Linterna"
	hud_widget_scene = WidgetScene
	default_relevance = 0.1
	allowed_actions = ["toggle"]

func _ready() -> void:
	call_deferred("_bind_flashlight")

func _bind_flashlight() -> void:
	var fl = _get_flashlight()
	if is_instance_valid(fl):
		if fl.has_signal("battery_changed") and not fl.is_connected("battery_changed", self, "_on_flashlight_changed"):
			fl.connect("battery_changed", self, "_on_flashlight_changed")

func widget_snapshot() -> Dictionary:
	var fl = _get_flashlight()
	var is_on := false
	var batt := 100.0
	var batt_max := 100.0
	var is_low := false

	if is_instance_valid(fl):
		if "enabled" in fl:
			is_on = bool(fl.enabled)
		if fl.has_method("get_battery"):
			batt = float(fl.get_battery())
		elif "battery" in fl:
			batt = float(fl.battery)
		if fl.has_method("get_battery_max"):
			batt_max = float(fl.get_battery_max())
		elif "battery_max" in fl:
			batt_max = float(fl.battery_max)
		if fl.has_method("is_battery_low"):
			is_low = bool(fl.is_battery_low())
		else:
			is_low = batt <= 20.0

	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"on": is_on,
		"battery": batt,
		"battery_max": batt_max,
		"low": is_low,
		"source": "online"
	}

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	var fl = _get_flashlight()

	if is_instance_valid(fl):
		var is_on: bool = bool(fl.enabled) if "enabled" in fl else false
		var is_low: bool = false
		if fl.has_method("is_battery_low"):
			is_low = bool(fl.is_battery_low())
		elif "battery" in fl and "battery_low_threshold" in fl:
			is_low = float(fl.battery) <= float(fl.battery_low_threshold)

		if is_on:
			rel += 0.2
		if is_low:
			rel += 0.5

	return clamp(rel, 0.0, 1.0)

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op == "toggle":
		var fl = _get_flashlight()
		if is_instance_valid(fl) and fl.has_method("toggle"):
			fl.toggle()
			notify_state_changed()
			return {"ok": true, "result": "toggled", "on": bool(fl.enabled)}
		return {"ok": false, "error": "Flashlight not found"}
	return {"ok": false, "error": "Action '%s' not supported" % op}

func _on_flashlight_changed(_val = null, _max_val = null) -> void:
	notify_state_changed()

func _get_flashlight() -> Node:
	if not String(flashlight_path).empty():
		var n = get_node_or_null(flashlight_path)
		if is_instance_valid(n):
			return n

	var parent = get_parent()
	if is_instance_valid(parent):
		if parent.has_method("toggle") and ("battery" in parent or parent.has_method("get_battery")):
			return parent

	if is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("flashlight")
		if not nodes.empty():
			return nodes[0]
		# Fallback: check parent's children or player
		if is_instance_valid(parent):
			var fl_child = parent.get_node_or_null("HelmetFlashlight")
			if is_instance_valid(fl_child):
				return fl_child

	return null
