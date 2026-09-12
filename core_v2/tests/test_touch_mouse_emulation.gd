extends GdUnitTestSuite

# test_touch_mouse_emulation.gd - En una pantalla tactil de escritorio el servidor grafico
# emula un mouse REAL por cada toque (ver MobileUIManager.is_pointer_from_touch): arrastrar el
# joystick disparaba tool_fire_primary sin soltar -22 de 56 frames en el replay del bug- y el
# motion fantasma movia la camara ademas del arrastre tactil.


func _touch() -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	return ev


func after_test() -> void:
	Input.action_release("tool_fire_primary")
	MobileUIManager._touch_pointer_until = 0 # la ventana dura mas que el test siguiente
	MobileUIManager._touch_trackers.clear()
	MobileUIManager._mouse_capture_suspended = false
	MobileUIManager._is_touch_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func test_a_touch_marks_the_pointer_as_a_finger_and_expires_on_its_own() -> void:
	assert_bool(MobileUIManager.is_pointer_from_touch()).is_false()
	MobileUIManager._input(_touch())
	assert_bool(MobileUIManager.is_pointer_from_touch()).is_true()
	# Ventana, no contador: sin mas toques se apaga sola aunque nadie vea el dedo levantarse.
	yield(await_millis(MobileUIManager.TOUCH_POINTER_GRACE_MSEC + 50), "completed")
	assert_bool(MobileUIManager.is_pointer_from_touch()).is_false()


func test_the_phantom_click_does_not_fire_the_tool() -> void:
	var provider := InputProviderV2.new()
	Input.action_press("tool_fire_primary")
	MobileUIManager._input(_touch())
	assert_bool(provider.get_input().tool_fire_primary).is_false()


func test_a_real_click_still_fires_the_tool() -> void:
	var provider := InputProviderV2.new()
	Input.action_press("tool_fire_primary")
	assert_bool(provider.get_input().tool_fire_primary).is_true()


# El joystick y los botones llaman set_input_as_handled(), que corta el grupo _input antes de
# llegar a este autoload (es el padre de todos ellos): arrastrando, _input() no ve un solo touch.
func test_a_held_touch_control_opens_the_window_without_any_event() -> void:
	var joystick_like = auto_free(TouchActionButton.new())
	joystick_like._touch_index = 0 # dedo apoyado, evento ya consumido por el control
	MobileUIManager._touch_trackers.append(joystick_like)
	assert_bool(MobileUIManager.is_pointer_from_touch()).is_false()
	MobileUIManager._process(0.016)
	assert_bool(MobileUIManager.is_pointer_from_touch()).is_true()


# Con el mouse capturado (XGrabPointer) X11 entrega la secuencia tactil al cliente del grab y el
# arrastre nunca llega como ScreenDrag: en modo tactil hay que soltar el grab.
func test_touch_releases_the_pointer_grab() -> void:
	if not _hold_a_touch_control():
		return # sin ventana (CI headless) no hay grab que soltar: nada que probar aca
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_HIDDEN)
	MobileUIManager._restore_mouse_capture()
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)


# Histeresis: mover el mouse de verdad sale del modo tactil en el acto (y con el, recupera el
# puntero; el modo de mouse solo se puede comprobar con ventana, ver el test de arriba).
func test_moving_the_real_mouse_ends_touch_mode() -> void:
	_hold_a_touch_control()
	MobileUIManager._is_touch_active = true
	MobileUIManager._touch_pointer_until = 0 # el dedo ya se fue: este motion no es fantasma
	MobileUIManager._input(_motion(40.0))
	assert_bool(MobileUIManager.is_touch_active()).is_false()
	assert_bool(MobileUIManager.is_mouse_capture_suspended()).is_false()


# El puntero fantasma tambien manda motion mientras el dedo arrastra: ese no cuenta.
func test_the_phantom_pointer_does_not_end_touch_mode() -> void:
	_hold_a_touch_control()
	MobileUIManager._is_touch_active = true
	MobileUIManager._input(_motion(40.0)) # dentro de la ventana del dedo
	assert_bool(MobileUIManager.is_touch_active()).is_true()


func _motion(dx: float) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, 0)
	return ev


# Devuelve false si el entorno no admite capturar el mouse: sin ventana (CI headless) el driver
# ignora set_mouse_mode, asi que no hay estado de grab que suspender.
func _hold_a_touch_control() -> bool:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var held = auto_free(TouchActionButton.new())
	held._touch_index = 0
	MobileUIManager._touch_trackers.append(held)
	var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	MobileUIManager._process(0.016)
	return captured
