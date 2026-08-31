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
