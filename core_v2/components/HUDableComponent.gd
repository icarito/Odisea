extends Node
class_name HUDableComponent

# HUDableComponent.gd - Component that declares a screen/widget source for OdiseaOS (FD-296)
# Registers with SuitOS on entering tree and unregisters on exit.

export(PackedScene) var hud_view_scene = null
export(PackedScene) var hud_widget_scene = null
export(String) var hud_screen_id = ""
export(String) var hud_screen_title = ""
export(Texture) var hud_screen_icon = null
export(float) var default_relevance = 0.0
export(Array, String) var allowed_actions = []

signal state_changed()

func _enter_tree() -> void:
	_register_to_suit_os()

func _ready() -> void:
	_register_to_suit_os()

func _exit_tree() -> void:
	_unregister_from_suit_os()

func screen_id() -> String:
	if not hud_screen_id.empty():
		return hud_screen_id
	return get_name()

func screen_title() -> String:
	if not hud_screen_title.empty():
		return hud_screen_title
	return screen_id()

func screen_icon() -> Texture:
	return hud_screen_icon

func view_scene() -> PackedScene:
	return hud_view_scene

func widget_scene() -> PackedScene:
	return hud_widget_scene

func relevance(context: Dictionary = {}) -> float:
	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("get_hud_relevance"):
		return float(parent.get_hud_relevance(context))
	return default_relevance

func allowed_actions() -> Array:
	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("get_hud_allowed_actions"):
		return parent.get_hud_allowed_actions()
	return allowed_actions

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("perform_hud_action"):
		return parent.perform_hud_action(op, args)

	if op in allowed_actions:
		return {"ok": true, "result": "action_executed"}
	return {"ok": false, "error": "Action '%s' not supported" % op}

func widget_snapshot() -> Dictionary:
	var parent = get_parent()
	if is_instance_valid(parent) and parent.has_method("get_hud_snapshot"):
		var parent_snap = parent.get_hud_snapshot()
		if typeof(parent_snap) == TYPE_DICTIONARY:
			if not parent_snap.has("proto"):
				parent_snap["proto"] = 1
			if not parent_snap.has("id"):
				parent_snap["id"] = screen_id()
			return parent_snap

	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"source": "online"
	}

func notify_state_changed() -> void:
	emit_signal("state_changed")

func _register_to_suit_os() -> void:
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.has_method("register_screen"):
			suit_os.register_screen(self)

func _unregister_from_suit_os() -> void:
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.has_method("unregister_screen"):
			suit_os.unregister_screen(screen_id())
