extends GdUnitTestSuite

const PauseMenuScene = preload("res://core_v2/ui/PauseMenu.tscn")


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


func test_right_mouse_button_releases_the_mouse_but_never_pauses() -> void:
	# ui_cancel en el InputMap incluye el boton derecho: pausar es ESC, back o gamepad.
	assert_bool(PauseManager.is_pause_request(_mouse(BUTTON_RIGHT))).is_false()
	var esc := InputEventKey.new()
	esc.scancode = KEY_ESCAPE
	esc.pressed = true
	assert_bool(PauseManager.is_pause_request(esc)).is_true()


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
