extends GdUnitTestSuite

# RemoteHudBackend: el contrato de SuitOS que usa el HUD compartido, alimentado por el canal.

const BackendScript = preload("res://core_v2/ui/hud/RemoteHudBackend.gd")
const PINS_PATH := "user://test_remote_hud.cfg"


class FakeHome extends Node:
	var actions: Array = []
	var selects: Array = []
	func send_remote_action(screen_id: String, op: String, _args: Dictionary = {}) -> void:
		actions.append([screen_id, op])
	func select_remote_screen(id: String) -> void:
		selects.append(id)


func _backend(persist: bool = false) -> Node:
	var backend = BackendScript.new()
	backend.persist = persist
	backend.pins_path = PINS_PATH
	var home = auto_free(FakeHome.new())
	add_child(home)
	backend.home = home
	home.add_child(backend)
	return backend


func after_test() -> void:
	Directory.new().remove(PINS_PATH)


func test_screens_come_from_the_channel_with_their_widget_and_state() -> void:
	var backend = _backend()
	var registered: Array = []
	var unregistered: Array = []
	backend.connect("screen_registered", self, "_append", [registered])
	backend.connect("screen_unregistered", self, "_append", [unregistered])

	backend.apply_screen_list([{"id": "player:flashlight", "title": "Linterna",
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn", "snapshot": {"on": false}}])
	assert_array(registered).is_equal(["player:flashlight"])
	var screen = backend.get_screen("player:flashlight")
	assert_str(screen.screen_title()).is_equal("Linterna")
	assert_object(screen.widget_scene()).is_not_null()
	assert_str(String(backend.get_slot_snapshot("slot_1").get("source"))).is_equal("online")

	# screen_data refresca el widget del slot y avisa a quien muestra la pantalla ampliada.
	var changed: Array = []
	screen.connect("state_changed", self, "_append", ["x", changed])
	backend.apply_screen_data("player:flashlight", {"on": true})
	assert_bool(bool(backend.get_slot_snapshot("slot_1").get("on"))).is_true()
	assert_int(changed.size()).is_equal(1)

	backend.apply_screen_list([])
	assert_array(unregistered).is_equal(["player:flashlight"])
	assert_str(String(backend.get_slot_snapshot("slot_1").get("source"))).is_equal("offline")


func test_actions_and_selection_travel_through_the_remote_home() -> void:
	var backend = _backend()
	backend.apply_screen_list([{"id": "screen_a", "title": "A"}])
	backend.perform_action("screen_a", "toggle")
	assert_array(backend.home.actions).is_equal([["screen_a", "toggle"]])
	assert_bool(backend.open_screen("screen_a")).is_true()
	assert_bool(backend.open_screen("missing")).is_false()
	assert_array(backend.home.selects).is_equal(["screen_a"])


func test_phone_slots_default_to_the_flashlight_and_persist() -> void:
	var backend = _backend(true)
	assert_array(backend.get_pinned_slots()).is_equal(["player:flashlight", "", "", ""])
	backend.pin_to_slot(2, "screen_a")
	backend.move_slot(0, 3)
	assert_array(backend.get_pinned_slots()).is_equal(["", "", "screen_a", "player:flashlight"])

	var again = _backend(true)
	assert_array(again.get_pinned_slots()).is_equal(["", "", "screen_a", "player:flashlight"])


func _append(value, into: Array) -> void:
	into.append(value)
