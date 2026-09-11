extends GdUnitTestSuite

# test_suitos_widget_host.gd - Integration tests for SuitOSWidgetHost and HangingDisplay (FD-296 F1.5)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const SuitOSWidgetHostScript = preload("res://core_v2/ui/hud/SuitOSWidgetHost.gd")

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

	# Pin to Slot B
	SuitOS.pin_screen(screen_id)
	var slot_b_snap: Dictionary = SuitOS.get_slot_snapshot("slot_b")
	assert_str(String(slot_b_snap.get("id", ""))).is_equal(screen_id)

	var slot_hud = _overlay_mgr.get_slot(_overlay_mgr.SLOT_HUD)
	var widget_b = slot_hud.get_node_or_null("SuitOS_Widget_slot_b")
	assert_object(widget_b).is_not_null()

	SuitOS.unpin_screen()
