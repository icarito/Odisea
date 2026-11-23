extends GdUnitTestSuite

# D-pad: en juego es camara (izq/der gira, arriba/abajo inclina); el modo HUD lo apaga en su
# proveedor para que navegue la UI.

const InputProviderScript = preload("res://core_v2/input/InputProviderV2.gd")

func after_test() -> void:
	for action in ["camera_up", "camera_down", "camera_left", "camera_right"]:
		Input.action_release(action)

func test_dpad_up_tilts_the_camera_and_hud_mode_turns_it_off() -> void:
	var provider = InputProviderScript.new()
	Input.action_press("camera_up")
	var tilted = provider.get_input()
	assert_float(tilted.mouse_delta.y).is_greater(0.0)
	assert_float(tilted.zoom_delta).is_equal(0.0)

	provider.digital_camera_enabled = false
	var hud = provider.get_input()
	assert_float(hud.mouse_delta.length()).is_equal(0.0)

# FD-325 polish (playtest): el stick derecho NO debe quedar invertido en Y. `JOY_AXIS_3`
# vale -1 con el stick hacia ARRIBA; el delta debe ser +y (como D-pad arriba y el mouse),
# para que `pitch -= mouse_delta.y * sensitivity` incline la cámara hacia arriba.
func test_right_stick_up_tilts_camera_up_not_inverted() -> void:
	# Stick arriba: eje crudo negativo (SDL) -> delta +y (inclina arriba).
	var up: Vector2 = InputProviderScript.look_delta_from_joy(0.0, -1.0)
	assert_float(up.y).is_greater(0.0)
	# Stick abajo: delta -y (inclina abajo).
	var down: Vector2 = InputProviderScript.look_delta_from_joy(0.0, 1.0)
	assert_float(down.y).is_less(0.0)
	# Horizontal no se toca.
	assert_float(InputProviderScript.look_delta_from_joy(1.0, 0.0).x).is_equal(1.0)
	# Mismo signo que el D-pad (arriba => +y).
	Input.action_press("camera_up")
	var provider = InputProviderScript.new()
	var pad = provider.get_input()
	Input.action_release("camera_up")
	assert_float(pad.mouse_delta.y).is_greater(0.0)
	assert_float(sign(up.y)).is_equal(sign(pad.mouse_delta.y))
