extends GdUnitTestSuite

# test_suit_os.gd - Tests for SuitOS core autoload (FD-296 F1)

class DummyScreen:
	extends Node
	signal state_changed()

	var _id: String
	var _title: String
	var _relevance_val: float
	var _allowed: Array
	var internal_dict: Dictionary = {"custom_field": "initial"}
	var action_executed: bool = false
	var last_action_op: String = ""
	var last_action_args: Dictionary = {}

	func _init(id: String, title: String = "Test", relevance_val: float = 0.5, allowed: Array = ["toggle", "reset"]).():
		_id = id
		_title = title
		_relevance_val = relevance_val
		_allowed = allowed

	func screen_id() -> String:
		return _id

	func screen_title() -> String:
		return _title

	func screen_icon() -> Texture:
		return null

	func relevance(context: Dictionary = {}) -> float:
		if context.has(_id + "_relevance"):
			return float(context[_id + "_relevance"])
		return _relevance_val

	func allowed_actions() -> Array:
		return _allowed

	func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
		if op in _allowed:
			action_executed = true
			last_action_op = op
			last_action_args = args
			return {"ok": true, "result": "done", "op": op}
		return {"ok": false, "error": "Invalid action"}

	func widget_snapshot() -> Dictionary:
		internal_dict["proto"] = 1
		internal_dict["id"] = _id
		internal_dict["title"] = _title
		internal_dict["relevance"] = _relevance_val
		return internal_dict

	func trigger_state_change() -> void:
		emit_signal("state_changed")

var _received_haptic: Array = []

func before_test() -> void:
	_received_haptic.clear()
	SuitOS.clear_slots()
	SuitOS.close_screen()
	SuitOS.set_hud_mode_active(false)
	SuitOS.set_context({})
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

func test_screen_registration_and_unregistration() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen One", 0.3))

	assert_bool(SuitOS.has_screen("screen_1")).is_false()
	SuitOS.register_screen(screen1)
	assert_bool(SuitOS.has_screen("screen_1")).is_true()
	assert_array(SuitOS.get_registered_screens()).contains(["screen_1"])

	SuitOS.unregister_screen("screen_1")
	assert_bool(SuitOS.has_screen("screen_1")).is_false()

func test_idempotent_registration() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen One", 0.3))
	SuitOS.register_screen(screen1)
	SuitOS.register_screen(screen1)

	assert_bool(SuitOS.has_screen("screen_1")).is_true()
	assert_int(SuitOS.get_registered_screens().size()).is_equal(1)

func test_no_screen_is_ever_auto_assigned_to_a_slot() -> void:
	# Ni por relevancia ni al cambiar el contexto: solo el jugador llena un slot.
	var top: DummyScreen = auto_free(DummyScreen.new("screen_top", "Top", 0.9))
	var second: DummyScreen = auto_free(DummyScreen.new("screen_second", "Second", 0.5))
	SuitOS.register_screen(top)
	SuitOS.register_screen(second)
	SuitOS.update_context_key("screen_second_relevance", 0.95)
	for i in range(4):
		assert_bool(SuitOS.get_slot_snapshot("slot_%d" % (i + 1)).empty()).is_true()
	# Vaciar o mover tampoco llena el slot que quedo libre.
	SuitOS.pin_to_slot(0, "screen_second")
	SuitOS.move_slot(0, 2)
	assert_bool(SuitOS.get_slot_snapshot("slot_1").empty()).is_true()
	SuitOS.clear_slot(2)
	for i in range(4):
		assert_str(SuitOS.slot_screen_id(i)).is_empty()

func test_pinned_slot_and_offline_fallback() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.5))
	SuitOS.register_screen(screen1)

	SuitOS.pin_to_slot(2, "screen_1")
	var slot_3 = SuitOS.get_slot_snapshot("slot_3")
	assert_str(slot_3.get("id", "")).is_equal("screen_1")
	assert_str(slot_3.get("source", "")).is_equal("online")

	# Unregister screen -> the slot keeps the last snapshot marked offline
	SuitOS.unregister_screen("screen_1")
	slot_3 = SuitOS.get_slot_snapshot("slot_3")
	assert_str(slot_3.get("id", "")).is_equal("screen_1")
	assert_str(slot_3.get("source", "")).is_equal("offline")

	# Clear -> empty
	SuitOS.clear_slot(2)
	assert_bool(SuitOS.get_slot_snapshot("slot_3").empty()).is_true()

func test_pin_to_slot_moves_the_screen_instead_of_duplicating_it() -> void:
	SuitOS.pin_to_slot(0, "a")
	SuitOS.pin_to_slot(3, "a")
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", "a"])

func test_action_gate_and_validation() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.5, ["toggle"]))
	SuitOS.register_screen(screen1)

	# Allowed action
	var res1 = SuitOS.perform_action("screen_1", "toggle", {"power": 100})
	assert_bool(res1.get("ok", false)).is_true()
	assert_bool(screen1.action_executed).is_true()
	assert_str(screen1.last_action_op).is_equal("toggle")

	# Forbidden action
	var res2 = SuitOS.perform_action("screen_1", "unauthorized_op", {})
	assert_bool(res2.get("ok", true)).is_false()

	# Non-existent screen action
	var res3 = SuitOS.perform_action("unknown_screen", "toggle", {})
	assert_bool(res3.get("ok", true)).is_false()

func test_haptic_bus() -> void:
	SuitOS.connect("haptic", self, "_on_haptic_event")

	SuitOS.trigger_haptic("tremor", 0.85)

	assert_int(_received_haptic.size()).is_equal(1)
	assert_str(_received_haptic[0]["kind"]).is_equal("tremor")
	assert_float(_received_haptic[0]["intensity"]).is_equal(0.85)

	if SuitOS.is_connected("haptic", self, "_on_haptic_event"):
		SuitOS.disconnect("haptic", self, "_on_haptic_event")

func test_hud_mode_and_open_close_screen() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.5))
	SuitOS.register_screen(screen1)

	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	SuitOS.set_hud_mode_active(true)
	assert_bool(SuitOS.is_hud_mode_active()).is_true()

	assert_bool(SuitOS.open_screen("screen_1")).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("screen_1")

	SuitOS.close_screen()
	assert_str(SuitOS.get_active_screen_id()).is_empty()

func test_persistence_save_restore_preserves_pin_and_offline_source() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.5))
	SuitOS.register_screen(screen1)
	SuitOS.pin_to_slot(1, "screen_1")

	# Screen is registered -> the slot is online
	assert_str(SuitOS.get_slot_snapshot("slot_2").get("source", "")).is_equal("online")

	# Unregister screen1 -> the slot becomes offline
	SuitOS.unregister_screen("screen_1")
	assert_str(SuitOS.get_slot_snapshot("slot_2").get("source", "")).is_equal("offline")

	var saved_state = SuitOS.save_state()

	SuitOS.clear_slots()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])

	# Restore -> screen_1 back in slot 2, offline since it is not registered
	SuitOS.restore_state(saved_state)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "screen_1", "", ""])
	assert_str(SuitOS.get_slot_snapshot("slot_2").get("source", "")).is_equal("offline")

	# Re-register screen1 -> resolves back to online
	SuitOS.register_screen(screen1)
	assert_str(SuitOS.get_slot_snapshot("slot_2").get("source", "")).is_equal("online")

func test_restore_of_a_two_slot_save_puts_the_pin_in_slot_1() -> void:
	SuitOS.restore_state({"pinned_screen_id": "screen_old"})
	assert_array(SuitOS.get_pinned_slots()).is_equal(["screen_old", "", "", ""])

func test_snapshot_aliasing_prevention() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.7))
	SuitOS.register_screen(screen1)
	SuitOS.pin_to_slot(0, "screen_1")

	# Get slot snapshot and mutate it
	var snap = SuitOS.get_slot_snapshot("slot_1")
	snap["source"] = "MUTATED"
	snap["custom_field"] = "MUTATED_FIELD"

	# Re-fetch snapshot and verify source object internal_dict was not corrupted
	var snap_fresh = SuitOS.get_slot_snapshot("slot_1")
	assert_str(snap_fresh.get("source", "")).is_equal("online")
	assert_str(screen1.internal_dict.get("custom_field", "")).is_equal("initial")

func test_pre_scene_swap_closes_active_screen_and_resets_context() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.5))
	SuitOS.register_screen(screen1)
	SuitOS.open_screen("screen_1")
	SuitOS.set_context({"level": "cryo_01", "hazard": true})

	assert_str(SuitOS.get_active_screen_id()).is_equal("screen_1")
	assert_bool(SuitOS.get_context().empty()).is_false()

	# Trigger pre_scene_swap handler
	SuitOS._on_pre_scene_swap()

	# Active screen is closed, context is reset to empty, screen remains registered
	assert_str(SuitOS.get_active_screen_id()).is_empty()
	assert_bool(SuitOS.get_context().empty()).is_true()
	assert_bool(SuitOS.has_screen("screen_1")).is_true()

func _on_haptic_event(kind: String, intensity: float, _duration: float = 0.1) -> void:
	_received_haptic.append({"kind": kind, "intensity": intensity})

func test_move_slot_swaps_the_two_slots() -> void:
	SuitOS.pin_to_slot(0, "a")
	SuitOS.pin_to_slot(2, "b")
	SuitOS.move_slot(0, 2)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["b", "", "a", ""])
	SuitOS.move_slot(0, 3)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "a", "b"])
	# Un slot vacio no tiene nada que mover.
	SuitOS.move_slot(0, 1)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "a", "b"])

func test_a_fresh_hud_has_the_flashlight_in_slot_1() -> void:
	var fresh = auto_free(load("res://core_v2/autoloads/SuitOS.gd").new()) # sin arbol: no corre _ready
	assert_array(fresh.get_pinned_slots()).is_equal(["player:flashlight", "", "", ""])
	# clear_slots vacia todo, la linterna incluida.
	fresh.clear_slots()
	assert_array(fresh.get_pinned_slots()).is_equal(["", "", "", ""])
