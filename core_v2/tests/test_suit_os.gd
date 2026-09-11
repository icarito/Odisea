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
	SuitOS.min_relevance_a = SuitOS.MIN_RELEVANCE_A
	SuitOS.unpin_screen()
	SuitOS.close_screen()
	SuitOS.set_hud_mode_active(false)
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

func test_automatic_slot_scoring_slot_a() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.2))
	var screen2: DummyScreen = auto_free(DummyScreen.new("screen_2", "Screen 2", 0.8))

	SuitOS.register_screen(screen1)
	SuitOS.register_screen(screen2)

	var slot_a = SuitOS.get_slot_snapshot("slot_a")
	assert_str(slot_a.get("id", "")).is_equal("screen_2")

	# Update context to make screen_1 more relevant
	SuitOS.update_context_key("screen_1_relevance", 0.95)

	slot_a = SuitOS.get_slot_snapshot("slot_a")
	assert_str(slot_a.get("id", "")).is_equal("screen_1")

func test_slot_a_relevance_threshold_zero_leaves_slot_empty() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("zero_rel_screen", "Zero Rel", 0.0))
	SuitOS.register_screen(screen1)

	# Relevance <= min_relevance_a (0.0) -> Slot A must be empty
	var slot_a = SuitOS.get_slot_snapshot("slot_a")
	assert_bool(slot_a.empty()).is_true()

	# Boost relevance > 0.0 -> Slot A populates
	SuitOS.update_context_key("zero_rel_screen_relevance", 0.5)
	slot_a = SuitOS.get_slot_snapshot("slot_a")
	assert_str(slot_a.get("id", "")).is_equal("zero_rel_screen")

func test_pinned_slot_b_and_offline_fallback() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.5))
	SuitOS.register_screen(screen1)

	SuitOS.pin_screen("screen_1")
	var slot_b = SuitOS.get_slot_snapshot("slot_b")
	assert_str(slot_b.get("id", "")).is_equal("screen_1")
	assert_str(slot_b.get("source", "")).is_equal("online")

	# Unregister screen -> slot B should keep last snapshot marked offline
	SuitOS.unregister_screen("screen_1")
	slot_b = SuitOS.get_slot_snapshot("slot_b")
	assert_str(slot_b.get("id", "")).is_equal("screen_1")
	assert_str(slot_b.get("source", "")).is_equal("offline")

	# Unpin -> slot B becomes empty
	SuitOS.unpin_screen()
	slot_b = SuitOS.get_slot_snapshot("slot_b")
	assert_bool(slot_b.empty()).is_true()

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
	SuitOS.pin_screen("screen_1")

	# Screen is registered -> Slot B is online
	assert_str(SuitOS.get_slot_snapshot("slot_b").get("source", "")).is_equal("online")

	# Unregister screen1 -> Slot B becomes offline
	SuitOS.unregister_screen("screen_1")
	assert_str(SuitOS.get_slot_snapshot("slot_b").get("source", "")).is_equal("offline")

	# Save state
	var saved_state = SuitOS.save_state()

	# Clear local pin
	SuitOS.unpin_screen()
	assert_str(SuitOS.get_pinned_screen_id()).is_empty()

	# Restore state -> should restore pinned screen_1 and set source to offline since screen_1 is not currently registered
	SuitOS.restore_state(saved_state)
	assert_str(SuitOS.get_pinned_screen_id()).is_equal("screen_1")
	assert_str(SuitOS.get_slot_snapshot("slot_b").get("source", "")).is_equal("offline")

	# Re-register screen1 -> Slot B should automatically resolve back to online
	SuitOS.register_screen(screen1)
	assert_str(SuitOS.get_slot_snapshot("slot_b").get("source", "")).is_equal("online")

func test_snapshot_aliasing_prevention() -> void:
	var screen1: DummyScreen = auto_free(DummyScreen.new("screen_1", "Screen 1", 0.7))
	SuitOS.register_screen(screen1)

	# Get slot snapshot and mutate it
	var snap = SuitOS.get_slot_snapshot("slot_a")
	snap["source"] = "MUTATED"
	snap["custom_field"] = "MUTATED_FIELD"

	# Re-fetch snapshot and verify source object internal_dict was not corrupted
	var snap_fresh = SuitOS.get_slot_snapshot("slot_a")
	assert_str(snap_fresh.get("source", "")).is_equal("online")
	assert_str(screen1.internal_dict.get("custom_field", "")).is_equal("initial")

func _on_haptic_event(kind: String, intensity: float) -> void:
	_received_haptic.append({"kind": kind, "intensity": intensity})
