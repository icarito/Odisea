extends GdUnitTestSuite

# test_hud_mode.gd - Modo HUD local de OdiseaOS (FD-296 F3).
# Con el overlay abierto el arbol queda pausado: todo lo que pasa entre abrir y cerrar es
# sincronico (sin yields), porque el runner no es PAUSE_MODE_PROCESS.

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
const HoloTerminalWidgetScript = preload("res://core_v2/ui/hud/HoloTerminalWidget.gd")
const HangingDisplayScene = preload("res://core_v2/levels/interiors/DomeIntroCryoDiagnosticsDisplay.tscn")
const CRYO_UI_PATH := "res://core_v2/levels/interiors/DomeIntroCryoDiagnosticsUI.tscn"

var _overlay_mgr = null
var _fake_scene: Node = null


func before() -> void:
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)
	# El runner de linea de comandos no tiene current_scene, y PauseManager no pausa sin una
	# escena de juego (menu/boot quedan fuera): se le da una.
	if get_tree().current_scene == null:
		_fake_scene = Node.new()
		_fake_scene.name = "HudModeTestScene"
		_fake_scene.filename = "res://core_v2/tests/fixtures/hud_mode_test.tscn"
		get_tree().root.add_child(_fake_scene)
		get_tree().current_scene = _fake_scene


func after() -> void:
	if is_instance_valid(_fake_scene):
		get_tree().current_scene = null
		_fake_scene.free()


func before_test() -> void:
	_overlay_mgr = get_tree().root.get_node("OverlayUIManager")
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.unpin_screen()


func after_test() -> void:
	SuitOS.close_hud_mode()
	SuitOS.unpin_screen()
	get_tree().paused = false
	# El overlay cerrado queda en queue_free hasta fin de frame; el proximo test lo necesita libre.
	yield(await_idle_frame(), "completed")


func _action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _screen(id: String, title: String) -> Node:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = id
	screen.hud_screen_title = title
	add_child(screen)
	return screen


func _overlay() -> Node:
	var node = _overlay_mgr.get_slot(_overlay_mgr.SLOT_MODAL).get_node_or_null(SuitOS.HUD_MODE_OVERLAY)
	if node == null or node.is_queued_for_deletion():
		return null
	return node


# Frames grabados tal como los escribe SessionManager (InputDataV2.to_dict()).
func _replay_provider(frames: Array) -> InputProviderV2:
	var provider := InputProviderV2.new()
	var buffer: Array = []
	for frame in frames:
		var data := InputDataV2.new()
		data.from_dict(frame)
		buffer.append({"input": data.to_dict()})
	provider.set_replay_data(buffer)
	return provider


# Gesto hacia arriba (mouse_delta +Y = arriba) y luego click: con dos pantallas el dial pone
# la primera a las 6 y la segunda a las 12, asi que elige la segunda.
func _pick_second_by_stream(overlay: Node) -> void:
	overlay.input_provider = _replay_provider([
		{"mouse_delta": [0.0, 12.0]},
		{"tool_fire_primary": true},
	])
	overlay._physics_process(1.0 / 60.0)
	overlay._physics_process(1.0 / 60.0)


func test_tab_opens_and_closes_overlay_pausing_the_world() -> void:
	_screen("test:a", "Alpha")
	SuitOS._input(_action("hud_mode"))
	var overlay = _overlay()
	assert_object(overlay).is_not_null()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(PauseManager.is_hud_mode_paused()).is_true()
	assert_object(PauseManager.pause_menu_instance).is_null()

	# ESC con el modo HUD abierto no es de PauseManager: no toca la pausa ni abre el menu.
	PauseManager._input(_action("ui_cancel"))
	assert_bool(get_tree().paused).is_true()

	overlay._input(_action("hud_mode"))
	assert_object(_overlay()).is_null()
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(PauseManager.is_hud_mode_paused()).is_false()


func test_ui_cancel_exits() -> void:
	SuitOS.open_hud_mode()
	_overlay()._input(_action("ui_cancel"))
	assert_object(_overlay()).is_null()
	assert_bool(get_tree().paused).is_false()


func test_overlay_lives_in_modal_slot_and_processes_in_pause() -> void:
	assert_bool(SuitOS.open_hud_mode()).is_true()
	var overlay = _overlay()
	assert_object(overlay).is_not_null()
	assert_object(overlay.get_parent()).is_equal(_overlay_mgr.get_slot(_overlay_mgr.SLOT_MODAL))
	assert_int(overlay.pause_mode).is_equal(Node.PAUSE_MODE_PROCESS)
	assert_bool(overlay.can_process()).is_true()


func test_radial_options_match_registered_screens() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.open_hud_mode()
	var overlay = _overlay()
	assert_array(overlay._screen_ids).is_equal(SuitOS.get_registered_screens())
	var titles: Array = []
	for label in overlay._selector._buttons:
		titles.append(label.text)
	assert_array(titles).is_equal(["Alpha", "Beta"])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_bool(overlay._placeholder.visible).is_false()


func test_single_screen_skips_the_radial() -> void:
	_screen("test:a", "Alpha")
	SuitOS.open_hud_mode()
	var overlay = _overlay()
	assert_bool(overlay._selector.visible).is_false()
	assert_str(SuitOS.get_pinned_screen_id()).is_equal("test:a")
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	assert_int(overlay._view_host.get_child_count()).is_equal(1)


func test_stream_confirm_pins_slot_b_and_persists() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.open_hud_mode()
	_pick_second_by_stream(_overlay())

	assert_str(SuitOS.get_pinned_screen_id()).is_equal("test:b")
	assert_str(String(SuitOS.get_slot_snapshot("slot_b").get("id", ""))).is_equal("test:b")
	assert_str(_overlay()._slots_label.text).contains("B · Beta")
	# Persistencia: viaja por el contrato replay_sync de SuitOS.
	var saved: Dictionary = SuitOS.get_snapshot()
	assert_str(String(saved.get("pinned_screen_id", ""))).is_equal("test:b")


func test_replaying_the_same_stream_picks_the_same_screen() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.open_hud_mode()
	_pick_second_by_stream(_overlay())
	var first_pick: String = SuitOS.get_pinned_screen_id()
	SuitOS.close_hud_mode()
	SuitOS.unpin_screen()
	yield(await_idle_frame(), "completed")

	SuitOS.open_hud_mode()
	_pick_second_by_stream(_overlay())
	assert_str(SuitOS.get_pinned_screen_id()).is_equal(first_pick)


func test_held_button_at_open_does_not_confirm() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.open_hud_mode()
	var overlay = _overlay()
	overlay.input_provider = _replay_provider([{"mouse_delta": [0.0, 12.0], "tool_fire_primary": true}])
	overlay._physics_process(1.0 / 60.0)
	assert_str(SuitOS.get_pinned_screen_id()).is_empty()


func test_view_falls_back_to_enlarged_widget_when_view_scene_is_null() -> void:
	var screen = _screen("test:w", "Widget Only")
	screen.hud_widget_scene = HoloTerminalWidgetScene
	SuitOS.open_hud_mode()
	var overlay = _overlay()

	var widget = overlay._view_host.get_node_or_null("WidgetFallback")
	assert_object(widget).is_not_null()
	assert_object(widget.get_script()).is_equal(HoloTerminalWidgetScript)
	assert_float(widget.rect_scale.x).is_greater(1.0)
	assert_bool(overlay._selector.is_open()).is_false()


func test_holoterminal_view_reuses_the_terminal_ui() -> void:
	var display = auto_free(HangingDisplayScene.instance())
	add_child(display)
	var hudable = display.get_node("HoloTerminalHUDable")
	assert_object(hudable.view_scene()).is_not_null()
	assert_str(hudable.view_scene().resource_path).is_equal(CRYO_UI_PATH)

	SuitOS.open_hud_mode() # Unica pantalla: va directo a la vista.
	var overlay = _overlay()
	assert_int(overlay._view_host.get_child_count()).is_equal(1)
	var view = overlay._view_host.get_child(0)
	assert_str(view.filename).is_equal(CRYO_UI_PATH)
	# A la resolucion del Viewport del terminal, no estirada al espacio de UI del juego.
	assert_vector2(view.rect_size).is_equal(hudable.view_size())
	assert_vector2(view.rect_size).is_equal(Vector2(1280, 816))


func test_empty_registry_shows_placeholder() -> void:
	SuitOS.open_hud_mode()
	var overlay = _overlay()
	assert_bool(overlay._placeholder.visible).is_true()
	assert_str(overlay._placeholder.text).is_equal("SIN PANTALLAS")
	assert_bool(overlay._selector.is_open()).is_false()


func test_suitos_snapshot_restore_intact() -> void:
	_screen("test:a", "Alpha")
	SuitOS.pin_screen("test:a")
	var saved: Dictionary = SuitOS.get_snapshot()
	assert_array(saved.keys()).contains_exactly_in_any_order(["pinned_screen_id", "last_snapshots"])
	# JSON-safe: sobrevive ida y vuelta por JSON sin perder nada.
	assert_str(to_json(parse_json(to_json(saved)))).is_equal(to_json(saved))

	SuitOS.unpin_screen()
	SuitOS.restore_snapshot(saved)
	assert_str(SuitOS.get_pinned_screen_id()).is_equal("test:a")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
