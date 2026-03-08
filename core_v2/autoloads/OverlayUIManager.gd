extends CanvasLayer

const SLOT_PASSIVE := "Passive"
const SLOT_HUD := "HUD"
const SLOT_MODAL := "Modal"
const SLOT_ORDER := [SLOT_PASSIVE, SLOT_HUD, SLOT_MODAL]

var _slots := {}

func _ready() -> void:
	layer = 115
	pause_mode = Node.PAUSE_MODE_PROCESS
	_ensure_slots()

func get_slot(slot_name: String = SLOT_PASSIVE) -> Control:
	_ensure_slots()
	var key = slot_name if slot_name in SLOT_ORDER else SLOT_PASSIVE
	return _slots.get(key, null)

func ensure_overlay(node_name: String, scene: PackedScene, slot_name: String = SLOT_PASSIVE) -> Node:
	if node_name == "" or scene == null:
		return null
	var slot = get_slot(slot_name)
	if not is_instance_valid(slot):
		return null
	var existing = slot.get_node_or_null(node_name)
	if is_instance_valid(existing):
		return existing
	var instance = scene.instance()
	if not is_instance_valid(instance):
		return null
	instance.name = node_name
	slot.add_child(instance)
	return instance

func get_safe_margins(extra_padding: float = 0.0) -> Dictionary:
	var margins = {
		"left": 0.0,
		"top": 0.0,
		"right": 0.0,
		"bottom": 0.0
	}
	var viewport_rect = get_viewport().get_visible_rect()
	var viewport_size = viewport_rect.size

	if OS.has_method("get_window_safe_area"):
		var safe_area = OS.get_window_safe_area()
		if safe_area is Rect2 and viewport_size.x > 0.0 and viewport_size.y > 0.0:
			margins.left = max(margins.left, safe_area.position.x)
			margins.top = max(margins.top, safe_area.position.y)
			margins.right = max(margins.right, viewport_size.x - (safe_area.position.x + safe_area.size.x))
			margins.bottom = max(margins.bottom, viewport_size.y - (safe_area.position.y + safe_area.size.y))

	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui and mobile_ui.has_method("get_reserved_overlay_margins"):
		var mobile_margins = mobile_ui.get_reserved_overlay_margins()
		for key in margins.keys():
			margins[key] = max(float(margins.get(key, 0.0)), float(mobile_margins.get(key, 0.0)))

	var screen_effects = get_node_or_null("/root/ScreenEffectsManager")
	if screen_effects and screen_effects.has_method("get_safe_margins"):
		var screen_fx_margins = screen_effects.get_safe_margins()
		if typeof(screen_fx_margins) == TYPE_DICTIONARY:
			for key in margins.keys():
				margins[key] = max(float(margins.get(key, 0.0)), float(screen_fx_margins.get(key, 0.0)))

	if extra_padding > 0.0:
		for key in margins.keys():
			margins[key] = float(margins[key]) + extra_padding

	return margins

func _ensure_slots() -> void:
	for slot_name in SLOT_ORDER:
		if is_instance_valid(_slots.get(slot_name, null)):
			continue
		var slot := Control.new()
		slot.name = slot_name
		slot.anchor_right = 1.0
		slot.anchor_bottom = 1.0
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots[slot_name] = slot
