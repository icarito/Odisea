extends HUDableComponent
class_name HoloTerminalHUDable

# HoloTerminalHUDable.gd - HoloTerminal bridge component for SuitOS / OdiseaOS (FD-296 F1.5)
# Exposes a HoloTerminalV2 instance as a HUDable screen source without modifying HoloTerminalV2.gd.

const DefaultWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")

export(NodePath) var terminal_path: NodePath = NodePath("")

var _last_active: bool = false
var _last_focused: bool = false

func widget_scene() -> PackedScene:
	if hud_widget_scene != null:
		return hud_widget_scene
	return DefaultWidgetScene

func _physics_process(_delta: float) -> void:
	var terminal = _get_terminal()
	if is_instance_valid(terminal):
		var active_now: bool = terminal.get_is_open() if terminal.has_method("get_is_open") else bool(terminal.get("is_active"))
		var focused_now: bool = terminal.is_focused() if terminal.has_method("is_focused") else false
		if active_now != _last_active or focused_now != _last_focused:
			_last_active = active_now
			_last_focused = focused_now
			notify_state_changed()

func screen_id() -> String:
	if not hud_screen_id.empty():
		return hud_screen_id

	var target_node: Node = owner
	if target_node == null:
		target_node = get_parent()
	if target_node == null:
		target_node = self

	var path: String = ""
	if "scene_file_path" in target_node and not str(target_node.get("scene_file_path")).empty():
		path = str(target_node.get("scene_file_path"))
	elif target_node.filename != "":
		path = target_node.filename
	elif filename != "":
		path = filename

	if path.empty():
		path = String(target_node.get_path())

	return "holoterminal:" + path

func widget_snapshot() -> Dictionary:
	var terminal = _get_terminal()
	var is_active_val: bool = false
	var is_focused_val: bool = false
	var pos_array: Array = [0.0, 0.0, 0.0]
	var title_val: String = screen_title()
	var status_text_val: String = "ESTADO: OPERATIVO"

	if is_instance_valid(terminal):
		if terminal.has_method("get_is_open"):
			is_active_val = terminal.get_is_open()
		elif "is_active" in terminal:
			is_active_val = bool(terminal.get("is_active"))

		if terminal.has_method("is_focused"):
			is_focused_val = terminal.is_focused()
		elif "_is_focused" in terminal:
			is_focused_val = bool(terminal.get("_is_focused"))

		if terminal is Spatial:
			var origin: Vector3 = (terminal as Spatial).global_transform.origin
			pos_array = [origin.x, origin.y, origin.z]

		if not is_active_val:
			status_text_val = "ESTADO: INACTIVO"
		elif is_focused_val:
			status_text_val = "MODO: FOCO ACTIVO"
		else:
			status_text_val = "DIAGNOSTICO: ONLINE"

	return {
		"proto": 1,
		"id": screen_id(),
		"title": title_val,
		"active": is_active_val,
		"focused": is_focused_val,
		"status_text": status_text_val,
		"position": pos_array,
		"source": "online"
	}

func view_scene() -> PackedScene:
	return null

func view_is_source() -> bool:
	return true

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance

	var proximity_boost: float = 0.0
	if context.has("player_position") and typeof(context["player_position"]) == TYPE_ARRAY and context["player_position"].size() >= 3:
		var px: float = float(context["player_position"][0])
		var py: float = float(context["player_position"][1])
		var pz: float = float(context["player_position"][2])
		var player_pos: Vector3 = Vector3(px, py, pz)

		var term_pos: Vector3 = Vector3.ZERO
		var terminal = _get_terminal()
		if is_instance_valid(terminal) and terminal is Spatial:
			term_pos = (terminal as Spatial).global_transform.origin
		elif is_inside_tree() and get_parent() is Spatial:
			term_pos = (get_parent() as Spatial).global_transform.origin

		var dist: float = term_pos.distance_to(player_pos)
		proximity_boost = clamp(1.0 - (dist / 15.0), 0.0, 1.0) * 0.5

	var focus_boost: float = 0.0
	if context.has("focus_id") and String(context["focus_id"]) == screen_id():
		focus_boost = 0.4

	return clamp(rel + proximity_boost + focus_boost, 0.0, 1.0)

func _get_terminal() -> Node:
	if not String(terminal_path).empty():
		var node = get_node_or_null(terminal_path)
		if is_instance_valid(node):
			return node
	var parent = get_parent()
	if is_instance_valid(parent):
		return parent
	return null
