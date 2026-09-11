extends Control
class_name SuitOSWidgetHost

# SuitOSWidgetHost.gd - Widget Host component for OdiseaOS (FD-296 F1.5)
# Listens to SuitOS.widget_changed(slot, snapshot) and mounts/updates widget overlays
# via OverlayUIManager without creating its own CanvasLayer.

var _active_screen_ids: Dictionary = {} # slot -> screen_id

func _ready() -> void:
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if not suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
			suit_os.connect("widget_changed", self, "_on_widget_changed")

		_on_widget_changed("slot_a", suit_os.get_slot_snapshot("slot_a"))
		_on_widget_changed("slot_b", suit_os.get_slot_snapshot("slot_b"))

func _exit_tree() -> void:
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
			suit_os.disconnect("widget_changed", self, "_on_widget_changed")

	_remove_overlay_for_slot("slot_a")
	_remove_overlay_for_slot("slot_b")

func _on_widget_changed(slot: String, snapshot: Dictionary) -> void:
	var overlay_mgr = get_node_or_null("/root/OverlayUIManager")
	if overlay_mgr == null:
		return

	var overlay_name: String = "SuitOS_Widget_" + slot
	var screen_id: String = String(snapshot.get("id", ""))

	if snapshot.empty() or screen_id.empty():
		_remove_overlay_for_slot(slot)
		return

	var prev_screen_id: String = String(_active_screen_ids.get(slot, ""))

	if screen_id == prev_screen_id and not prev_screen_id.empty():
		var slot_node = overlay_mgr.get_slot(overlay_mgr.SLOT_HUD)
		if is_instance_valid(slot_node):
			var existing = slot_node.get_node_or_null(overlay_name)
			if is_instance_valid(existing) and not existing.is_queued_for_deletion():
				if existing.has_method("update_snapshot"):
					existing.update_snapshot(snapshot)
				elif existing.has_method("set_snapshot"):
					existing.set_snapshot(snapshot)
				elif existing is Label:
					(existing as Label).text = _format_fallback_text(snapshot)
				return

	_remove_overlay_for_slot(slot)

	var widget_scene: PackedScene = null
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.has_screen(screen_id):
			var screen = suit_os.get_screen(screen_id)
			if is_instance_valid(screen):
				if screen.has_method("widget_scene"):
					widget_scene = screen.widget_scene()

	_active_screen_ids[slot] = screen_id

	if widget_scene != null:
		var overlay = overlay_mgr.ensure_overlay(overlay_name, widget_scene, overlay_mgr.SLOT_HUD)
		if is_instance_valid(overlay):
			if overlay.has_method("update_snapshot"):
				overlay.update_snapshot(snapshot)
			elif overlay.has_method("set_snapshot"):
				overlay.set_snapshot(snapshot)
	else:
		var slot_hud = overlay_mgr.get_slot(overlay_mgr.SLOT_HUD)
		if is_instance_valid(slot_hud):
			var label := Label.new()
			label.name = overlay_name
			label.text = _format_fallback_text(snapshot)
			slot_hud.add_child(label)

func _remove_overlay_for_slot(slot: String) -> void:
	var overlay_mgr = get_node_or_null("/root/OverlayUIManager")
	var overlay_name: String = "SuitOS_Widget_" + slot
	if overlay_mgr != null:
		overlay_mgr.remove_overlay(overlay_name, overlay_mgr.SLOT_HUD)
		var slot_hud = overlay_mgr.get_slot(overlay_mgr.SLOT_HUD)
		if is_instance_valid(slot_hud):
			var fallback_node = slot_hud.get_node_or_null(overlay_name)
			if is_instance_valid(fallback_node):
				fallback_node.queue_free()
	_active_screen_ids.erase(slot)

func _format_fallback_text(snapshot: Dictionary) -> String:
	var title: String = String(snapshot.get("title", snapshot.get("id", "Unknown Screen")))
	var source: String = String(snapshot.get("source", "online"))
	var active_str: String = "ACTIVE" if bool(snapshot.get("active", false)) else "INACTIVE"
	var focus_str: String = " (FOCUSED)" if bool(snapshot.get("focused", false)) else ""

	if source == "offline":
		return "[OFFLINE] %s: %s%s" % [title, active_str, focus_str]
	return "[HUD] %s: %s%s" % [title, active_str, focus_str]
