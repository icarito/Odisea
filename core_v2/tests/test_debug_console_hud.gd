extends GdUnitTestSuite

func test_debug_console_is_a_hud_screen_with_its_statusbar_text() -> void:
	yield(get_tree(), "idle_frame")
	var screen = get_node_or_null("/root/DebugConsoleManager")
	assert_object(screen).is_not_null()
	assert_str(screen.screen_id()).is_equal("system:console")
	assert_str(String(screen.widget_snapshot().get("status_text", ""))).is_equal("OK")
	assert_object(screen.widget_scene()).is_not_null()
	assert_object(screen.view_scene()).is_not_null()
	assert_bool(screen.view_requires_input()).is_true()
	assert_object(screen.borrow_viewport()).is_not_null()
	assert_float(float(screen.view_hud_config().get("background_alpha", 0.0))).is_equal_approx(0.42, 0.001)
	screen.enter_focus_mode()
	var cursor_before: Vector2 = screen._viewport._cursor_position
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(12.0, -8.0)
	screen.forward_view_input(motion)
	assert_vector2(screen._viewport._cursor_position).is_equal(cursor_before + motion.relative)
	screen.exit_focus_mode()
	# El manager se registra solo en escena gameplay (y la suite completa corre
	# despues de tests como test_hudable que vacian SuitOS), asi que aca se rehace
	# el alta: el test verifica el contrato de la pantalla, no el timing del autoload.
	SuitOS.register_screen(screen)
	assert_bool(SuitOS.has_screen(screen.screen_id())).is_true()
