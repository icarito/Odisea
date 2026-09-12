extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const InputProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

# El handheld reporta los ejes del stick invertidos. InputProviderV2 lo corrige en
# step(), pero VirtualMouse lee las acciones cursor_* del InputMap sin pasar por ahi:
# si las dos puntas no leen el mismo origen, el cursor de UI queda invertido mientras
# caminar y la camara van bien. Este test ata las dos a la misma funcion.

func _with_device(value: String) -> bool:
	var previous = OS.get_environment("ODISEA_DEVICE")
	OS.set_environment("ODISEA_DEVICE", value)
	var result: bool = InputProviderScript.wants_handheld_axis_inversion()
	OS.set_environment("ODISEA_DEVICE", previous)
	return result

func test_inversion_follows_the_device_hint() -> void:
	assert_bool(_with_device("anbernic")).is_true()
	assert_bool(_with_device("RG351V")).is_true()
	assert_bool(_with_device("")).is_false()
	assert_bool(_with_device("desktop")).is_false()

func test_provider_axis_flags_match_the_shared_helper() -> void:
	var previous = OS.get_environment("ODISEA_DEVICE")
	OS.set_environment("ODISEA_DEVICE", "anbernic")

	var provider = InputProviderScript.new()
	provider._ensure_axis_profile_resolved()
	assert_bool(provider.handheld_axis_correction_enabled).is_true()
	assert_bool(provider._invert_joy_move_x).is_true()
	assert_bool(provider._invert_joy_move_y).is_true()
	assert_str(provider.handheld_axis_profile).is_equal("anbernic_env_invert_xy")

	# El cursor de UI toma su signo de la misma fuente que el provider.
	var mouse = VirtualMouseScript.new()
	add_child(mouse)
	assert_bool(mouse._invert_axes).is_equal(provider.handheld_axis_correction_enabled)

	mouse.queue_free()
	OS.set_environment("ODISEA_DEVICE", previous)
