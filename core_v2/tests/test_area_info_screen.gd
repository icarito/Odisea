# GdUnit3 test for AreaInfoScreen
extends GdUnitTestSuite

const AreaInfoScreenScene = preload("res://core_v2/props/signage/AreaInfoScreen.tscn")

func test_area_info_screen_instantiation():
	var screen = auto_free(AreaInfoScreenScene.instance())
	assert_object(screen).is_not_null()
	assert_str(screen.panel_title).is_equal("Information")

func test_info_overlay_setup():
	var overlay = auto_free(load("res://core_v2/props/signage/InfoOverlay.tscn").instance())
	add_child(overlay)
	
	var test_title = "Test Title"
	var test_body = "Test Body"
	overlay.setup(test_title, test_body, null, Color.red)
	
	assert_str(overlay.get_node("CenterContainer/Panel/VBox/Title").text).is_equal(test_title.to_upper())
	assert_str(overlay.get_node("CenterContainer/Panel/VBox/Scroll/Body").text).is_equal(test_body)
	assert_bool(overlay.get_node("CenterContainer/Panel/VBox/MapRect").visible).is_false()

func test_preset_colors():
	var screen = auto_free(AreaInfoScreenScene.instance())
	add_child(screen) # Need to be in tree for onready nodes
	
	screen.preset = 2 # Preset.DANGER
	screen._update_world_visuals()
	
	assert_object(screen.get_node("OmniLight").light_color).is_equal(Color(1.0, 0.2, 0.1))

func test_event_bus_signal_emitted():
	var screen = auto_free(AreaInfoScreenScene.instance())
	screen.panel_title = "Secret Intel"
	add_child(screen)
	
	var eb = get_node_or_null("/root/EventBus")
	if eb == null:
		# Fallback: create it if not present (headless may have issues with autoloads sometimes)
		eb = load("res://core_v2/EventBus.gd").new()
		eb.name = "EventBus"
		get_tree().root.add_child(eb)
		auto_free(eb)

	var spy_event_bus = spy(eb)
	
	# Simulate opening overlay
	screen._open_overlay()
	
	verify(spy_event_bus).emit_signal("info_screen_read", "Secret Intel")
	
	# Clean up overlay which was added to root
	for child in get_tree().root.get_children():
		if child.name.find("InfoOverlay") != -1:
			child.free()
