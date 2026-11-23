extends GdUnitTestSuite

# FD-325 T1 — input unificado:
# - `rope_grapple` / `thruster_boost` existen en el InputMap y responden a Input.action_press
#   (el mismo canal que sintetiza TouchActionButton).
# - Con `triggers_reserved_for_gameplay`, L2/R2 no disparan hud_slot en gameplay, L1/R1 sí, y
#   en modo HUD los 4 slots siguen completos.
# - SpinRopeInputV2 en modo touch toggle: tap engancha, soltar el dedo mantiene, tap 2 o salto
#   suelta conservando el momento.
# - `get_active_input_device()` reporta el ultimo dispositivo.

const InputProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const RopeInputScript = preload("res://core_v2/player/traversal/SpinRopeInputV2.gd")

const ACTIONS := ["slot_1", "slot_2", "slot_3", "slot_4", "rope_grapple", "thruster_boost",
	"jump", "interact", "nav_assist", "hud_mode"]

var _provider = null
var _saved_reserved := true
var _saved_shoulder := false


class FakePilot extends KinematicBody:
	var velocity := Vector3(0.0, 0.0, 0.0)


func before_test() -> void:
	_release_actions()
	_saved_reserved = SuitOS.triggers_reserved_for_gameplay
	_saved_shoulder = SuitOS.shoulder_slots_suppressed
	SuitOS.triggers_reserved_for_gameplay = true
	SuitOS.shoulder_slots_suppressed = false
	SuitOS.close_hud_mode()
	get_tree().paused = false
	_provider = InputProviderScript.new()


func after_test() -> void:
	_release_actions()
	SuitOS.triggers_reserved_for_gameplay = _saved_reserved
	SuitOS.shoulder_slots_suppressed = _saved_shoulder
	SuitOS.close_hud_mode()
	get_tree().paused = false
	yield(get_tree(), "idle_frame")


func _release_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


# --- Acciones registradas ---

func test_rope_and_thruster_actions_exist_and_respond_to_action_press() -> void:
	assert_bool(InputMap.has_action("rope_grapple")).is_true()
	assert_bool(InputMap.has_action("thruster_boost")).is_true()

	Input.action_press("rope_grapple")
	assert_bool(Input.is_action_pressed("rope_grapple")).is_true()
	Input.action_release("rope_grapple")
	assert_bool(Input.is_action_pressed("rope_grapple")).is_false()

	Input.action_press("thruster_boost")
	assert_bool(Input.is_action_pressed("thruster_boost")).is_true()
	Input.action_release("thruster_boost")
	assert_bool(Input.is_action_pressed("thruster_boost")).is_false()


func test_thruster_input_reads_thruster_boost_action() -> void:
	var thruster = auto_free(ThrusterScript.new())
	add_child(thruster)
	thruster.keyboard_thruster_scancode = -1 # sin teclado crudo: solo la acción
	assert_bool(thruster.read_keyboard_pressed()).is_false()
	Input.action_press("thruster_boost")
	assert_bool(thruster.read_keyboard_pressed()).is_true()
	Input.action_release("thruster_boost")
	assert_bool(thruster.read_keyboard_pressed()).is_false()


# --- Liberación real de gatillos ---

func test_triggers_do_not_fire_hud_slots_in_gameplay() -> void:
	Input.action_press("slot_2") # L2
	assert_int(_provider.get_input().hud_slot).is_equal(0)
	Input.action_press("slot_4") # R2
	assert_int(_provider.get_input().hud_slot).is_equal(0)
	# L1/R1 sí publican: son los dos slots rápidos de gameplay.
	Input.action_press("slot_1")
	assert_int(_provider.get_input().hud_slot).is_equal(1)
	Input.action_press("slot_3")
	# slot_1 sigue sostenida y gana por orden; soltamos para verificar slot_3.
	Input.action_release("slot_1")
	assert_int(_provider.get_input().hud_slot).is_equal(3)


func test_triggers_fire_when_reservation_flag_is_off() -> void:
	SuitOS.triggers_reserved_for_gameplay = false
	Input.action_press("slot_2")
	assert_int(_provider.get_input().hud_slot).is_equal(2)


func test_hud_mode_keeps_all_four_slots() -> void:
	SuitOS.set_hud_mode_active(true) # estado puro: sin pausar la escena del test
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_bool(SuitOS.triggers_are_reserved_for_gameplay()).is_false()
	for n in range(1, 5):
		_release_actions()
		Input.action_press("slot_%d" % n)
		assert_int(_provider.get_input().hud_slot).is_equal(n)
	_release_actions()
	SuitOS.set_hud_mode_active(false)


# --- Cuerda: toggle touch y salto suelta ---

func _rope_rig():
	var pilot = auto_free(FakePilot.new())
	add_child(pilot)
	pilot.global_transform.origin = Vector3.ZERO
	pilot.velocity = Vector3(4.0, 0.0, 0.0)
	var rope = auto_free(RopeInputScript.new())
	add_child(rope)
	rope._ensure_rope()
	rope.max_range = 55.0
	rope.cone_deg = 38.0
	var anchors: Array = [Vector3(0.0, 0.0, -10.0)] # adelante (-Z), dentro del cono
	return [rope, pilot, anchors]


func test_touch_toggle_attaches_once_and_stays_until_second_tap() -> void:
	var rig: Array = _rope_rig()
	var rope = rig[0]
	var pilot = rig[1]
	var anchors: Array = rig[2]
	var aim := Vector3(0.0, 0.0, -1.0)
	# Tap 1 (flanco de subida) engancha.
	var r: Dictionary = rope.step(pilot, anchors, aim, true, 0.016, false, false, false, true)
	assert_bool(bool(r["attached"])).is_true()
	assert_bool(rope.is_attached()).is_true()
	# Soltar el dedo (pressed=false) NO suelta en toggle.
	r = rope.step(pilot, anchors, aim, false, 0.016, false, true, false, true)
	assert_bool(bool(r["released"])).is_false()
	assert_bool(rope.is_attached()).is_true()
	# Tap 2 (nuevo flanco) suelta.
	r = rope.step(pilot, anchors, aim, true, 0.016, false, false, false, true)
	assert_bool(rope.is_attached()).is_false()


func test_touch_toggle_jump_releases_and_keeps_momentum() -> void:
	var rig: Array = _rope_rig()
	var rope = rig[0]
	var pilot = rig[1]
	var anchors: Array = rig[2]
	var aim := Vector3(0.0, 0.0, -1.0)
	rope.step(pilot, anchors, aim, true, 0.016, false, false, false, true)
	assert_bool(rope.is_attached()).is_true()
	var v_before: Vector3 = pilot.velocity
	var r: Dictionary = rope.step(pilot, anchors, aim, false, 0.016, false, true, true, true)
	assert_bool(bool(r["released"])).is_true()
	assert_bool(rope.is_attached()).is_false()
	assert_vector3(pilot.velocity).is_equal(v_before) # el momento se conserva


func test_hold_mode_still_releases_on_button_up() -> void:
	var rig: Array = _rope_rig()
	var rope = rig[0]
	var pilot = rig[1]
	var anchors: Array = rig[2]
	var aim := Vector3(0.0, 0.0, -1.0)
	rope.step(pilot, anchors, aim, true, 0.016) # hold, default
	assert_bool(rope.is_attached()).is_true()
	var r: Dictionary = rope.step(pilot, anchors, aim, false, 0.016)
	assert_bool(bool(r["released"])).is_true()
	assert_bool(rope.is_attached()).is_false()


# --- Dispositivo activo ---

func test_last_input_device_tracks_sources() -> void:
	assert_str(_provider.get_active_input_device()).is_equal("keyboard")
	_provider.add_touch_camera_drag(Vector2(3.0, 0.0))
	assert_str(_provider.get_active_input_device()).is_equal("touch")
	Input.action_press("thruster_boost")
	_provider.mouse_delta_accum = Vector2(5.0, 0.0)
	_provider.get_input()
	assert_str(_provider.get_active_input_device()).is_equal("keyboard")
	Input.action_release("thruster_boost")
