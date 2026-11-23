extends GdUnitTestSuite

# FD-325 T2: controles tactiles de Ark Run (IMPULSO/CUERDA/AUTONAV). Cubre:
#  - visibilidad contextual (oculto hasta set_spin_controls_active(true)),
#  - zonas sagradas en 1280x720 y 800x480 (IMPULSO izq sobre el joystick, CUERDA der sobre los
#    botones de accion, nada invade la franja superior 0..140px ni la barra central inerne),
#  - grupo "touch_control" (TouchCameraControls no gira la camara al tocarlos),
#  - estados: IMPULSO vs RETRAER, CUERDA atenuado / "CUERDA 68 m" / SOLTAR y el ratio de Dv.

const ArkRunTouchControlsScript = preload("res://core_v2/ui/ArkRunTouchControls.gd")

const RING_SAFE_TOP := 140.0
const VIEWPORTS := [Vector2(1280, 720), Vector2(800, 480)]

var _host: Control = null
var _controls = null


func before_test() -> void:
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.rect_size = Vector2(1280, 720)
	get_tree().root.add_child(_host)
	_controls = ArkRunTouchControlsScript.new()
	_host.add_child(_controls)
	yield(get_tree(), "idle_frame")


func after_test() -> void:
	if is_instance_valid(_host):
		_host.queue_free()
	_host = null
	_controls = null
	yield(get_tree(), "idle_frame")


# --- Visibilidad contextual ----------------------------------------------------------------

func test_hidden_by_default_and_visible_when_spin_active() -> void:
	assert_bool(_controls.visible).is_false()
	assert_bool(_controls.is_spin_controls_active()).is_false()
	assert_bool(_controls.get_thruster_button().is_visible_in_tree()).is_false()

	_controls.set_spin_controls_active(true)
	assert_bool(_controls.visible).is_true()
	assert_bool(_controls.is_spin_controls_active()).is_true()

	# Volver a false la esconde otra vez (salir de ArkRun).
	_controls.set_spin_controls_active(false)
	assert_bool(_controls.visible).is_false()


func test_manager_helpers_delegate_when_ui_exists() -> void:
	var mgr: Node = get_node_or_null("/root/MobileUIManager")
	if mgr == null:
		return
	var saved_active: bool = mgr._spin_controls_active
	var saved_ui: Node = mgr._mobile_ui
	var saved_mobile: bool = mgr._is_mobile
	var saved_touch: bool = mgr._is_touch_active
	var saved_seen: bool = mgr._touch_seen

	mgr._is_mobile = true
	mgr._is_touch_active = true
	mgr._touch_seen = true
	if not is_instance_valid(mgr._mobile_ui):
		mgr._spawn_mobile_ui()
	var node: Node = mgr._mobile_ui.get_node_or_null("Container/ArkRunTouchControls")
	assert_object(node).is_not_null()
	assert_bool(node.visible).is_false()

	mgr.set_spin_controls_active(true)
	assert_bool(mgr.is_spin_controls_active()).is_true()
	assert_bool(node.visible).is_true()

	mgr.update_spin_touch_state({"rope_attached": true, "dv_ratio": 0.5})
	assert_str(node.get_thruster_button().text).is_equal("RETRAER")
	assert_float(node.get_dv_ratio()).is_equal(0.5)

	# La UI mostrandose (_set_gameplay_controls_visible) no debe forzar visible el nodo si la
	# escena no lo pidio: se gobierna por el flag del manager.
	mgr.set_spin_controls_active(false)
	mgr._set_gameplay_controls_visible(true)
	assert_bool(node.visible).is_false()

	if is_instance_valid(mgr._mobile_ui):
		mgr._mobile_ui.free()
		mgr._mobile_ui = saved_ui
	mgr._spin_controls_active = saved_active
	mgr._is_mobile = saved_mobile
	mgr._is_touch_active = saved_touch
	mgr._touch_seen = saved_seen
	mgr._refresh_mobile_ui_visibility()


# --- Zonas seguras ---------------------------------------------------------------------------

func test_safe_zones_on_both_viewports() -> void:
	for entry in VIEWPORTS:
		var vsize: Vector2 = entry
		_controls.set_spin_controls_active(true)
		_controls._layout_buttons(vsize)
		var joystick_left: float = 90.0 # MoveJoystick arranca a 90px del borde izq
		var action_right: float = vsize.x - 30.0 # ActionButtons termina a 30px del borde der
		var imp: Control = _controls.get_thruster_button()
		var cue: Control = _controls.get_rope_button()
		var nav: Control = _controls.get_nav_button()

		# IMPULSO a la izquierda (sobre el joystick) y CUERDA a la derecha (sobre ActionButtons).
		var imp_rect := Rect2(imp.rect_position, imp.rect_size)
		var cue_rect := Rect2(cue.rect_position, cue.rect_size)
		assert_bool(imp_rect.position.x < vsize.x * 0.5).override_failure_message(
			"IMPULSO debe quedar en la mitad izquierda @%s" % str(vsize)).is_true()
		assert_bool(imp_rect.end.x <= joystick_left + 300.0).override_failure_message(
			"IMPULSO debe quedar sobre MoveJoystick @%s (x=%.1f)" % [str(vsize), imp_rect.position.x]).is_true()
		assert_bool(cue_rect.position.x >= vsize.x * 0.5).override_failure_message(
			"CUERDA debe quedar en la mitad derecha @%s" % str(vsize)).is_true()
		assert_bool(cue_rect.position.x >= action_right - 330.0).override_failure_message(
			"CUERDA debe quedar sobre ActionButtons @%s (x=%.1f)" % [str(vsize), cue_rect.position.x]).is_true()

		# Ningun boton de accion invade la franja superior central (0..140px) ni el centro.
		for btn in [imp, cue, nav]:
			var rect := Rect2(btn.rect_position, btn.rect_size)
			assert_bool(rect.position.y >= RING_SAFE_TOP).override_failure_message(
				"%s invade la franja superior @%s (y=%.1f)" % [btn.name, str(vsize), rect.position.y]).is_true()
			assert_bool(rect.position.y < vsize.y).is_true() # dentro de pantalla
			assert_bool(btn.rect_position.x >= 0.0 and rect.end.x <= vsize.x).override_failure_message(
				"%s se sale por los lados @%s" % [btn.name, str(vsize)]).is_true()

		# El centro superior (barra del HUD) no lo tapa ningun boton.
		var center_top := Rect2(vsize.x * 0.5 - 100.0, 0.0, 200.0, RING_SAFE_TOP)
		for btn in [imp, cue, nav]:
			var rect := Rect2(btn.rect_position, btn.rect_size)
			assert_bool(rect.intersects(center_top)).override_failure_message(
				"%s pisa el centro superior @%s" % [btn.name, str(vsize)]).is_false()


func test_all_new_buttons_are_touch_controls() -> void:
	for btn in [_controls.get_thruster_button(), _controls.get_rope_button(), _controls.get_nav_button()]:
		assert_object(btn).is_not_null()
		assert_bool(btn.is_in_group("touch_control")).override_failure_message(
			"%s debe estar en el grupo touch_control" % btn.name).is_true()


func test_buttons_use_expected_actions() -> void:
	assert_str(_controls.get_thruster_button().action_name).is_equal("thruster_boost")
	assert_str(_controls.get_rope_button().action_name).is_equal("rope_grapple")
	assert_str(_controls.get_nav_button().action_name).is_equal("nav_assist")


# --- Estados visuales ------------------------------------------------------------------------

func test_thruster_label_switches_impulso_and_retraer() -> void:
	_controls.set_spin_controls_active(true)
	_controls.update_spin_touch_state({"rope_attached": false})
	assert_str(_controls.get_thruster_button().text).is_equal("IMPULSO")

	_controls.update_spin_touch_state({"rope_attached": true})
	assert_str(_controls.get_thruster_button().text).is_equal("RETRAER")


func test_rope_button_dims_shows_range_and_soltar() -> void:
	_controls.set_spin_controls_active(true)
	# Sin anclaje: atenuado, texto simple.
	_controls.update_spin_touch_state({"rope_attached": false, "anchor_in_range": false})
	var rope: Control = _controls.get_rope_button()
	assert_str(rope.text).is_equal("CUERDA")
	assert_bool(rope.modulate.a < 1.0).override_failure_message("CUERDA sin anclaje debe verse atenuado").is_true()

	# Con anclaje en rango: iluminado y con distancia.
	_controls.update_spin_touch_state({"anchor_in_range": true, "anchor_range_m": 68.0})
	assert_str(rope.text).is_equal("CUERDA\n68 m")
	assert_float(rope.modulate.a).is_greater(0.9)

	# Cuerda enganchada: SOLTAR.
	_controls.update_spin_touch_state({"rope_attached": true})
	assert_str(rope.text).is_equal("SOLTAR")


func test_dv_ratio_ring_is_clamped() -> void:
	_controls.set_spin_controls_active(true)
	_controls.update_spin_touch_state({"dv_ratio": 0.42})
	assert_float(_controls.get_dv_ratio()).is_equal(0.42)
	_controls.update_spin_touch_state({"dv_ratio": 2.0})
	assert_float(_controls.get_dv_ratio()).is_equal(1.0)
	_controls.update_spin_touch_state({"dv_ratio": -1.0})
	assert_float(_controls.get_dv_ratio()).is_equal(0.0)


func test_partial_updates_keep_previous_state() -> void:
	_controls.set_spin_controls_active(true)
	_controls.update_spin_touch_state({"rope_attached": true, "anchor_range_m": 68.0})
	_controls.update_spin_touch_state({"dv_ratio": 0.3}) # sin tocar rope_attached
	assert_str(_controls.get_thruster_button().text).is_equal("RETRAER")
	assert_float(_controls.get_dv_ratio()).is_equal(0.3)
