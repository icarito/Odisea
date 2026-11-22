extends GdUnitTestSuite

# FD-324 F4 — Suit OS del Ark-Run: Autonavegador en R1, hold/TAB, mini mapa radial
# + axial desde SpinFrame, gravedad local en g, destinos con nombre y aviso de encendido.

const Model = preload("res://core_v2/ui/suit_os/ArkRunNavigationModel.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const InputProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
const EPS := 0.00001

const ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "jump",
	"run", "crouch", "interact", "focus", "rotate_left", "rotate_right",
	"tool_fire_primary", "tool_fire_secondary", "cargol_ability", "nav_assist",
	"hud_mode", "slot_1", "slot_2", "slot_3", "slot_4"]


class RecordingAutopilot extends Reference:
	const Auto = preload("res://core_v2/input/AutopilotInputV2.gd")
	var held_history: Array = []
	var active := false
	func apply(d, held: bool) -> void:
		held_history.append(held)
		active = held and not Auto.human_is_active(d)


class FakePlayer extends KinematicBody:
	var _current_interactable = null


var _provider = null
var _autopilot = null
var _player = null
var _destination_events: Array = []
var _ignition_events: Array = []

func before_test() -> void:
	_release_actions()
	VirtualMouse.set_pointer_released(false)
	SuitOS.close_hud_mode(); SuitOS.close_screen(); SuitOS.set_context({})
	get_tree().paused = false
	SuitOS.clear_slots()
	SuitOS.clear_favorites()
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.ensure_ark_run_apps()
	SuitOS.apply_ark_run_default_pins()
	var nav = SuitOS.get_screen("ship:ark_nav")
	if nav != null:
		if not nav.is_connected("destination_changed", self, "_on_destination_changed"):
			nav.connect("destination_changed", self, "_on_destination_changed")
		if not nav.is_connected("ignition_alert", self, "_on_ignition_alert"):
			nav.connect("ignition_alert", self, "_on_ignition_alert")
	_destination_events.clear()
	_ignition_events.clear()
	_provider = InputProviderScript.new()
	_autopilot = RecordingAutopilot.new()
	_provider.autopilot = _autopilot


func after_test() -> void:
	_release_actions()
	SuitOS.clear_slots()
	SuitOS.clear_favorites()
	SuitOS.close_hud_mode()
	get_tree().paused = false
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_provider = null
	_autopilot = null
	yield(get_tree(), "idle_frame")


func _release_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


func _on_destination_changed(destination) -> void:
	_destination_events.append(destination)
func _on_ignition_alert(state, countdown) -> void:
	_ignition_events.append([state, countdown])


func test_autonav_registers_in_r1_and_moves_to_any_slot() -> void:
	assert_bool(SuitOS.has_screen("player:autonav")).is_true()
	assert_bool(SuitOS.has_screen("ship:ark_nav")).is_true()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["player:flashlight", "", "player:autonav", ""])
	assert_array(SuitOS.DEFAULT_PINS).is_equal(["player:flashlight", "", "", ""])
	assert_int(SuitOS.ARK_RUN_AUTONAV_SLOT).is_equal(2) # R1 = slot_3; L1 = slot_1
	assert_int(SuitOS.nav_assist_slot_index()).is_equal(2)
	SuitOS.pin_to_slot(1, "player:autonav")
	assert_str(SuitOS.slot_screen_id(1)).is_equal("player:autonav")
	assert_str(SuitOS.slot_screen_id(2)).is_empty()
	assert_int(SuitOS.nav_assist_slot_index()).is_equal(1)
	var nav_widget = auto_free(load("res://core_v2/ui/suit_os/ArkNavWidget.tscn").instance())
	add_child(nav_widget)
	nav_widget.update_snapshot(SuitOS.get_screen("ship:ark_nav").widget_snapshot())
	assert_object(load("res://core_v2/ui/suit_os/ArkRunAutonavWidget.tscn")).is_not_null()
	assert_object(load("res://core_v2/ui/suit_os/ArkRunSuitOSHost.gd")).is_not_null()


func test_hold_from_slot_and_tab_returns_manual_in_the_same_tick() -> void:
	Input.action_press("slot_3")
	_provider.get_input()
	assert_bool(_autopilot.active).is_true()
	assert_array(_autopilot.held_history).is_equal([true])

	_provider.mouse_delta_accum = Vector2(12.0, -4.0) # mirar no interrumpe
	_provider.get_input()
	assert_bool(_autopilot.active).is_true()

	Input.action_release("slot_3")
	_provider.get_input()
	assert_bool(_autopilot.held_history.back()).is_false()

	Input.action_press("nav_assist")
	_provider.get_input()
	assert_bool(_autopilot.active).is_true()
	Input.action_release("nav_assist")
	_provider.get_input()
	assert_bool(_autopilot.active).is_false()

	SuitOS.pin_to_slot(1, "player:autonav") # reubicado: el hold sigue al slot nuevo
	Input.action_press("slot_2")
	_provider.get_input()
	assert_bool(_autopilot.active).is_true()
	Input.action_release("slot_2")
	_provider.get_input()
	assert_bool(_autopilot.active).is_false()

	# Un interactuable cercano no es un intent; el intent humano sí cede en el mismo tick.
	_player = FakePlayer.new()
	_player._current_interactable = Node.new()
	_player.add_child(_player._current_interactable)
	get_tree().root.add_child(_player)
	_player.add_to_group("player")
	Input.action_press("slot_2")
	_provider.get_input()
	assert_bool(_autopilot.active).is_true()
	_provider.mouse_delta_accum = Vector2(8.0, 0.0)
	_provider.get_input()
	assert_bool(_autopilot.active).is_true()
	Input.action_press("interact")
	_provider.get_input()
	assert_bool(_autopilot.active).is_false()
	Input.action_release("interact")
	Input.action_release("slot_2")


func test_minimap_and_local_gravity_from_spin_frame() -> void:
	assert_float(Model.DEFAULT_HULL_RADIUS).is_equal_approx(340.0, EPS)
	var map: Dictionary = Model.minimap(Vector3(120.0, -160.0, 250.0), Model.DEFAULT_HULL_RADIUS, 2000.0)
	assert_float(float(map["angle"])).is_equal_approx(atan2(-160.0, 120.0), EPS)
	assert_float(float(map["radius_ratio"])).is_equal_approx(200.0 / 340.0, EPS)
	assert_float(float(map["axial_ratio"])).is_equal_approx(0.25, EPS)
	assert_float(float(map["point"][0])).is_equal_approx(120.0 / 340.0, 0.000001)
	assert_float(float(map["point"][1])).is_equal_approx(-160.0 / 340.0, 0.000001)
	var edge: Dictionary = Model.minimap(Vector3(0.0, 0.0, 4000.0), Model.DEFAULT_HULL_RADIUS, 2000.0)
	assert_float(float(edge["axial_ratio"])).is_equal(1.0)
	assert_float(float(edge["axial"])).is_equal(1000.0)

	var position := Vector3(240.0, 0.0, 0.0)
	var omega := SpinFrame.omega_for(9.8, 240.0)
	var idle: Dictionary = Model.gravity_reading(position, omega, 0.0)
	var burning: Dictionary = Model.gravity_reading(position, omega, 9.8)
	assert_float(float(idle["g"])).is_equal_approx(1.0, 0.000001)
	assert_float(float(idle["arrow_angle"])).is_equal_approx(0.0, 0.000001)
	assert_float(float(burning["g"])).is_equal_approx(sqrt(2.0), 0.000001)
	assert_bool(bool(burning["toward_pop"])).is_true()
	assert_float(float(burning["direction"][2])).is_less(0.0)
	assert_float(float(burning["arrow_angle"])).is_equal_approx(PI / 4.0, 0.000001)


func test_named_destinations_and_ignition_warning_signals() -> void:
	var nav = SuitOS.get_screen("ship:ark_nav")
	var snapshot: Dictionary = nav.widget_snapshot()
	var labels: Array = []
	for destination in snapshot["destinations"]:
		labels.append(String(destination["label"]))
	assert_array(labels).is_equal(["Puente", "Núcleo", "Motor", "Ascensores"])
	assert_str(String(snapshot["destination"]["label"])).is_equal("Motor")

	assert_str(String(nav.cycle_destination(1)["label"])).is_equal("Ascensores")
	assert_int(_destination_events.size()).is_equal(1)
	var result: Dictionary = SuitOS.perform_action("ship:ark_nav", "set_destination", {"id": "bridge"})
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_str(String(nav.widget_snapshot()["destination"]["label"])).is_equal("Puente")
	assert_int(_destination_events.size()).is_equal(2)

	nav.set_ignition_state("WARNING", 3.0)
	assert_array(_ignition_events).is_equal([["WARNING", 3.0]])
	snapshot = nav.widget_snapshot()
	assert_str(String(snapshot["ignition"]["state"])).is_equal("WARNING")
	assert_bool(bool(snapshot["ignition"]["active"])).is_false()
	nav.set_ignition_state("ACTIVE", 30.0)
	assert_bool(bool(nav.widget_snapshot()["ignition"]["active"])).is_true()
	assert_int(_ignition_events.size()).is_equal(2)
