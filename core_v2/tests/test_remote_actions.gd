extends GdUnitTestSuite

# test_remote_actions.gd - Tests for remote_action validation and execution (FD-296 F4)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const SuitOSRemoteBridgeScript = preload("res://core_v2/components/SuitOSRemoteBridge.gd")

class DummyActionScreen extends HUDableComponent:
	var action_executed: bool = false
	var last_op: String = ""
	var last_args: Dictionary = {}

	func screen_id() -> String:
		return "dummy_action_screen"

	func allowed_actions() -> Array:
		return ["toggle_power", "set_level"]

	func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
		action_executed = true
		last_op = op
		last_args = args.duplicate(true)
		return {"ok": true, "result": "success"}

class DummyServer extends Node:
	var last_directives: Array = []
	func send_ui_directive(op: String, payload) -> void:
		last_directives.append({"op": op, "payload": payload})

func test_remote_action_validation_and_execution():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	var screen = auto_free(DummyActionScreen.new())
	SuitOS.register_screen(screen)

	# Execute valid remote action
	bridge._on_ui_directive_received("remote_action", {
		"screen_id": "dummy_action_screen",
		"op": "toggle_power",
		"args": {"power": true}
	})

	assert_bool(screen.action_executed).is_true()
	assert_str(screen.last_op).is_equal("toggle_power")
	assert_bool(bool(screen.last_args.get("power", false))).is_true()

	# Attempt disallowed remote action
	screen.action_executed = false
	bridge._on_ui_directive_received("remote_action", {
		"screen_id": "dummy_action_screen",
		"op": "hack_system",
		"args": {}
	})

	assert_bool(screen.action_executed).is_false()

	SuitOS.unregister_screen("dummy_action_screen")
	bridge.queue_free()
	server.queue_free()

func test_screen_select_directive_updates_remote_active_screen():
	var server = DummyServer.new()
	add_child(server)

	var bridge = SuitOSRemoteBridgeScript.new()
	add_child(bridge)
	bridge.set("server", server)

	var screen = auto_free(DummyActionScreen.new())
	SuitOS.register_screen(screen)

	server.last_directives.clear()
	bridge._on_ui_directive_received("screen_select", {"id": "dummy_action_screen"})

	assert_str(bridge.get_remote_active_screen_id()).is_equal("dummy_action_screen")
	assert_int(server.last_directives.size()).is_greater_equal(1)

	var active_dir = server.last_directives.back()
	assert_str(active_dir["op"]).is_equal("screen_active")
	assert_str(String(active_dir["payload"].get("id", ""))).is_equal("dummy_action_screen")

	SuitOS.unregister_screen("dummy_action_screen")
	bridge.queue_free()
	server.queue_free()
