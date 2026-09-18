extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const InputProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

# La inversion de ejes ya no se detecta por dispositivo: es una preferencia del
# jugador (Opciones -> Invertir X / Invertir Y) y la comparten el gameplay, el
# cursor de UI y el control remoto. Un firmware que da vuelta un stick lo hace en
# los dos a la vez, asi que la misma preferencia corrige movimiento y camara.
# Este test ata las tres puntas a la misma fuente.

func _with_inversion(ix: bool, iy: bool) -> Vector2:
	var prev_x = SettingsManager.invert_x
	var prev_y = SettingsManager.invert_y
	SettingsManager.invert_x = ix
	SettingsManager.invert_y = iy
	var result: Vector2 = InputProviderScript.axis_inversion()
	SettingsManager.invert_x = prev_x
	SettingsManager.invert_y = prev_y
	return result

func test_inversion_defaults_to_identity() -> void:
	assert_vector2(_with_inversion(false, false)).is_equal(Vector2.ONE)
	assert_bool(InputProviderScript.wants_axis_inversion()).is_false()

func test_inversion_follows_the_menu_toggles() -> void:
	assert_vector2(_with_inversion(true, false)).is_equal(Vector2(-1.0, 1.0))
	assert_vector2(_with_inversion(false, true)).is_equal(Vector2(1.0, -1.0))
	assert_vector2(_with_inversion(true, true)).is_equal(Vector2(-1.0, -1.0))

func test_provider_axis_flags_match_the_shared_helper() -> void:
	var prev_x = SettingsManager.invert_x
	var prev_y = SettingsManager.invert_y
	SettingsManager.invert_x = true
	SettingsManager.invert_y = true

	var provider = InputProviderScript.new()
	provider._ensure_axis_profile_resolved()
	assert_bool(provider.handheld_axis_correction_enabled).is_true()
	assert_bool(provider._invert_joy_move_x).is_true()
	assert_bool(provider._invert_joy_move_y).is_true()
	assert_str(provider.handheld_axis_profile).is_equal("manual_invert_xy")

	# El cursor de UI toma su signo de la misma fuente que el provider.
	var mouse = VirtualMouseScript.new()
	add_child(mouse)
	mouse._invert_axes = InputProviderScript.axis_inversion()
	assert_vector2(mouse._invert_axes).is_equal(Vector2(-1.0, -1.0))

	mouse.queue_free()
	SettingsManager.invert_x = prev_x
	SettingsManager.invert_y = prev_y
