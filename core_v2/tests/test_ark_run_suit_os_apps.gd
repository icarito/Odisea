extends GdUnitTestSuite

# FD-324 — apps equipables/reubicables del Ark-Run: Propulsores (player:thrusters) en L2
# y Cuerda (player:rope) en R2, con Linterna (L1) y Autonavegador (R1).

const HudSlotGamepad = preload("res://core_v2/ui/hud/HudSlotGamepadV2.gd")
const Gesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const SuitOSHostScript = preload("res://core_v2/ui/suit_os/ArkRunSuitOSHost.gd")
const ThrustersWidgetScene = preload("res://core_v2/ui/suit_os/ArkRunThrustersWidget.tscn")
const RopeWidgetScene = preload("res://core_v2/ui/suit_os/ArkRunRopeWidget.tscn")
const EPS := 0.00001
const HOLD_GAMEPLAY_APPS := ["player:autonav", "player:thrusters", "player:rope"]
const SLOT_ACTIONS := ["slot_1", "slot_2", "slot_3", "slot_4"]

class FakeBackend extends Node:
	var slots: Dictionary = {}
	var opened: Array = []
	var hud: bool = false
	func slot_screen_id(slot: int) -> String:
		return String(slots.get(slot, ""))
	func has_screen(_id: String) -> bool:
		return false
	func get_screen(_id: String):
		return null
	func is_hud_mode_active() -> bool:
		return hud
	func get_widget_host() -> Node:
		return null
	func open_hud_mode(_radial: bool, _screen_id: String, slot: int) -> bool:
		opened.append(slot)
		return true
	func is_hold_gameplay_app(screen_id: String) -> bool:
		return screen_id in HOLD_GAMEPLAY_APPS

func before_test() -> void:
	_release()
	SuitOS.close_hud_mode(); SuitOS.close_screen(); SuitOS.set_context({})
	get_tree().paused = false
	SuitOS.clear_slots(); SuitOS.clear_favorites()
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.ensure_ark_run_apps(); SuitOS.apply_ark_run_default_pins()

func after_test() -> void:
	_release()
	SuitOS.clear_slots(); SuitOS.clear_favorites(); SuitOS.close_hud_mode()
	get_tree().paused = false
	yield(get_tree(), "idle_frame")

func _release() -> void:
	for action in SLOT_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)

func _sample(n: int) -> InputDataV2:
	var d := InputDataV2.new()
	d.hud_slot = n
	return d

func _make(app_id: String) -> Array:
	var backend = auto_free(FakeBackend.new())
	add_child(backend)
	backend.slots[2] = app_id
	var node = auto_free(HudSlotGamepad.new())
	node.backend = backend
	add_child(node)
	return [backend, node]

func _hold(node) -> void:
	for _i in range(Gesture.HOLD_TICKS):
		node.tick(_sample(3))

func test_registers_four_apps_in_default_slots_without_touching_global_pins() -> void:
	assert_bool(SuitOS.has_screen("player:thrusters")).is_true()
	assert_bool(SuitOS.has_screen("player:rope")).is_true()
	assert_array(SuitOS.ARK_RUN_DEFAULT_PINS).is_equal(
		["player:flashlight", "player:thrusters", "player:autonav", "player:rope"])
	assert_array(SuitOS.get_pinned_slots()).is_equal(
		["player:flashlight", "player:thrusters", "player:autonav", "player:rope"])
	# El default global del HUD no cambia: fuera del Ark-Run sólo nace la linterna.
	assert_array(SuitOS.DEFAULT_PINS).is_equal(["player:flashlight", "", "", ""])
	assert_int(SuitOS.thrusters_slot_index()).is_equal(1) # L2
	assert_int(SuitOS.rope_slot_index()).is_equal(3) # R2
	assert_str(SuitOS.slot_label_for_screen("player:flashlight")).is_equal("L1")
	assert_str(SuitOS.slot_label_for_screen("player:thrusters")).is_equal("L2")
	assert_str(SuitOS.slot_label_for_screen("player:autonav")).is_equal("R1")
	assert_str(SuitOS.slot_label_for_screen("player:rope")).is_equal("R2")
	for app in HOLD_GAMEPLAY_APPS:
		assert_bool(SuitOS.is_hold_gameplay_app(app)).is_true()
	assert_bool(SuitOS.is_hold_gameplay_app("player:flashlight")).is_false()

func test_relocation_follows_new_slot_for_helpers_and_labels() -> void:
	SuitOS.pin_screen_to_slot(0, "player:thrusters")
	assert_int(SuitOS.thrusters_slot_index()).is_equal(0)
	assert_str(SuitOS.slot_label_for_screen("player:thrusters")).is_equal("L1")
	assert_str(SuitOS.slot_label_for_screen("player:flashlight")).is_empty()
	SuitOS.pin_to_slot(2, "player:rope")
	assert_int(SuitOS.rope_slot_index()).is_equal(2)
	assert_str(SuitOS.slot_label_for_screen("player:rope")).is_equal("R1")
	# move_slot intercambia; los helpers siguen al slot nuevo de cada app.
	SuitOS.move_slot(0, 3)
	assert_int(SuitOS.thrusters_slot_index()).is_equal(3)
	assert_str(SuitOS.slot_label_for_screen("player:thrusters")).is_equal("R2")

func test_hold_gameplay_apps_do_not_open_the_radial() -> void:
	for app in HOLD_GAMEPLAY_APPS:
		var ctx: Array = _make(app)
		_hold(ctx[1])
		assert_array(ctx[0].opened).override_failure_message(
			"hold de %s no deberia abrir el radial" % app).is_empty()

func test_hold_normal_app_still_opens_the_radial() -> void:
	var ctx: Array = _make("player:flashlight")
	_hold(ctx[1])
	assert_array(ctx[0].opened).is_equal([2])

func test_thruster_and_rope_snapshots_render() -> void:
	var thrusters = SuitOS.get_screen("player:thrusters")
	thrusters.set_thruster_state(9.0, 18.0, true)
	var snap: Dictionary = thrusters.widget_snapshot()
	assert_dict(snap).contains_keys(["dv_ratio", "active", "remaining", "max", "state"])
	assert_float(float(snap["dv_ratio"])).is_equal_approx(0.5, EPS)
	assert_bool(bool(snap["active"])).is_true()
	assert_str(String(snap["state"])).is_equal("ACTIVE")
	var tw = auto_free(ThrustersWidgetScene.instance())
	add_child(tw)
	tw.update_snapshot(snap)
	assert_float(tw.get_node("Margin/VBox/DeltaBar").value).is_equal_approx(50.0, 0.01)
	assert_str(tw.get_node("Margin/VBox/StatusLabel").text).is_equal(tr("ACTIVO"))
	thrusters.set_thruster_state(18.0, 18.0, false)
	assert_str(String(thrusters.widget_snapshot()["state"])).is_equal("READY")
	thrusters.set_thruster_state(0.0, 18.0, false)
	snap = thrusters.widget_snapshot()
	assert_str(String(snap["state"])).is_equal("EMPTY")
	assert_float(float(snap["dv_ratio"])).is_equal(0.0)

	var rope = SuitOS.get_screen("player:rope")
	rope.set_rope_state(false, false, 0.0)
	snap = rope.widget_snapshot()
	assert_dict(snap).contains_keys(["attached", "anchor_ready", "length", "state"])
	assert_bool(bool(snap["attached"])).is_false()
	assert_str(String(snap["state"])).is_equal("NO_ANCHOR")
	rope.set_rope_state(false, true, 0.0)
	assert_str(String(rope.widget_snapshot()["state"])).is_equal("IN_RANGE")
	rope.set_rope_state(true, true, 12.5)
	snap = rope.widget_snapshot()
	assert_bool(bool(snap["attached"])).is_true()
	assert_str(String(snap["state"])).is_equal("ATTACHED")
	assert_float(float(snap["length"])).is_equal_approx(12.5, EPS)
	var rw = auto_free(RopeWidgetScene.instance())
	add_child(rw)
	rw.update_snapshot(snap)
	assert_str(rw.get_node("Margin/VBox/StatusLabel").text).is_equal(tr("ENGANCHADA"))
	assert_str(rw.get_node("Margin/VBox/LengthLabel").text).is_equal(tr("LARGO: %.1f m") % 12.5)

func test_host_slot_press_helpers_follow_relocation() -> void:
	var host = auto_free(SuitOSHostScript.new())
	add_child(host) # _ready reaplica defaults: thrusters L2 (slot_2), rope R2 (slot_4)
	Input.action_press("slot_2")
	assert_bool(host.is_thrusters_slot_pressed()).is_true()
	Input.action_release("slot_2")
	Input.action_press("slot_4")
	assert_bool(host.is_rope_slot_pressed()).is_true()
	Input.action_release("slot_4")
	SuitOS.pin_to_slot(2, "player:thrusters") # R1 -> slot_3
	Input.action_press("slot_3")
	assert_bool(host.is_thrusters_slot_pressed()).is_true()
	Input.action_release("slot_3")
	Input.action_press("slot_2")
	assert_bool(host.is_thrusters_slot_pressed()).is_false()
	Input.action_release("slot_2")
	SuitOS.pin_to_slot(0, "player:rope") # L1 -> slot_1
	Input.action_press("slot_1")
	assert_bool(host.is_rope_slot_pressed()).is_true()
	Input.action_release("slot_1")
	Input.action_press("slot_4")
	assert_bool(host.is_rope_slot_pressed()).is_false()
	Input.action_release("slot_4")
