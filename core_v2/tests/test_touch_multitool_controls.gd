extends GdUnitTestSuite

# test_touch_multitool_controls.gd - La UI tactil debe poder disparar el multitool y ciclar su
# modo. El click fantasma que el X server emula de cada toque apaga tool_fire_primary
# (MobileUIManager.is_pointer_from_touch); un boton explicito marca la accion que sintetiza para
# que InputProviderV2 la deje pasar sin reactivar ese bug (ver test_touch_mouse_emulation).

const MobileUIManagerScript = preload("res://core_v2/autoloads/MobileUIManager.gd")
const InputProviderV2Script = preload("res://core_v2/input/InputProviderV2.gd")
const TouchActionButtonScript = preload("res://core_v2/ui/TouchActionButton.gd")


func after_test() -> void:
	Input.action_release("tool_fire_primary")
	Input.action_release("tool_next_mode")
	Input.action_release("tool_prev_mode")
	MobileUIManager._touch_pointer_until = 0
	MobileUIManager._explicit_touch_actions.clear()
	MobileUIManager._touch_trackers.clear()
	MobileUIManager._is_touch_active = false


func _orphan_button(action: String) -> TouchActionButton:
	# get_node_or_null("/root/...") resuelve por el arbol: el boton tiene que estar adentro.
	var btn := TouchActionButtonScript.new()
	btn.action_name = action
	get_tree().root.add_child(btn)
	auto_free(btn)
	return btn


# El boton explicito de disparo marca su accion: el provider la deja pasar aunque el puntero
# sea "de touch" (el dedo apoyado en el propio boton es el que abre esa ventana).
func test_explicit_fire_button_fires_during_touch() -> void:
	var fire := _orphan_button("tool_fire_primary")
	var provider := InputProviderV2Script.new()

	MobileUIManager._touch_pointer_until = OS.get_ticks_msec() + 10000 # dedo apoyado
	fire._press()
	assert_bool(MobileUIManager.is_touch_action_explicit("tool_fire_primary")).is_true()
	assert_bool(provider.get_input().tool_fire_primary).is_true()

	fire._release()
	assert_bool(MobileUIManager.is_touch_action_explicit("tool_fire_primary")).is_false()
	# Sigue dentro de la ventana del fantasma: sin marca explicita vuelve a suprimirse.
	assert_bool(provider.get_input().tool_fire_primary).is_false()


# La regresion del click fantasma no se reabre: sin boton explicito sigue apagado.
func test_phantom_click_still_suppressed_without_explicit_button() -> void:
	var provider := InputProviderV2Script.new()
	MobileUIManager._touch_pointer_until = OS.get_ticks_msec() + 10000
	Input.action_press("tool_fire_primary")
	assert_bool(provider.get_input().tool_fire_primary).is_false()


# Los botones de modo sintetizan tool_next_mode/tool_prev_mode, que el provider lee como flanco
# y MultiToolV2 usa en step() -> _switch_mode(dir).
func test_tool_mode_buttons_synthesize_cycle_actions() -> void:
	var next_btn := _orphan_button("tool_next_mode")
	next_btn._press()
	assert_bool(Input.is_action_pressed("tool_next_mode")).is_true()
	next_btn._release()
	assert_bool(Input.is_action_pressed("tool_next_mode")).is_false()

	var prev_btn := _orphan_button("tool_prev_mode")
	prev_btn._press()
	assert_bool(Input.is_action_pressed("tool_prev_mode")).is_true()
	prev_btn._release()
	assert_bool(Input.is_action_pressed("tool_prev_mode")).is_false()


# El .tscn trae los controles nuevos cableados a las acciones correctas.
func test_mobile_ui_scene_has_fire_and_tool_buttons() -> void:
	var mgr = MobileUIManagerScript.new()
	get_tree().root.add_child(mgr)
	mgr._is_mobile = true
	mgr._is_touch_active = true
	mgr._spawn_mobile_ui()
	assert_object(mgr._mobile_ui).is_not_null()
	if mgr._mobile_ui == null:
		mgr.queue_free()
		return
	var container: Control = mgr._mobile_ui.get_node("Container")

	var fire: Control = container.get_node_or_null("ActionButtons/FireButton")
	assert_object(fire).is_not_null()
	if fire != null:
		assert_str(String(fire.action_name)).is_equal("tool_fire_primary")

	var prev_btn: Control = container.get_node_or_null("ToolButtons/ToolPrevButton")
	var next_btn: Control = container.get_node_or_null("ToolButtons/ToolNextButton")
	assert_object(prev_btn).is_not_null()
	assert_object(next_btn).is_not_null()
	if prev_btn != null:
		assert_str(String(prev_btn.action_name)).is_equal("tool_prev_mode")
	if next_btn != null:
		assert_str(String(next_btn.action_name)).is_equal("tool_next_mode")

	mgr.queue_free()
