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
