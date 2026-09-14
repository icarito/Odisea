extends GdUnitTestSuite

# Toda vibracion pasa por Haptics: respeta la opcion "Vibracion", da un detente por opcion del dial
# y un pulso al confirmar, marca cada destino al arrastrar, y cada temblor de camara se siente aca y
# en el control remoto.

const Haptics = preload("res://core_v2/ui/Haptics.gd")
const SelectorScene = preload("res://core_v2/ui/radial/RadialSelectorV2.tscn")
const HudWidgetAction = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
const BridgeScript = preload("res://core_v2/components/SuitOSRemoteBridge.gd")

var _pulses: Array = []
var _vibration_before := true


class DummyServer extends Node:
	var directives: Array = []
	func has_paired_client() -> bool:
		return true
	func send_ui_directive(op: String, payload) -> void:
		directives.append({"op": op, "payload": payload})


func before_test() -> void:
	_pulses = []
	Engine.set_meta("haptics_probe", _pulses)
	_vibration_before = SettingsManager.vibration
	SettingsManager.vibration = true


func after_test() -> void:
	Engine.set_meta("haptics_probe", null)
	SettingsManager.vibration = _vibration_before
	CinematicManager.stop_camera_shake()


func test_the_vibration_option_turns_every_pulse_off() -> void:
	Haptics.tick()
	Haptics.confirm()
	assert_array(_pulses).is_equal([Haptics.TICK_MSEC, Haptics.CONFIRM_MSEC])
	SettingsManager.vibration = false
	Haptics.pulse(100)
	CinematicManager.trigger_camera_shake(0.5, 0.1)
	assert_int(_pulses.size()).is_equal(2)
	# Un temblor largo no deja el telefono zumbando.
	SettingsManager.vibration = true
	Haptics.pulse(10000)
	assert_int(_pulses.back()).is_equal(Haptics.MAX_MSEC)


func test_the_dial_ticks_once_per_marked_option_and_pulses_on_confirm() -> void:
	var selector = auto_free(SelectorScene.instance())
	add_child(selector)
	selector.rect_size = Vector2(1024.0, 1024.0)
	selector.set_options(["1", "2", "3"])
	selector.open()
	var center := Vector2(512.0, 512.0)
	selector.point_at(center + Vector2(0.0, 330.0)) # 6
	selector.point_at(center + Vector2(0.0, 335.0)) # misma opcion: sin detente
	selector.point_at(center + Vector2(330.0, 0.0)) # 3
	assert_array(_pulses).is_equal([Haptics.TICK_MSEC, Haptics.TICK_MSEC])
	selector.confirm()
	assert_int(_pulses.back()).is_equal(Haptics.CONFIRM_MSEC)


func test_a_widget_button_and_each_new_drop_target_are_felt() -> void:
	var loose = auto_free(Control.new())
	add_child(loose)
	HudWidgetAction.perform(loose, "", "noop")
	assert_array(_pulses).is_equal([Haptics.CONFIRM_MSEC])

	var host = SuitOS.get_node("SuitOSWidgetHost")
	host.show_drop_targets(true, 1)
	host.show_drop_targets(true, 1) # sigue en el mismo slot
	host.show_drop_targets(true, -1) # fuera de todo slot: nada
	host.show_drop_targets(true, 2)
	host.show_drop_targets(false)
	assert_array(_pulses).is_equal([Haptics.CONFIRM_MSEC, Haptics.TICK_MSEC, Haptics.TICK_MSEC])


func test_every_camera_shake_is_felt_here_and_on_the_remote() -> void:
	var server = auto_free(DummyServer.new())
	add_child(server)
	var bridge = auto_free(BridgeScript.new())
	add_child(bridge)
	bridge.server = server

	CinematicManager.trigger_camera_shake(1.2, 0.12, 30.0, 2.0) # la ruptura del criocoolant
	assert_array(_pulses).is_equal([1200])
	var sent: Array = []
	for d in server.directives:
		if d["op"] == "haptic":
			sent.append(d["payload"])
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["kind"])).is_equal("shake")
	assert_float(float(sent[0]["intensity"])).is_equal_approx(1.0, 0.001)
	assert_float(float(sent[0]["duration"])).is_equal_approx(1.2, 0.001)

	# Y el control remoto lo siente con su propia opcion de vibracion.
	var home = auto_free(load("res://core_v2/ui/RemoteControlHome.tscn").instance())
	add_child(home)
	home._on_ui_directive("haptic", sent[0])
	assert_int(_pulses.back()).is_equal(1200)
