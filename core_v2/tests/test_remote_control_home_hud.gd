extends GdUnitTestSuite

# test_remote_control_home_hud.gd - Tests for RemoteControlHome HUD UI client (FD-296 F4)

var RemoteControlHomeScene = load("res://core_v2/ui/RemoteControlHome.tscn")

func test_remote_home_instantiates_slot_widgets():
	var home = RemoteControlHomeScene.instance()
	add_child(home)

	var screen_list = [
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.2}
	]

	home._on_ui_directive("screen_list", screen_list)

	# Slot A should mount screen_a (highest relevance)
	assert_bool(home._mounted_widgets.has("slot_a")).is_true()
	var widget_a = home._mounted_widgets["slot_a"]
	assert_object(widget_a).is_not_null()
	assert_str(home._get_node_screen_id(widget_a)).is_equal("screen_a")

	home.queue_free()

func test_remote_home_pin_local_screen():
	var home = RemoteControlHomeScene.instance()
	add_child(home)

	var screen_list = [
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.2}
	]

	home._on_ui_directive("screen_list", screen_list)
	home.pin_local_screen("screen_b")

	# Slot B should mount screen_b
	assert_bool(home._mounted_widgets.has("slot_b")).is_true()
	var widget_b = home._mounted_widgets["slot_b"]
	assert_object(widget_b).is_not_null()
	assert_str(home._get_node_screen_id(widget_b)).is_equal("screen_b")

	home.queue_free()

func test_remote_home_fullscreen_view_mounting():
	var home = RemoteControlHomeScene.instance()
	add_child(home)

	var active_payload = {
		"id": "screen_active_1",
		"title": "Active Screen 1",
		"view": "widget",
		"snapshot": {"proto": 1, "id": "screen_active_1", "status_text": "OPERATIONAL"}
	}

	home._on_ui_directive("screen_active", active_payload)

	assert_bool(home.fullscreen_overlay.visible).is_true()
	assert_object(home._fullscreen_view_node).is_not_null()
	assert_str(home._get_node_screen_id(home._fullscreen_view_node)).is_equal("screen_active_1")

	# Sending empty screen_active closes view
	home._on_ui_directive("screen_active", {"id": "", "title": "", "view": "widget", "snapshot": {}})
	assert_bool(home.fullscreen_overlay.visible).is_false()
	assert_object(home._fullscreen_view_node).is_null()

	home.queue_free()
