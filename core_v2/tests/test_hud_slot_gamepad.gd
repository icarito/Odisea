extends GdUnitTestSuite

# Test de HudSlotGamepadV2: hombros = slots tambien en gameplay, decididos con el stream
# determinista (una muestra de InputDataV2 por tick). Tap = accion principal del widget;
# hold = radial fijado al slot. El mismo nodo se cuelga del host y del control remoto.

const HudSlotGamepad = preload("res://core_v2/ui/hud/HudSlotGamepadV2.gd")
const Gesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")


class FakeScreen extends Reference:
	var ops: Array = [{"button": "a", "op": "toggle", "label": "Encender", "confirm": true, "enabled": true}]
	func hud_gamepad_actions() -> Array:
		return ops


class FakeHost extends Node:
	var holds: Array = []
	func set_hold_progress(slot: int, progress: float) -> void:
		holds.append([slot, progress])


class FakeBackend extends Node:
	var slots: Dictionary = {}
	var screens: Dictionary = {}
	var opened: Array = []
	var performed: Array = []
	var hud: bool = false
	var widget_host: Node = null
	func slot_screen_id(slot: int) -> String:
		return String(slots.get(slot, ""))
	func has_screen(id: String) -> bool:
		return screens.has(id)
	func get_screen(id: String):
		return screens.get(id)
	func is_hud_mode_active() -> bool:
		return hud
	func get_widget_host() -> Node:
		return widget_host
	func open_hud_mode(_radial: bool, _screen_id: String, slot: int) -> bool:
		opened.append(slot)
		return true
	func perform_hud_widget_action(screen_id: String, op: String, args: Dictionary = {}) -> void:
		performed.append([screen_id, op, args])


func _sample(slot_number: int) -> InputDataV2:
	var d := InputDataV2.new()
	d.hud_slot = slot_number
	return d


func _make() -> Array:
	var backend := FakeBackend.new()
	add_child(backend)
	var host := FakeHost.new()
	backend.widget_host = host
	backend.add_child(host)
	var screen := FakeScreen.new()
	backend.screens["player:flashlight"] = screen
	backend.slots[2] = "player:flashlight"
	var node = HudSlotGamepad.new()
	node.backend = backend
	backend.add_child(node)
	return [backend, node, host]


func test_tap_runs_the_primary_action_without_opening() -> void:
	var ctx: Array = _make()
	var backend: FakeBackend = ctx[0]
	var node = ctx[1]
	node.tick(_sample(3)) # press del hombro del slot 3 (indice 2)
	var gesture: int = node.tick(_sample(0)) # release dentro del umbral = tap
	assert_int(gesture).is_equal(Gesture.TAP)
	assert_array(backend.performed).is_equal([["player:flashlight", "toggle", {}]])
	assert_array(backend.opened).is_empty() # el tap no abre nada
	backend.queue_free()


func test_hold_opens_the_radial_fixed_to_that_slot() -> void:
	var ctx: Array = _make()
	var backend: FakeBackend = ctx[0]
	var node = ctx[1]
	var host: FakeHost = ctx[2]
	var last: int = Gesture.NONE
	for _i in range(Gesture.HOLD_TICKS):
		last = node.tick(_sample(3))
	assert_int(last).is_equal(Gesture.HOLD)
	assert_array(backend.opened).is_equal([2])
	assert_array(backend.performed).is_empty()
	# Feedback: el host vio progreso creciente durante el hold y un apagado al abrir el radial.
	var saw_progress: bool = false
	for entry in host.holds:
		if entry[0] == 2 and float(entry[1]) > 0.0:
			saw_progress = true
	assert_bool(saw_progress).is_true()
	assert_array(host.holds.back()).is_equal([-1, 0.0])
	backend.queue_free()


func test_empty_slot_hold_still_opens_the_radial() -> void:
	var ctx: Array = _make()
	var backend: FakeBackend = ctx[0]
	var node = ctx[1]
	for _i in range(Gesture.HOLD_TICKS):
		node.tick(_sample(1)) # slot 1 (indice 0) vacio
	assert_array(backend.opened).is_equal([0])
	backend.queue_free()


func test_in_hud_mode_the_component_does_not_act() -> void:
	var ctx: Array = _make()
	var backend: FakeBackend = ctx[0]
	var node = ctx[1]
	backend.hud = true
	node.tick(_sample(3))
	node.tick(_sample(0))
	assert_array(backend.performed).is_empty()
	assert_array(backend.opened).is_empty()
	backend.queue_free()


func test_the_same_stream_gives_the_same_gestures() -> void:
	var frames: Array = [3, 3, 3, 0, 3, 3]
	var runs: Array = []
	for _run in range(2):
		var ctx: Array = _make()
		var backend: FakeBackend = ctx[0]
		var node = ctx[1]
		var gestures: Array = []
		for slot in frames:
			gestures.append(node.tick(_sample(slot)))
		runs.append([gestures, backend.performed, backend.opened])
		backend.queue_free()
	assert_array(runs[0]).is_equal(runs[1])
