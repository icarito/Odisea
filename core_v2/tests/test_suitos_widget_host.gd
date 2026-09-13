extends GdUnitTestSuite

# test_suitos_widget_host.gd - Integration tests for SuitOSWidgetHost, HangingDisplay, and auto-mounting (FD-296 F1.5)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const SuitOSWidgetHostScript = preload("res://core_v2/ui/hud/SuitOSWidgetHost.gd")
const HoloTerminalWidgetScript = preload("res://core_v2/ui/hud/HoloTerminalWidget.gd")

var _widget_host: Node = null
var _overlay_mgr = null

func before() -> void:
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)

func before_test() -> void:
	var root = get_tree().root
	_overlay_mgr = root.get_node_or_null("OverlayUIManager")
	if _overlay_mgr == null:
		_overlay_mgr = OverlayUIManager.new()
		_overlay_mgr.name = "OverlayUIManager"
		root.add_child(_overlay_mgr)

	_widget_host = SuitOSWidgetHostScript.new()
	_widget_host.name = "SuitOSWidgetHost"
	root.add_child(_widget_host)

func after_test() -> void:
	if is_instance_valid(_widget_host):
		_widget_host.free()

func test_suitos_auto_mounts_driver_and_widget_host() -> void:
	assert_object(SuitOS.get_node_or_null("SuitOSContextDriver")).is_not_null()
	assert_object(SuitOS.get_node_or_null("SuitOSWidgetHost")).is_not_null()

func test_widget_changed_mounts_and_unmounts_overlay() -> void:
	var dummy_screen = auto_free(HUDableComponentScript.new())
	dummy_screen.hud_screen_id = "test:dummy_screen"
	dummy_screen.hud_screen_title = "Dummy Screen Title"
	dummy_screen.default_relevance = 0.9
	add_child(dummy_screen)

	SuitOS.register_screen(dummy_screen)
	SuitOS.set_context({"player_position": [0, 0, 0]})

	var slot_hud = _overlay_mgr.get_slot(_overlay_mgr.SLOT_HUD)
	assert_object(slot_hud).is_not_null()

	var overlay_node = slot_hud.get_node_or_null("SuitOS_Widget_slot_a")
	assert_object(overlay_node).is_not_null()
	assert_bool(overlay_node is Label).is_true()
	assert_str((overlay_node as Label).text).contains("Dummy Screen Title")

	# Unregister -> empty snapshot -> remove_overlay
	SuitOS.unregister_screen(dummy_screen)
	yield(get_tree(), "idle_frame")

	var freed_node = slot_hud.get_node_or_null("SuitOS_Widget_slot_a")
	assert_bool(freed_node == null or freed_node.is_queued_for_deletion()).is_true()

func test_hanging_display_registration_and_slot_flow() -> void:
	var hanging_display_scene = load("res://core_v2/levels/interiors/DomeIntroCryoDiagnosticsDisplay.tscn")
	assert_object(hanging_display_scene).is_not_null()

	var display_inst = auto_free(hanging_display_scene.instance())
	assert_object(display_inst).is_not_null()
	display_inst.translation = Vector3(1.0, 2.0, 3.0)
	add_child(display_inst)

	var hudable_comp = display_inst.get_node_or_null("HoloTerminalHUDable")
	assert_object(hudable_comp).is_not_null()

	var screen_id: String = hudable_comp.screen_id()
	assert_bool(SuitOS.has_screen(screen_id)).is_true()

	# Move context close to HangingDisplay so Slot A picks it
	SuitOS.set_context({"player_position": [1.0, 2.0, 3.0]})

	var slot_a_snap: Dictionary = SuitOS.get_slot_snapshot("slot_a")
	assert_str(String(slot_a_snap.get("id", ""))).is_equal(screen_id)

	var slot_hud = _overlay_mgr.get_slot(_overlay_mgr.SLOT_HUD)
	var widget_a = slot_hud.get_node_or_null("SuitOS_Widget_slot_a")
	assert_object(widget_a).is_not_null()
	assert_object(widget_a.get_script()).is_equal(HoloTerminalWidgetScript)

	# Pin to Slot B
	SuitOS.pin_screen(screen_id)
	var slot_b_snap: Dictionary = SuitOS.get_slot_snapshot("slot_b")
	assert_str(String(slot_b_snap.get("id", ""))).is_equal(screen_id)

	var widget_b = slot_hud.get_node_or_null("SuitOS_Widget_slot_b")
	assert_object(widget_b).is_not_null()
	assert_object(widget_b.get_script()).is_equal(HoloTerminalWidgetScript)

	SuitOS.unpin_screen()

# Slot A y Slot B tienen filas fijas en la misma esquina: no se pisan, y B no se mueve si A
# queda vacio (el layout no depende de cuantos slots haya).
func test_slots_stack_in_fixed_rows_without_overlap() -> void:
	var auto_screen = auto_free(HUDableComponentScript.new())
	auto_screen.hud_screen_id = "test:auto"
	auto_screen.default_relevance = 0.9
	auto_screen.hud_widget_scene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
	add_child(auto_screen)
	var pinned_screen = auto_free(HUDableComponentScript.new())
	pinned_screen.hud_screen_id = "test:pinned"
	pinned_screen.hud_widget_scene = preload("res://core_v2/ui/hud/SystemStatusWidget.tscn")
	add_child(pinned_screen)
	SuitOS.set_context({})
	SuitOS.pin_screen("test:pinned")

	var slot_hud = _overlay_mgr.get_slot(_overlay_mgr.SLOT_HUD)
	var widget_a: Control = slot_hud.get_node("SuitOS_Widget_slot_a")
	var widget_b: Control = slot_hud.get_node("SuitOS_Widget_slot_b")
	var rect_a := Rect2(widget_a.rect_position, widget_a.rect_size * widget_a.rect_scale)
	var rect_b := Rect2(widget_b.rect_position, widget_b.rect_size * widget_b.rect_scale)
	assert_bool(rect_a.intersects(rect_b)).override_failure_message("A %s pisa a B %s" % [rect_a, rect_b]).is_false()
	assert_float(widget_a.rect_position.x).is_equal(widget_b.rect_position.x)
	assert_bool(rect_b.position.y > rect_a.position.y).is_true()

	var b_position: Vector2 = widget_b.rect_position
	SuitOS.unregister_screen(auto_screen) # Slot A vacio
	yield(await_idle_frame(), "completed")
	assert_vector2(slot_hud.get_node("SuitOS_Widget_slot_b").rect_position).is_equal(b_position)

	SuitOS.unpin_screen()
	SuitOS.unregister_screen(pinned_screen)


func test_widget_buttons_stay_pressable_and_their_touch_does_not_open_hud_mode():
	# Como en el control remoto: el toggle de la linterna se oprime con clic o dedo, y ese toque
	# no abre la pantalla (en Godot 3 un ScreenTouch sube por encima de un control STOP).
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget: Control = auto_free(load("res://core_v2/ui/hud/FlashlightWidget.tscn").instance())
	add_child(widget)
	host._make_tappable(widget, "slot_b")
	var toggle: Control = widget.get_node("Margin/VBox/StatusRow/ToggleButton")
	assert_int(toggle.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(widget.get_node("Margin/VBox/StatusRow/StatusLabel").mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	yield(await_idle_frame(), "completed")

	var xf: Transform2D = toggle.get_global_transform_with_canvas()
	var on_button: Vector2 = xf.origin + toggle.rect_size * xf.get_scale() * 0.5
	var touch := InputEventScreenTouch.new()
	touch.position = on_button
	touch.pressed = true
	host._input(touch)
	host._on_widget_gui_input(touch, widget, "slot_b")
	touch = touch.duplicate()
	touch.pressed = false
	host._on_widget_gui_input(touch, widget, "slot_b")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
