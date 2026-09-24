extends GdUnitTestSuite

# Gate global: con el puntero liberado por el juego en gameplay, el provider anula los intents
# de control (mover, saltar, camara, herramientas) pero conserva los campos de HUD, para que
# el cursor virtual no mueva al personaje ni dispare acciones "sin querer".

const InputProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

func after_test() -> void:
	VirtualMouseScript.set_pointer_released(false)
	for action in ["move_forward", "jump", "camera_right", "ui_down"]:
		Input.action_release(action)

func test_pointer_released_suppresses_gameplay_intents_but_keeps_hud_nav() -> void:
	var provider = InputProviderScript.new()
	VirtualMouseScript.set_pointer_released(true)
	Input.action_press("move_forward")
	Input.action_press("jump")
	Input.action_press("camera_right")
	Input.action_press("ui_down")
	var suppressed = provider.get_input()
	Input.action_release("ui_down")
	assert_float(suppressed.move_vec.length()).is_equal(0.0)
	assert_bool(suppressed.jump).is_false()
	assert_float(suppressed.mouse_delta.length()).is_equal(0.0)
	assert_int(int(suppressed.hud_nav)).is_equal(1)

	# Recapturar (clic izquierdo) levanta el gate solo.
	VirtualMouseScript.set_pointer_released(false)
	var restored = provider.get_input()
	assert_bool(restored.jump).is_true()
	assert_float(restored.move_vec.length()).is_greater(0.0)
