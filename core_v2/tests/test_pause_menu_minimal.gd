extends GdUnitTestSuite

const PauseMenuScene = preload("res://core_v2/ui/PauseMenu.tscn")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")


func after_test() -> void:
	# El puntero liberado es estado global del cursor compartido: no debe filtrarse entre tests.
	VirtualMouseScript.set_pointer_released(false)
	# El doble tap y el watchdog de inactividad son estado del autoload: tampoco debe filtrarse.
	PauseManager._touch_tap_was_passive = false
	PauseManager._last_touch_tap_msec = -100000
	PauseManager._reset_inactivity_timer()


func test_set_minimal_leaves_only_the_pausa_label() -> void:
	var menu = PauseMenuScene.instance()
	add_child(menu)

	var title = menu.find_node("Title")
	assert_str(String(title.text)).is_equal("PAUSA")

	menu.set_minimal(true)
	assert_bool(title.visible).is_true()
	assert_bool(menu.find_node("Resume").visible).is_false()
	assert_bool(menu.find_node("VersionLabel").visible).is_false()
	assert_float(menu.color.a).is_equal_approx(0.0, 0.001)

	menu.set_minimal(false)
	assert_bool(title.visible).is_true()
	assert_bool(menu.find_node("Resume").visible).is_true()
	assert_float(menu.color.a).is_greater(0.0)

	menu.queue_free()


func test_minimal_ignores_ui_cancel_so_the_first_input_only_restores() -> void:
	var menu = PauseMenuScene.instance()
	add_child(menu)
	menu.set_minimal(true)

	var event = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	menu._input(event) # no debe llamar a resume(): sin PauseManager, crashearia
	assert_bool(menu.find_node("Resume").visible).is_false()

	menu.queue_free()



func _mouse(button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


func _touch(index: int, at: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = at
	ev.pressed = true
	return ev


func _select() -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_SELECT
	ev.pressed = true
	return ev


func test_right_mouse_button_releases_the_mouse_but_never_pauses() -> void:
	# ui_cancel en el InputMap incluye el boton derecho: pausar es ESC, back o gamepad.
	assert_bool(PauseManager.is_pause_request(_mouse(BUTTON_RIGHT))).is_false()
	var esc := InputEventKey.new()
	esc.scancode = KEY_ESCAPE
	esc.pressed = true
	assert_bool(PauseManager.is_pause_request(esc)).is_true()


func test_gamepad_select_does_not_pause_and_start_accepts() -> void:
	# T6 (2026-09-24): Select (JOY_SELECT) ya NO es pausa. En juego libera el puntero e inhibe
	# el control del jugador sin congelar el mundo; con la pausa pasiva (menu oculto) revela el
	# menu (O15). Pausar es ESC/back. Start (JOY_START) sigue en ui_accept y PauseManager lo
	# intercepta solo con el menu oculto (con el menu visible cae a ui_accept y activa el item
	# enfocado).
	var select := InputEventJoypadButton.new()
	select.button_index = JOY_SELECT
	select.pressed = true
	assert_bool(PauseManager.is_pause_request(select)).is_false()

	var esc := InputEventKey.new()
	esc.scancode = KEY_ESCAPE
	esc.pressed = true
	assert_bool(PauseManager.is_pause_request(esc)).is_true()

	var start := InputEventJoypadButton.new()
	start.button_index = JOY_START
	start.pressed = true
	assert_bool(start.is_action_pressed("ui_accept")).is_true()
	assert_bool(PauseManager.is_pause_request(start)).is_false()
	assert_bool(start.is_action_pressed("skip")).is_false()


func test_start_pauses_with_the_same_minimal_pausa_label_as_focus_loss() -> void:
	# Start hace LA misma pausa que perder el foco: el PauseMenu reducido a "PAUSA".
	# Antes era una pausa propia sin ningun aviso en pantalla.
	var was_paused: bool = get_tree().paused
	var previous_menu = PauseManager.pause_menu_instance
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	get_tree().paused = false
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false

	PauseManager.pause_quick()
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager.is_quick_paused()).is_true()
	# El mismo aviso que al perder el foco: solo el titulo, sin oscurecer.
	assert_bool(menu.find_node("Title").visible).is_true()
	assert_bool(menu.find_node("Resume").visible).is_false()
	assert_float(menu.color.a).is_equal_approx(0.0, 0.001)

	get_tree().paused = was_paused
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	menu.queue_free()


func test_start_again_cancels_the_pause_instead_of_entering_the_menu() -> void:
	# Segunda pulsacion de Start: cancela, venga la pausa de Start o del menu completo.
	var was_paused: bool = get_tree().paused
	var previous_menu = PauseManager.pause_menu_instance
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	get_tree().paused = false
	PauseManager._quick_paused = false

	PauseManager.pause_quick()
	assert_bool(get_tree().paused).is_true()
	PauseManager.toggle_quick_pause()
	assert_bool(get_tree().paused).is_false()
	assert_bool(PauseManager.is_quick_paused()).is_false()

	# Y con el menu completo abierto (ESC) Start tampoco confirma: tambien cancela.
	PauseManager.pause()
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager.is_quick_paused()).is_false()
	PauseManager.toggle_quick_pause()
	assert_bool(get_tree().paused).is_false()

	get_tree().paused = was_paused
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	menu.queue_free()


func test_right_mouse_button_does_not_resume_from_the_full_menu() -> void:
	var menu = PauseMenuScene.instance()
	add_child(menu)
	menu.set_minimal(false)
	menu.show()
	get_tree().paused = true

	menu._input(_mouse(BUTTON_RIGHT))
	assert_bool(get_tree().paused).is_true() # sin _on_resume_pressed

	get_tree().paused = false
	menu.queue_free()


func test_left_click_on_the_focus_paused_game_resumes_it() -> void:
	# Pausa por perder el foco (solo la etiqueta PAUSA): el clic es "volver a jugar", no traer
	# el menu completo.
	var previous_menu = PauseManager.pause_menu_instance
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	PauseManager._menu_hidden_by_focus = true
	get_tree().paused = true

	PauseManager._input(_mouse(BUTTON_LEFT))
	assert_bool(get_tree().paused).is_false()
	assert_bool(menu.visible).is_false()

	# Cualquier otra entrada sigue trayendo el menu completo, sin reanudar.
	PauseManager._menu_hidden_by_focus = true
	get_tree().paused = true
	var key := InputEventKey.new()
	key.scancode = KEY_W
	key.pressed = true
	PauseManager._input(key)
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager._menu_hidden_by_focus).is_false()

	get_tree().paused = false
	PauseManager.pause_menu_instance = previous_menu
	menu.queue_free()


func test_double_tap_on_touch_resumes_the_passive_pause() -> void:
	# O2 (2026-09-24): en pantalla tactil no habia forma de salir de la pausa pasiva. Un solo
	# tap revela el menu (sigue igual); un DOBLE tap dentro de 300 ms/40 px reanuda directo.
	var previous_menu = PauseManager.pause_menu_instance
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	menu.set_minimal(true)
	PauseManager._menu_hidden_by_focus = true
	PauseManager._quick_paused = false
	get_tree().paused = true

	PauseManager._input(_touch(0, Vector2(100.0, 100.0)))
	# El primer tap revela el menu, todavia no reanuda.
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager._menu_hidden_by_focus).is_false()

	PauseManager._input(_touch(0, Vector2(104.0, 103.0)))
	assert_bool(get_tree().paused).is_false()
	assert_bool(menu.visible).is_false()

	get_tree().paused = false
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	menu.queue_free()


func test_a_single_tap_does_not_resume_and_a_far_second_tap_does_not_either() -> void:
	# El doble tap exige distancia <= 40 px: dos taps lejanos son dos toques distintos.
	var previous_menu = PauseManager.pause_menu_instance
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	menu.set_minimal(true)
	PauseManager._menu_hidden_by_focus = true
	PauseManager._quick_paused = false
	get_tree().paused = true

	PauseManager._input(_touch(0, Vector2(100.0, 100.0)))
	# Tras el primer tap el menu queda visible: el segundo tap lejano no reanuda.
	assert_bool(PauseManager._menu_hidden_by_focus).is_false()
	PauseManager._input(_touch(0, Vector2(300.0, 300.0)))
	assert_bool(get_tree().paused).is_true()

	get_tree().paused = false
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	menu.queue_free()


func test_select_toggles_the_pointer_between_release_and_recapture() -> void:
	# T7 (2026-09-24): Select alterna. Primero libera el puntero (cursor virtual, nunca el nativo);
	# con el puntero ya liberado, lo recaptura. Nunca pausa ni despausa.
	var select := InputEventJoypadButton.new()
	select.button_index = JOY_SELECT
	select.pressed = true
	assert_bool(PauseManager.is_pause_request(select)).is_false()

	VirtualMouseScript.set_pointer_released(false)
	PauseManager._toggle_select_control()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_true()

	PauseManager._toggle_select_control()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_false()


func test_select_reveals_the_passive_menu_and_toggles_the_pointer_in_gameplay() -> void:
	# O15 (2026-09-24): con la pausa pasiva (menu oculto) Select revela el menu en vez de
	# consumirse sin hacer nada. En gameplay sigue alternando el puntero y no pausa. Con el
	# menu completo visible no cambia nada.
	var previous_menu = PauseManager.pause_menu_instance
	var previous_scene = get_tree().current_scene
	var fake_scene = _install_fake_game_scene()
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	get_tree().paused = false
	VirtualMouseScript.set_pointer_released(false)

	# Gameplay: Select libera el puntero y no pausa.
	PauseManager._input(_select())
	assert_bool(get_tree().paused).is_false()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_true()

	# Pausa pasiva: Select revela el menu, no reanuda.
	PauseManager._menu_hidden_by_focus = true
	menu.set_minimal(true)
	get_tree().paused = true
	PauseManager._input(_select())
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager._menu_hidden_by_focus).is_false()
	assert_bool(menu._minimal).is_false()

	# Menu completo visible: Select no hace nada.
	var released_before: bool = VirtualMouseScript.is_pointer_released()
	PauseManager._input(_select())
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager._menu_hidden_by_focus).is_false()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_equal(released_before)

	get_tree().paused = false
	get_tree().current_scene = previous_scene
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	fake_scene.queue_free()
	menu.queue_free()


func test_start_passive_pause_does_not_release_or_request_the_cursor() -> void:
	# T8 (2026-09-24): Start entra en pausa pasiva sin liberar ni mostrar el cursor. El menu
	# minimal no cuenta como solicitante del cursor virtual; recien el movimiento lo revela y lo
	# pide (libera/muestra).
	VirtualMouseScript.set_pointer_released(false)
	var was_paused: bool = get_tree().paused
	var previous_menu = PauseManager.pause_menu_instance
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	get_tree().paused = false
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false

	PauseManager.pause_quick()
	assert_bool(get_tree().paused).is_true()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_false()
	assert_bool(menu._minimal).is_true()
	# El menu minimal no pide el cursor: no figura entre los requesters del cursor compartido.
	assert_bool(menu._cursor._requesters.has(menu)).is_false()

	# Al revelarse (movimiento de mouse/stick) vuelve a pedirlo y recien ahi lo libera/muestra.
	PauseManager._reveal_passive_menu()
	assert_bool(menu._minimal).is_false()
	assert_bool(menu._cursor._requesters.has(menu)).is_true()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_true()

	get_tree().paused = was_paused
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	menu.queue_free()


func test_jump_button_is_back_but_select_and_right_click_are_not() -> void:
	# B6 (2026-09-24): el boton de cara Jump (B) hace de "volver" como ui_cancel. Select y el clic
	# derecho tambien son ui_cancel pero no reanudan (Select alterna el puntero, el derecho lo suelta).
	var menu = PauseMenuScene.instance()
	add_child(menu)

	var jump := InputEventJoypadButton.new()
	jump.button_index = JOY_BUTTON_1
	jump.pressed = true
	assert_bool(menu._is_back_event(jump)).is_true()

	var select := InputEventJoypadButton.new()
	select.button_index = JOY_SELECT
	select.pressed = true
	assert_bool(menu._is_back_event(select)).is_false()

	var esc := InputEventKey.new()
	esc.scancode = KEY_ESCAPE
	esc.pressed = true
	assert_bool(menu._is_back_event(esc)).is_true()

	assert_bool(menu._is_back_event(_mouse(BUTTON_RIGHT))).is_false()

	menu.queue_free()


func _install_fake_game_scene() -> Node:
	# PauseManager no pausa sin escena de juego (menu/boot quedan fuera): el runner no tiene
	# current_scene, se le da una que no matchee Menu.tscn/Boot.tscn.
	var fake_scene := Node.new()
	fake_scene.name = "InactivityWatchdogTestScene"
	fake_scene.filename = "res://core_v2/tests/fixtures/inactivity_watchdog_test.tscn"
	get_tree().root.add_child(fake_scene)
	get_tree().current_scene = fake_scene
	return fake_scene


func test_inactivity_watchdog_fades_music_then_enters_the_passive_pause() -> void:
	# O5 (2026-09-24): 60 s sin input ni movimiento del jugador. Timer propio, separado del
	# auto-hide de 3 s. Al cumplirse arranca el fade (~4 s) y recien despues entra la pausa
	# pasiva de Start (asi el fade suena: con el arbol pausado el tween no avanzaria).
	var previous_menu = PauseManager.pause_menu_instance
	var previous_scene = get_tree().current_scene
	var fake_scene = _install_fake_game_scene()
	var menu = PauseMenuScene.instance()
	add_child(menu)
	PauseManager.pause_menu_instance = menu
	get_tree().paused = false
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	PauseManager._reset_inactivity_timer()

	PauseManager._process_inactivity(PauseManager.INACTIVITY_PAUSE_SEC - 1.0)
	assert_bool(PauseManager._inactivity_fade_pending).is_false()
	assert_bool(get_tree().paused).is_false()

	PauseManager._process_inactivity(1.0)
	assert_bool(PauseManager._inactivity_fade_pending).is_true()
	assert_bool(get_tree().paused).is_false() # el fade corre con el mundo sin pausar

	PauseManager._process_inactivity(PauseManager.INACTIVITY_MUSIC_FADE_SEC)
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager._menu_hidden_by_focus).is_true()
	assert_bool(PauseManager.is_quick_paused()).is_true()

	get_tree().paused = false
	get_tree().current_scene = previous_scene
	PauseManager.pause_menu_instance = previous_menu
	PauseManager._quick_paused = false
	PauseManager._menu_hidden_by_focus = false
	PauseManager._reset_inactivity_timer()
	fake_scene.queue_free()
	menu.queue_free()


func test_inactivity_watchdog_resets_with_input() -> void:
	# Cualquier input reinicia el conteo y cancela un fade pendiente.
	var previous_scene = get_tree().current_scene
	var fake_scene = _install_fake_game_scene()
	get_tree().paused = false
	PauseManager._menu_hidden_by_focus = false
	PauseManager._reset_inactivity_timer()

	PauseManager._process_inactivity(PauseManager.INACTIVITY_PAUSE_SEC - 1.0)
	PauseManager._input(_mouse(BUTTON_LEFT))
	PauseManager._process_inactivity(1.0)
	assert_bool(PauseManager._inactivity_fade_pending).is_false()
	assert_bool(get_tree().paused).is_false()

	get_tree().current_scene = previous_scene
	PauseManager._menu_hidden_by_focus = false
	PauseManager._reset_inactivity_timer()
	fake_scene.queue_free()

