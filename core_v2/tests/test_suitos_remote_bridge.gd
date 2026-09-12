extends GdUnitTestSuite

# test_suitos_remote_bridge.gd - Tests for SuitOSRemoteBridge (FD-296 F4)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const SuitOSRemoteBridgeScript = preload("res://core_v2/components/SuitOSRemoteBridge.gd")

class DummyServer extends Node:
	var last_directives: Array = []
	func send_ui_directive(op: String, payload) -> void:
		last_directives.append({"op": op, "payload": payload})

func test_bridge_sends_screen_list_on_client_connected():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	# Register a dummy screen in SuitOS
	var dummy_screen = auto_free(HUDableComponentScript.new())
	dummy_screen.hud_screen_id = "test_screen_1"
	dummy_screen.hud_screen_title = "Test Screen 1"
	dummy_screen.default_relevance = 0.8
	SuitOS.register_screen(dummy_screen)

	server.last_directives.clear()
	bridge._on_client_connected("Phone 1")

	assert_int(server.last_directives.size()).is_greater_equal(1)
	var list_directive = server.last_directives[0]
	assert_str(list_directive["op"]).is_equal("screen_list")
	assert_bool(list_directive["payload"] is Array).is_true()

	var screens: Array = list_directive["payload"]
	var found: bool = false
	for s in screens:
		if String(s.get("id", "")) == "test_screen_1":
			found = true
			assert_str(String(s.get("title", ""))).is_equal("Test Screen 1")
			assert_float(float(s.get("relevance", 0.0))).is_equal(0.8)

	assert_bool(found).is_true()

	SuitOS.unregister_screen("test_screen_1")
	bridge.queue_free()
	server.queue_free()

func test_bridge_sends_screen_list_on_screen_registration_change():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	server.last_directives.clear()

	var dummy_screen = auto_free(HUDableComponentScript.new())
	dummy_screen.hud_screen_id = "test_screen_reg"
	dummy_screen.hud_screen_title = "Screen Registration"
	SuitOS.register_screen(dummy_screen)

	assert_int(server.last_directives.size()).is_greater_equal(1)
	var last = server.last_directives.back()
	assert_str(last["op"]).is_equal("screen_list")

	server.last_directives.clear()
	SuitOS.unregister_screen("test_screen_reg")

	assert_int(server.last_directives.size()).is_greater_equal(1)
	last = server.last_directives.back()
	assert_str(last["op"]).is_equal("screen_list")

	bridge.queue_free()
	server.queue_free()

func test_bridge_sends_haptic_directive():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	server.last_directives.clear()
	SuitOS.trigger_haptic("heavy", 0.75)

	assert_int(server.last_directives.size()).is_equal(1)
	var haptic_dir = server.last_directives[0]
	assert_str(haptic_dir["op"]).is_equal("haptic")
	assert_str(String(haptic_dir["payload"].get("kind", ""))).is_equal("heavy")
	assert_float(float(haptic_dir["payload"].get("intensity", 0.0))).is_equal(0.75)

	bridge.queue_free()
	server.queue_free()

func test_bridge_sends_widget_scene_and_snapshot_in_screen_list():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	# El control remoto no tiene la pantalla registrada: sin la escena del widget y su
	# snapshot mostraba la ruta cruda como nombre y "EN ESPERA" como estado.
	var dummy_screen = auto_free(HUDableComponentScript.new())
	dummy_screen.hud_screen_id = "test_screen_widget"
	dummy_screen.hud_screen_title = "Linterna"
	dummy_screen.hud_widget_scene = load("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
	SuitOS.register_screen(dummy_screen)

	server.last_directives.clear()
	bridge._on_client_connected("Phone 1")

	var entry: Dictionary = {}
	for s in server.last_directives[0]["payload"]:
		if String(s.get("id", "")) == "test_screen_widget":
			entry = s
	assert_bool(entry.empty()).is_false()
	assert_str(String(entry.get("widget", ""))).is_equal("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
	assert_bool(entry.get("snapshot") is Dictionary).is_true()
	assert_str(String(entry["snapshot"].get("title", ""))).is_equal("Linterna")

	SuitOS.unregister_screen("test_screen_widget")
	bridge.queue_free()
	server.queue_free()

class DummyViewScreen extends HUDableComponent:
	func view_size() -> Vector2:
		return Vector2(1280.0, 816.0)

func test_screen_active_carries_the_view_scene_and_its_design_size():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	var screen = auto_free(DummyViewScreen.new())
	screen.hud_screen_id = "holoterminal:cryo"
	screen.hud_screen_title = "Diagnostico de criogenia"
	screen.hud_view_scene = load("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
	SuitOS.register_screen(screen)

	server.last_directives.clear()
	bridge.set_remote_active_screen("holoterminal:cryo")

	var active: Dictionary = {}
	for d in server.last_directives:
		if String(d["op"]) == "screen_active":
			active = d["payload"]
	assert_bool(active.empty()).is_false()
	assert_str(String(active.get("view", ""))).is_equal("scene")
	assert_str(String(active.get("view_scene", ""))).is_equal("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
	assert_array(active.get("view_size", [])).is_equal([1280.0, 816.0])

	SuitOS.unregister_screen("holoterminal:cryo")
	bridge.queue_free()
	server.queue_free()
