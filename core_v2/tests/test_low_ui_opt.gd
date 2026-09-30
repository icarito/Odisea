extends GdUnitTestSuite

# FD-316 (tarea GG): ahorros de UI del tier LOW, con A/B por ODISEA_LOW_UI_OPT.
# Lo critico: fuera de LOW (o con el A/B en 0) NADA cambia; en LOW, la UI animada se
# refresca a 10 Hz, los controles tactiles no se dibujan sin pantalla tactil y los
# subtitulos no pagan sombra.

const LowUiOptScript = preload("res://core_v2/systems/LowUiOpt.gd")
const LowHzTickScript = preload("res://core_v2/systems/LowHzTick.gd")
const SubtitlesOverlayScript = preload("res://core_v2/ui/retro/SubtitlesOverlay.gd")
const HudViewMountScript = preload("res://core_v2/ui/hud/HudViewMount.gd")

var _gate_prev := {}
var _sm_prev := false
var _env_prev := ""


func before() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate:
		_gate_prev = {
			"force_gate": gate.force_gate,
			"gated": gate._gated_active,
			"env": gate._env_forced_low_tier,
		}
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		_sm_prev = bool(sm.get("low_end_forced"))
	_env_prev = OS.get_environment(LowUiOptScript.ENV)
	OS.set_environment(LowUiOptScript.ENV, "")


func after() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate and not _gate_prev.empty():
		gate.force_gate = _gate_prev["force_gate"]
		gate._gated_active = _gate_prev["gated"]
		gate._env_forced_low_tier = _gate_prev["env"]
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		sm.set("low_end_forced", _sm_prev)
	OS.set_environment(LowUiOptScript.ENV, _env_prev)


func _set_low(active: bool) -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	assert_object(gate).is_not_null()
	if gate == null:
		return
	gate.force_gate = active
	gate._gated_active = false
	gate._env_forced_low_tier = false
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		sm.set("low_end_forced", false)


# El interruptor es "tier LOW y ODISEA_LOW_UI_OPT != 0".
func test_low_ui_opt_gate_and_env() -> void:
	_set_low(true)
	assert_bool(LowUiOptScript.enabled()).is_true()
	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_bool(LowUiOptScript.enabled()).is_false()
	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_bool(LowUiOptScript.enabled()).is_false()


# En LOW el delta se acumula y solo sale cada ~0.1 s; fuera de LOW (o con el A/B en 0)
# pasa el mismo delta en cada llamada, sin cambiar el comportamiento.
func test_low_hz_tick_throttles_only_in_low() -> void:
	_set_low(true)
	var low_tick = LowHzTickScript.new(LowUiOptScript.HZ)
	assert_float(low_tick.step(0.03)).is_equal(-1.0)
	assert_float(low_tick.step(0.03)).is_equal(-1.0)
	assert_float(low_tick.step(0.05)).is_equal_approx(0.11, 0.0001)

	_set_low(false)
	var desktop_tick = LowHzTickScript.new(LowUiOptScript.HZ)
	assert_float(desktop_tick.step(0.016)).is_equal_approx(0.016, 0.0001)

	_set_low(true)
	OS.set_environment(LowUiOptScript.ENV, "0")
	var ab_off_tick = LowHzTickScript.new(LowUiOptScript.HZ)
	assert_float(ab_off_tick.step(0.016)).is_equal_approx(0.016, 0.0001)
	OS.set_environment(LowUiOptScript.ENV, "")


# En LOW sin pantalla tactil la UI tactil queda suprimida; con el A/B en 0 no se suprime.
func test_mobile_ui_suppressed_without_touchscreen_in_low() -> void:
	var mobile = get_node_or_null("/root/MobileUIManager")
	assert_object(mobile).is_not_null()
	if mobile == null:
		return
	var prev_touchscreen = mobile._has_touchscreen
	mobile._has_touchscreen = false

	_set_low(true)
	assert_bool(mobile._touch_ui_suppressed()).is_true()
	mobile._activate_touch()
	assert_bool(mobile.is_touch_active()).is_false()

	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_bool(mobile._touch_ui_suppressed()).is_false()

	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_bool(mobile._touch_ui_suppressed()).is_false()

	mobile._has_touchscreen = prev_touchscreen


# Los subtitulos pierden la sombra dinamica en LOW y la conservan fuera de LOW / con el A/B en 0.
func test_subtitles_shadow_disabled_in_low() -> void:
	var sub = SubtitlesOverlayScript.new()
	_set_low(true)
	assert_int(sub._build_stylebox(false).shadow_size).is_equal(0)
	OS.set_environment(LowUiOptScript.ENV, "0")
	assert_int(sub._build_stylebox(false).shadow_size).is_equal(4)
	OS.set_environment(LowUiOptScript.ENV, "")
	_set_low(false)
	assert_int(sub._build_stylebox(false).shadow_size).is_equal(4)
	sub.free()


# El Viewport animado del HUD pasa a UPDATE_DISABLED + driver de 10 Hz en LOW, y a
# UPDATE_ALWAYS sin driver fuera del tier.
func test_viewport_animation_is_10hz_in_low() -> void:
	var host = HudViewMountScript.new()
	var vp = Viewport.new()
	_set_low(true)
	host._enable_viewport_animation(vp)
	assert_int(vp.render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	assert_object(vp.get_node_or_null("LowHzRedraw")).is_not_null()

	_set_low(false)
	var vp_desktop = Viewport.new()
	host._enable_viewport_animation(vp_desktop)
	assert_int(vp_desktop.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)
	assert_object(vp_desktop.get_node_or_null("LowHzRedraw")).is_null()

	vp.free()
	vp_desktop.free()
