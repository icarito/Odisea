extends GdUnitTestSuite

# test_hud_mode.gd - Modo HUD local de OdiseaOS (FD-296 F3, spec 4 + Verification 1/1b).
# Con el overlay abierto el arbol queda pausado: todo lo que pasa entre abrir y cerrar es
# sincronico (sin yields), porque el runner no es PAUSE_MODE_PROCESS. El input entra como
# frames grabados (InputDataV2.to_dict), igual que en un replay.

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
const HoloTerminalWidgetScript = preload("res://core_v2/ui/hud/HoloTerminalWidget.gd")
const HangingDisplayScene = preload("res://core_v2/levels/interiors/DomeIntroCryoDiagnosticsDisplay.tscn")
const RadialSelectorScene = preload("res://core_v2/ui/radial/RadialSelectorV2.tscn")
const Gesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const HudOverlayScript = preload("res://core_v2/ui/hud/HudModeOverlay.gd")
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
	# Sin la ultima posicion del puntero de otra suite: el host la usa para decidir si un toque es de
	# un boton del widget.
	SuitOS.get_node("SuitOSWidgetHost")._last_pointer_position = Vector2(-10000, -10000)
	# Ni una cinematica que otra suite dejo abierta: esconde los widgets.
	SuitOS.get_node("SuitOSWidgetHost")._cinematic_active = false
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.clear_slots()
	# FD-305: el dial muestra los FAVORITOS, no el registry. Cada suite arranca sin curaduria y
	# _screen() favoritea lo que registra, que es lo que estos casos siempre dieron por sentado.
	SuitOS.clear_favorites()
	SuitOS._last_snapshots_cache.clear()
	# FD-305: el dial pasa a mostrar los FAVORITOS y no el registry. Esta suite es de la mecanica
	# del dial, no de la curaduria (esa vive en test_hud_drawer.gd), asi que cada pantalla que se
	# registra entra sola al arco y los casos siguen diciendo lo mismo que siempre dijeron.
	if not SuitOS.is_connected("screen_registered", self, "_auto_favorite"):
		SuitOS.connect("screen_registered", self, "_auto_favorite")


func _auto_favorite(id: String) -> void:
	if not SuitOS.is_favorite(id):
		SuitOS.toggle_favorite(id)


func after_test() -> void:
	if SuitOS.is_connected("screen_registered", self, "_auto_favorite"):
		SuitOS.disconnect("screen_registered", self, "_auto_favorite")
	SuitOS.close_hud_mode()
	SuitOS.clear_slots()
	get_tree().paused = false
	# El overlay cerrado queda en queue_free hasta fin de frame; el proximo test lo necesita libre.
	yield(await_idle_frame(), "completed")


func _action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _screen(id: String, title: String, relevance: float = 0.0) -> Node:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = id
	screen.hud_screen_title = title
	screen.default_relevance = relevance
	add_child(screen)
	return screen


func _overlay() -> Node:
	var node = _overlay_mgr.get_slot(_overlay_mgr.SLOT_MODAL).get_node_or_null(SuitOS.HUD_MODE_OVERLAY)
	if node == null or node.is_queued_for_deletion():
		return null
	return node


# Abre con TAB y reproduce frames grabados, uno por tick de fisica, como un replay.
func _open_and_play(frames: Array) -> Node:
	SuitOS._input(_action("hud_mode"))
	var overlay = _overlay()
	_play(overlay, frames)
	return overlay


# Abre con TAB y descarta ese gesto de apertura (como hace show_for_slot): asi la muestra inicial
# del stream no se lee como tap de TAB y se puede probar solo el stream del hombro.
func _open_and_play_slot(frames: Array) -> Node:
	SuitOS._input(_action("hud_mode"))
	var overlay = _overlay()
	overlay._gesture.consume()
	_play(overlay, frames)
	return overlay


func _play(overlay: Node, frames: Array) -> void:
	var provider := InputProviderV2.new()
	var buffer: Array = []
	for frame in frames:
		var data := InputDataV2.new()
		data.from_dict(frame)
		buffer.append({"input": data.to_dict()})
	provider.set_replay_data(buffer)
	overlay.input_provider = provider
	for _i in range(frames.size()):
		if is_instance_valid(overlay) and not overlay.is_queued_for_deletion():
			overlay._physics_process(1.0 / 60.0)


# Abre directo en una pantalla (tap sobre el widget de su slot) y reproduce frames.
func _open_screen_and_play(id: String, frames: Array) -> Node:
	assert_bool(SuitOS.open_hud_mode(false, id)).is_true()
	var overlay = _overlay()
	_play(overlay, frames)
	return overlay


func _await_overlay_freed() -> void:
	var slot = _overlay_mgr.get_slot(_overlay_mgr.SLOT_MODAL)
	for _i in range(30):
		yield(await_idle_frame(), "completed")
		if slot.get_node_or_null(SuitOS.HUD_MODE_OVERLAY) == null:
			return


func _held(ticks: int) -> Array:
	var frames: Array = []
	for _i in range(ticks):
		frames.append({"hud_mode": true})
	return frames


const UP := {"hud_mode": false}
# Confirmar lo marcado en el dial. Desde 2026-09-20 soltar el boton del HUD ya no elige:
# sostenerlo abre el cajon (Manual §5, verbos 1 y 5), asi que el dial se confirma aparte.
const CONFIRM := {"tool_fire_primary": true}


func test_tab_pauses_without_pause_menu_and_ui_cancel_exits() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([])
	assert_object(overlay).is_not_null()
	assert_object(overlay.get_parent()).is_equal(_overlay_mgr.get_slot(_overlay_mgr.SLOT_MODAL))
	assert_int(overlay.pause_mode).is_equal(Node.PAUSE_MODE_PROCESS)
	assert_bool(get_tree().paused).is_true()
	assert_int(CinematicManager.pause_mode).is_equal(Node.PAUSE_MODE_PROCESS)
	assert_bool(PauseManager.is_hud_mode_paused()).is_true()
	assert_object(PauseManager.pause_menu_instance).is_null()
	# ESC con el modo HUD abierto no es de PauseManager: no toca la pausa ni abre el menu.
	PauseManager._input(_action("ui_cancel"))
	assert_bool(get_tree().paused).is_true()

	overlay._input(_action("ui_cancel"))
	assert_object(_overlay()).is_null()
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_tap_opens_the_radial_even_with_a_pinned_screen() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(0, "test:b")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_empty()


func test_tap_without_pin_or_last_screen_opens_the_radial() -> void:
	# Nada se sugiere: sin pantalla fijada ni ultima abierta, el tap deja elegir.
	_screen("test:a", "Alpha", 0.9)
	_screen("test:b", "Beta", 0.0)
	SuitOS.set_context({})
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])


func test_hold_opens_the_drawer_not_the_dial() -> void:
	# Decision de Sebastian 2026-09-20 (Manual, Apendice A punto 1): tap = tus favoritos (el
	# dial), hold = todo (el cajon). Antes tap y hold abrian los dos el dial, o sea el hold
	# no tenia significado propio y no habia nada que ensenar.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS - 1))
	assert_bool(overlay._drawer_open()).is_false() # 0.38 s: todavia no
	assert_bool(overlay._selector.is_open()).is_false()
	_play(overlay, _held(1))
	assert_bool(overlay._drawer_open()).is_true()
	assert_bool(overlay._selector.is_open()).is_false() # el dial no aparece
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	# Soltar no elige nada: el cajon se queda, que es lo que se pidio.
	_play(overlay, [UP])
	assert_bool(overlay._drawer_open()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_empty()


func test_hold_over_a_screen_opens_the_drawer_and_closes_that_screen() -> void:
	# Desde una pantalla abierta, sostener lleva al cajon: es la lista completa, y es la unica
	# ruta para cambiar de pantalla sin volver al juego (tap vuelve al jugador).
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:a", [UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	_play(overlay, _held(Gesture.HOLD_TICKS))
	assert_bool(overlay._drawer_open()).is_true()
	# La pantalla que estaba abierta se cierra: el cajon no se monta encima de una vista.
	assert_str(SuitOS.get_active_screen_id()).is_empty()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func test_tap_over_a_screen_goes_back_to_the_player() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:a", [UP])
	# Con varias pantallas tampoco abre el dial: vuelve al jugador.
	_play(overlay, [{"hud_mode": true}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_gamepad_hud_tap_exits_a_single_open_screen() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	_play(overlay, [{"hud_mode": true}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_tap_with_a_single_screen_opens_it_directly() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_false()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")


# Mantener TAB, apuntar hacia arriba (mouse_delta +Y = arriba) y soltar: con dos pantallas el
# dial pone la primera a las 6 y la segunda a las 12, y soltar elige lo marcado.
# En tandas separadas (un tick por frame, como en el juego): en una sola tanda el hover no se
# asienta y el release termina eligiendo el centro. El delta va al radio de apuntado completo,
# no a 60 px: el radio de acierto del hub escala con el dial y en la ventana de CI es 65 px.
# Tap para abrir el dial, apuntar, y confirmar. El boton del HUD queda suelto todo el
# tiempo: sostenerlo abriria el cajon.
func _open_and_pick_second():
	var overlay = _open_and_play([UP])
	_play(overlay, [{"mouse_delta": [0.0, overlay_aim_radius()]}])
	_play(overlay, [CONFIRM])
	return overlay


func overlay_aim_radius() -> float:
	return HudOverlayScript.AIM_RADIUS


func test_confirming_in_the_dial_opens_the_screen_and_closes_the_dial() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	# Apuntado y disparo en tandas separadas, como llegan los ticks en el juego (uno por frame):
	# en una sola tanda el hover no se asienta y el disparo termina confirmando el centro. Y el
	# delta va al radio de apuntado completo, no a 60 px: el radio de acierto del hub escala con
	# el tamanio del dial y en la ventana de CI (1066x600) es 65 px, asi que 60 caia adentro.
	var overlay = _open_and_play([UP])
	_play(overlay, [{"mouse_delta": [0.0, overlay_aim_radius()]}])
	_play(overlay, [CONFIRM])
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_bool(overlay._selector.is_open()).is_false()
	# Un tick mas sin tocar nada no cancela la pantalla mientras entra su transicion.
	_play(overlay, [{}])
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func test_gesture_reports_the_release_that_ends_a_hold() -> void:
	var g = Gesture.new()
	for _i in range(Gesture.HOLD_TICKS - 1):
		assert_int(g.feed(true)).is_equal(Gesture.NONE)
	assert_int(g.feed(true)).is_equal(Gesture.HOLD)
	assert_int(g.feed(true)).is_equal(Gesture.NONE) # sigue apretado
	assert_int(g.feed(false)).is_equal(Gesture.HOLD_RELEASE)
	assert_int(g.feed(false)).is_equal(Gesture.NONE)

	# Un tap no es fin de hold.
	assert_int(g.feed(true)).is_equal(Gesture.NONE)
	assert_int(g.feed(false)).is_equal(Gesture.TAP)

	# consume() olvida la pulsacion: su release tampoco cuenta como fin de hold.
	for _i in range(Gesture.HOLD_TICKS):
		g.feed(true)
	g.consume()
	assert_int(g.feed(false)).is_equal(Gesture.NONE)


func test_tab_radial_pick_opens_the_screen_without_pinning_it() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	_open_and_pick_second()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	# Nada se autoasigna: elegir con TAB no llena un slot.
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])


# Verification 1b: el mismo input grabado da el mismo resultado, sin leer estado en vivo.
func test_replaying_the_same_stream_gives_the_same_result() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	_open_and_pick_second()
	var first: Array = [SuitOS.get_pinned_slots(), SuitOS.get_active_screen_id()]
	SuitOS.close_hud_mode()
	SuitOS.clear_slots()
	yield(_await_overlay_freed(), "completed")

	_open_and_pick_second()
	assert_array([SuitOS.get_pinned_slots(), SuitOS.get_active_screen_id()]).is_equal(first)


func test_single_screen_never_shows_the_radial() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_false()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")


# En el telefono no hay TAB: el widget del slot es el boton. Tap = la pantalla de ESE slot.
# Simetrico con abrir tocando el widget del slot: tocar fuera de la pantalla la cierra.
func test_tap_outside_the_view_closes_the_hud_mode() -> void:
	_screen("test:a", "Alpha") # sin view_scene: la vista es el widget ampliado, centrado
	var overlay = _open_and_play([UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	var inside: Vector2 = overlay._view_screen_rect().position + overlay._view_screen_rect().size * 0.5
	overlay._input(_touch(true, inside))
	overlay._input(_touch(false, inside))
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	overlay._input(_touch(true, Vector2.ZERO)) # la esquina nunca es la pantalla
	overlay._input(_touch(false, Vector2.ZERO))
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func _touch(pressed: bool, at: Vector2 = Vector2.ZERO) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.position = at
	return ev


func _mouse_click(pressed: bool, at: Vector2 = Vector2.ZERO, button: int = BUTTON_LEFT) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = at
	return ev


func _screen_drag(at: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.position = at
	return ev


func _mouse_motion(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.relative = relative
	return ev


func _wheel(button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


func test_widget_tap_opens_the_screen_of_that_slot() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	host._active_screen_ids["slot_2"] = "test:b"
	var widget: Control = auto_free(Control.new())
	host._on_widget_gui_input(_touch(true), widget, "slot_2")
	host._on_widget_gui_input(_touch(false), widget, "slot_2")
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	_play(_overlay(), [UP]) # el dedo ya se solto: eso no es un tap que cierre
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func test_widget_hold_without_moving_opens_nothing() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(2, "test:a")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget: Control = auto_free(Control.new())
	host._active_screen_ids["slot_3"] = "test:a"
	host._on_widget_gui_input(_touch(true), widget, "slot_3")
	host._press_msec = OS.get_ticks_msec() - 500 # > HOLD_MSEC
	host._on_widget_gui_input(_touch(false), widget, "slot_3")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_closing_the_hud_mode_does_not_trigger_the_widget_underneath() -> void:
	# Tocar fuera de la pantalla cierra el modo HUD; el release de ese toque le llega al widget que
	# abrio el modo (ultimo foco de mouse de la GUI) y no debe volver a abrirlo.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	host._active_screen_ids["slot_1"] = "test:a"
	var widget: Control = auto_free(Control.new())
	host._on_widget_gui_input(_touch(true), widget, "slot_1")
	host._on_widget_gui_input(_touch(false), widget, "slot_1")
	var overlay = _overlay()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	overlay._input(_touch(true, Vector2.ZERO))
	overlay._input(_touch(false, Vector2.ZERO))
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	# El release suelto (sin press sobre el widget) no es un tap ni un hold.
	host._press_msec = OS.get_ticks_msec() - 500
	host._on_widget_gui_input(_touch(false), widget, "slot_1")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_touch_hold_opens_the_radial_directly() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	_play(overlay, [UP]) # el boton ya se solto: eso no es un tap que cierre
	assert_bool(overlay._selector.is_open()).is_true()


func test_radial_hides_the_elevator_needle_but_the_dial_keeps_it() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.show_indicator).is_false()
	assert_bool(overlay._selector._indicator.visible).is_false()
	# El default del dial (el del ascensor) sigue mostrando la aguja.
	var dial = auto_free(RadialSelectorScene.instance())
	add_child(dial)
	dial.set_options(["1", "2", "3"])
	assert_bool(dial._indicator.visible).is_true()


func test_holoterminal_view_is_a_hologram_presenter() -> void:
	var display = auto_free(HangingDisplayScene.instance())
	add_child(display)
	display.set_active(true, true)
	display.get_node("ScreenContainer/ScreenMesh").visible = true
	var source_viewport: Viewport = display.get_node("Viewport")
	var source_update_mode: int = source_viewport.render_target_update_mode
	var overlay = _open_and_play([UP]) # unica pantalla: tap = vista
	# Primero se ve solo la pantalla diegetica mientras la camara llega al FocusedRig.
	assert_object(overlay._mount.get_presenter()).is_null()
	assert_bool(display.get_node("ScreenContainer/ScreenMesh").visible).is_true()
	display.get_node("CinematicSetup/FocusedRig/Camera").current = true
	overlay._physics_process(1.0 / 60.0)
	var presenter = overlay._mount.get_presenter()
	assert_object(presenter).is_not_null()
	var mesh = presenter._get_hud_attach_target()
	assert_object(mesh).is_not_null()
	assert_bool(mesh.visible).is_false()
	assert_bool(display.get_node("ScreenContainer/ScreenMesh").visible).is_true()
	overlay._complete_focus_swap()
	assert_object(presenter.get_parent()).is_equal(get_tree().current_scene)
	assert_int(presenter.pause_mode).is_equal(Node.PAUSE_MODE_PROCESS)
	assert_bool(presenter.is_in_group("replay_sync")).is_false()
	assert_bool(presenter.is_active).is_true()
	assert_bool(presenter.is_ui_interactive()).is_false()
	assert_bool(presenter.is_processing_input()).is_false()
	assert_int(presenter.get_node("Viewport").render_target_update_mode).is_equal(Viewport.UPDATE_DISABLED)
	assert_object(overlay._mount._shared_screen).is_equal(display.get_node("HoloTerminalHUDable"))
	assert_bool(source_viewport.get("_ui_mode_active")).is_true()
	var cursor_start: Vector2 = source_viewport.get("_cursor_position")
	# La sensibilidad sale de PlayerUISettings (1.8 con jugador, 1.0 sin el): el delta se
	# escala con ella, no es fijo.
	var sensitivity: float = float(source_viewport.cursor_sensitivity)
	source_viewport.process_mouse_motion(Vector2(24.0, 12.0))
	assert_vector2(source_viewport.get("_cursor_position")) \
		.is_equal(cursor_start + Vector2(24.0, 12.0) * sensitivity)
	var persisted_cursor: Vector2 = source_viewport.get("_cursor_position")
	source_viewport.set_ui_mode(false)
	assert_bool(source_viewport.get("_cursor_visual").visible).is_false()
	source_viewport.set_ui_mode(true)
	assert_vector2(source_viewport.get("_cursor_position")).is_equal(persisted_cursor)
	assert_bool(source_viewport.get("_cursor_visual").visible).is_true()
	source_viewport.process_mouse_click(BUTTON_LEFT, true)
	assert_int(source_viewport.get("_mouse_button_mask")).is_equal(BUTTON_MASK_LEFT)
	assert_str(source_viewport.get_node("CryoDiagnosticsUI").filename).is_equal(CRYO_UI_PATH)
	assert_vector2(presenter.screen_resolution).is_equal(source_viewport.size)
	# Sin piso de vidrio; la transparencia propia del canvas sigue en la textura.
	assert_float(presenter.hud_cfg_background_alpha).is_equal_approx(0.0, 0.001)
	assert_float(presenter.hud_cfg_background_emission).is_equal_approx(3.0, 0.001)
	assert_float(presenter.hud_cfg_attach_transition_time).is_equal(0.0)
	assert_float(presenter.hud_cfg_screen_depth).is_equal(1.0)
	assert_bool(mesh.visible).is_true()
	assert_bool(display.get_node("ScreenContainer/ScreenMesh").visible).is_false()
	assert_int(source_viewport.render_target_update_mode).is_equal(Viewport.UPDATE_ALWAYS)

	# El reemplazo desaparece en el mismo frame; no vuelve a cruzarse con la fuente.
	SuitOS.close_hud_mode()
	yield(await_idle_frame(), "completed")
	assert_bool(display.get_node("ScreenContainer/ScreenMesh").visible).is_true()
	assert_int(source_viewport.render_target_update_mode).is_equal(source_update_mode)
	assert_bool(is_instance_valid(presenter)).is_false()
	assert_bool(is_instance_valid(mesh)).is_false()


func test_view_falls_back_to_enlarged_widget_when_view_scene_is_null() -> void:
	var screen = _screen("test:w", "Widget Only")
	screen.hud_widget_scene = HoloTerminalWidgetScene
	var overlay = _open_and_play([UP])
	var widget = overlay._mount.get_widget()
	assert_object(widget).is_not_null()
	assert_object(widget.get_script()).is_equal(HoloTerminalWidgetScript)
	assert_object(widget.get_parent()).is_equal(overlay._view_host)
	assert_float(widget.rect_scale.x).is_greater(1.0)
	assert_object(overlay._mount.get_presenter()).is_null()


func test_empty_registry_shows_placeholder_and_tap_still_closes() -> void:
	var overlay = _open_and_play([UP])
	assert_bool(overlay._placeholder.visible).is_true()
	assert_str(overlay._placeholder.text).is_equal("SIN PANTALLAS")
	_play(overlay, [{"hud_mode": true}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


# El velo 2D se dibuja encima del 3D: vive dentro del radial (solo detras de su texto) y es
# liviano; la vista holografica queda sin velo, con su propio brillo.
func test_veil_is_light_and_only_behind_the_radial() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:a", [UP])
	var dim: ColorRect = overlay.get_node("RadialSelector/Dim")
	assert_float(dim.color.a).is_less_equal(0.5)
	assert_bool(dim.is_visible_in_tree()).is_false()
	# El dial solo aparece con un tap desde el juego (sostener va al cajon).
	_play(overlay, [{"hud_mode": true}, UP]) # tap: vuelve al jugador
	overlay = _open_and_play([UP])
	dim = overlay.get_node("RadialSelector/Dim")
	assert_bool(dim.is_visible_in_tree()).is_true()


class FocusableDummyScreen:
	extends HUDableComponent

	var enter_called: bool = false
	var exit_called: bool = false

	func view_transition_origin() -> Dictionary:
		return {"kind": "focus_rig", "path": NodePath("DummyRig")}

	func enter_focus_mode() -> void:
		enter_called = true

	func exit_focus_mode() -> void:
		exit_called = true


func test_transition_origin_focus_rig_triggers_enter_and_exit_focus() -> void:
	var screen = auto_free(FocusableDummyScreen.new())
	screen.hud_screen_id = "test:focus"
	screen.hud_screen_title = "Focus Screen"
	add_child(screen)

	var overlay = _open_and_play([UP])
	assert_bool(screen.enter_called).is_true()
	assert_bool(screen.exit_called).is_false()

	overlay._cleanup_focus()
	assert_bool(screen.exit_called).is_true()


func test_suitos_snapshot_restore_intact() -> void:
	_screen("test:a", "Alpha")
	SuitOS.pin_to_slot(0, "test:a")
	var saved: Dictionary = SuitOS.get_snapshot()
	# FD-305 §4: la curaduria viaja con el checkpoint, de forma aditiva sobre lo que ya habia.
	assert_array(saved.keys()).contains_exactly_in_any_order(
		["pinned_slots", "last_snapshots", "favorite_screens", "favorites_initialized"])
	# JSON-safe: sobrevive ida y vuelta por JSON sin perder nada.
	assert_str(to_json(parse_json(to_json(saved)))).is_equal(to_json(saved))

	SuitOS.clear_slots()
	SuitOS.restore_snapshot(saved)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:a", "", "", ""])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_hud_widgets_hide_during_the_pause_menu_but_not_in_hud_mode() -> void:
	# Los widgets viven en el slot HUD (capa 115) y quedaban dibujados encima del menu de pausa.
	_screen("test:a", "Alpha", 0.9)
	SuitOS.pin_to_slot(0, "test:a")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget = host.get_widget_root().get_node_or_null("SuitOS_Widget_slot_1")
	assert_object(widget).is_not_null()
	assert_bool(widget.visible).is_true()

	# Pausa del menu: se esconden.
	get_tree().paused = true
	host.refresh_visibility()
	assert_bool(widget.visible).is_false()

	# Pausa del modo HUD: se ven (tocarlos cambia de pantalla).
	PauseManager._hud_mode_paused = true
	host.refresh_visibility()
	assert_bool(widget.visible).is_true()
	PauseManager._hud_mode_paused = false

	# Reanudar: vuelven.
	get_tree().paused = false
	host.refresh_visibility()
	assert_bool(widget.visible).is_true()



func test_dragging_the_hud_touch_button_aims_the_dial_and_lifting_picks() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	MobileUIManager._spawn_mobile_ui()
	var button = MobileUIManager._mobile_ui.get_node("Container/ActionButtons/HUDButton")

	# Dedo apoyado y arrastrado hacia arriba antes del umbral del hold: el dial se abre ya y
	# apunta a la segunda pantalla (las 12).
	button.drag_vector = Vector2(0.0, -80.0)
	var overlay = _open_and_play([{"hud_mode": true}, {"hud_mode": true}])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)

	# Soltar el dedo: TAB suelto, elige lo marcado y se queda.
	button.drag_vector = Vector2.ZERO
	_play(overlay, [UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func test_hud_touch_button_emits_the_same_event_as_tab() -> void:
	MobileUIManager._spawn_mobile_ui()
	var button = MobileUIManager._mobile_ui.get_node("Container/ActionButtons/HUDButton")
	assert_int(button.pause_mode).is_equal(Node.PAUSE_MODE_PROCESS)

	button._press()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_bool(Input.is_action_pressed("hud_mode")).is_true()

	button._release()
	assert_bool(Input.is_action_pressed("hud_mode")).is_false()


func test_promote_to_hold_turns_the_release_into_hold_release() -> void:
	var g = Gesture.new()
	assert_int(g.feed(true)).is_equal(Gesture.NONE)
	g.promote_to_hold()
	assert_int(g.feed(true)).is_equal(Gesture.NONE) # no dispara un segundo HOLD
	assert_int(g.feed(false)).is_equal(Gesture.HOLD_RELEASE)



func test_gamepad_and_tab_open_the_radial_without_the_virtual_mouse() -> void:
	# Cualquier boton o eje de gamepad prende el mouse virtual: el boton del HUD o el stick para
	# apuntar lo mostraban encima del dial, y con TAB no. Deben entrar igual.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	var cursor = overlay._virtual_mouse
	assert_bool(cursor.is_processing_input()).is_false() # el gamepad no lo activa
	assert_bool(cursor.is_processing()).is_false()        # el stick no lo mueve
	assert_bool(cursor.visible).is_false()

	# Elegida una pantalla sin Pantalla propia (widget ampliado): desde la revision 2026-09-19 usa
	# mouse (click y arrastre a slots), asi que el cursor queda prendido y liberado.
	_play(overlay, [{"hud_mode": true, "mouse_delta": [0.0, overlay_aim_radius()]}])
	_play(overlay, [UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_bool(cursor.is_processing_input()).is_true()
	assert_bool(cursor.visible).is_true()



func _widget_screen(id: String, title: String) -> Node:
	var screen = _screen(id, title)
	screen.hud_widget_scene = load("res://core_v2/ui/hud/FlashlightWidget.tscn")
	return screen


func test_widget_screen_uses_button_focus_and_trigger_jump_crouch_as_click() -> void:
	# Un hudable sin Pantalla (la linterna) deja el foco en su boton y el mando puede oprimirlo con
	# el gatillo derecho, jump o crouch (en el host el modo HUD pausa: no hacen otra cosa). Ademas
	# el mouse queda disponible (revision 2026-09-19) para clickear y arrastrar el panel.
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:a", [UP])
	var widget = overlay._mount.get_widget()
	assert_bool(is_instance_valid(widget)).is_true()
	var toggle = widget.get_node("Margin/VBox/StatusRow/ToggleButton")
	assert_bool(toggle.has_focus()).is_true()
	assert_bool(overlay._virtual_mouse.is_processing_input()).is_true()
	var presses := PressCounter.new()
	toggle.connect("pressed", presses, "on_pressed")

	_play(overlay, [{"tool_fire_primary": true}, UP, {"jump": true}, UP, {"crouch": true}, UP])
	assert_int(presses.count).is_equal(3)

	# Sostenido no repite: un flanco, un clic.
	presses.count = 0
	_play(overlay, [{"crouch": true}, {"crouch": true}, {"crouch": true}, UP])
	assert_int(presses.count).is_equal(1)


func test_ui_accept_does_not_double_press_the_widget_button() -> void:
	# A es crouch y ui_accept a la vez: la GUI no puede oprimirlo ademas del stream.
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:a", [UP])
	overlay._input(_action("ui_accept"))
	assert_bool(get_viewport().is_input_handled()).is_true()


func test_focus_cursor_scale_crosses_the_terminal_like_the_screen() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([])
	var terminal_like = auto_free(TerminalSizedScreen.new())
	var root: Vector2 = overlay.get_viewport_rect().size
	assert_vector2(overlay._focus_cursor_scale(terminal_like)).is_equal(Vector2(1280.0, 816.0) / root)
	assert_vector2(overlay._focus_cursor_scale(null)).is_equal(Vector2.ONE)


class TerminalSizedScreen extends Reference:
	func view_size() -> Vector2:
		return Vector2(1280.0, 816.0)


func test_the_surface_sign_comes_from_the_real_mesh_basis() -> void:
	# El signo de U ya no es un flip fijo: sale de proyectar el eje local X del mesh. Un mesh
	# que mira al frente deja su +X a la derecha; girado 180 (mirando a la camara) lo deja a la
	# izquierda y ahi si hay que invertir. Misma autoridad para mouse y stick.
	var overlay = auto_free(load("res://core_v2/ui/hud/HudModeOverlay.gd").new())
	var mesh = auto_free(CSGBox.new())
	mesh.width = 2.0
	mesh.height = 1.0
	var cam = auto_free(Camera.new())
	add_child(mesh)
	add_child(cam)
	cam.global_transform = Transform(Basis(), Vector3(0.0, 0.0, 3.0))
	cam.current = true
	mesh.global_transform = Transform(Basis(), Vector3.ZERO)
	assert_bool(overlay._surface_u_flip(mesh, cam)).is_false()
	mesh.global_transform = Transform(Basis(Vector3.UP, PI), Vector3.ZERO)
	assert_bool(overlay._surface_u_flip(mesh, cam)).is_true()
	# Sin mesh 3D (vista 2D del control remoto) se conserva el signo historico.
	assert_bool(overlay._surface_u_flip(null, cam)).is_true()


# Hereda de la constante y no de la ruta entre comillas: el runner del CI extrae nombres de clase
# sacando espacios y con la ruta imprimia "Can't extract class name".
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

class RecordingVirtualMouse extends VirtualMouseScript:
	var emitted := []
	func _emit_event(event: InputEvent) -> void:
		emitted.append(event)


func test_virtual_mouse_drives_a_holographic_screen_by_relative_motion() -> void:
	# El terminal tiene su cursor en pixeles de SU Viewport: el cursor virtual no camina por la
	# pantalla ni hace warp (con el mouse capturado, cada warp mandaba un salto de ida y vuelta).
	var cursor = auto_free(RecordingVirtualMouse.new())
	add_child(cursor)
	cursor._active = true
	cursor._invert_axes = false
	Input.action_press("cursor_right", 1.0)

	cursor._process(0.1)
	var normal: Vector2 = cursor.emitted.back().relative
	var position_after_normal: Vector2 = cursor._position

	cursor.emitted.clear()
	cursor._ignore_warp_motion = false # el warp de la pasada normal se limpia recien al frame siguiente
	cursor.relative_target_scale = Vector2(2.0, 3.0)
	cursor._process(0.1)
	Input.action_release("cursor_right")

	assert_int(cursor.emitted.size()).is_equal(1)
	assert_float(cursor.emitted[0].relative.x).is_equal_approx(normal.x * 2.0, 0.01)
	assert_vector2(cursor._position).is_equal(position_after_normal) # no camina por la pantalla
	assert_bool(cursor._ignore_warp_motion).is_false() # sin warp


class PressCounter extends Reference:
	var count := 0
	func on_pressed() -> void:
		count += 1



func test_hud_widgets_hide_while_a_screen_is_open_but_not_with_only_the_dial() -> void:
	# La pantalla abierta va encima de los widgets; con el holograma 3D ninguna capa 2D queda
	# debajo de el, asi que se ocultan. Con solo el dial abierto se ven (el dial ya va encima).
	_screen("test:a", "Alpha", 0.9)
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(0, "test:a")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget = host.get_widget_root().get_node_or_null("SuitOS_Widget_slot_1")
	assert_object(widget).is_not_null()

	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_bool(widget.visible).is_true()

	_play(overlay, [{"mouse_delta": [0.0, overlay_aim_radius()]}])
	_play(overlay, [CONFIRM])
	assert_str(SuitOS.get_active_screen_id()).is_not_empty()
	assert_bool(widget.visible).is_false()


# --- Teclas de slot (1-4) y zona muerta del dial ---

# Abre con la tecla del slot (1..4) y reproduce frames con esa tecla en el stream.
func _open_slot_and_play(slot_number: int, frames: Array) -> Node:
	# Revision 2026-09-19: las teclas 1-4 ya no abren el modo HUD por evento; entran por el stream
	# determinista como los hombros. Para probar el resto del modo HUD se abre directo por slot.
	SuitOS.open_hud_mode(false, "", slot_number - 1)
	var overlay = _overlay()
	_play(overlay, frames)
	return overlay


func _slot_held(slot_number: int, ticks: int) -> Array:
	var frames: Array = []
	for _i in range(ticks):
		frames.append({"hud_slot": slot_number})
	return frames


func test_slot_key_tap_opens_that_slot_and_closes_it_if_already_open() -> void:
	# Decision de Sebastian 2026-09-20 (Manual, Apendice A punto 2): el boton de un slot ABRE
	# la pantalla de ese slot; si ya estamos en ella, la cierra. Un boton, un destino.
	# Antes los cuatro botones hacian lo mismo: cerrar el modo HUD, sin mirar cual se apreto.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(0, "test:a")
	SuitOS.pin_to_slot(2, "test:b")
	var overlay = _open_slot_and_play(3, [UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	# Otro slot: cambia a SU pantalla, sin salir del modo HUD.
	_play(overlay, [{"hud_slot": 1}, UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	# El mismo slot otra vez: cierra.
	_play(overlay, [{"hud_slot": 1}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_slot_key_hold_pins_the_pick_in_that_slot() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(0, "test:a")
	var overlay = _open_slot_and_play(4, _slot_held(4, Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	_play(overlay, [{"hud_slot": 4, "mouse_delta": [0.0, overlay_aim_radius()]}])
	_play(overlay, [UP])
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:a", "", "", "test:b"])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")


# Revision 2026-09-19: el hold abre el radial fijado al slot y marca su widget. El tap es el que
# ejecuta la accion; el hold no abre la pantalla directo.
func test_hold_a_shoulder_opens_the_radial_with_that_widget_selected() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(1, "test:b")
	var overlay = _open_and_play_slot(_slot_held(2, Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	assert_int(overlay._target_slot).is_equal(1)
	assert_str(overlay._dial_id_at(overlay._selector.get_hovered_index())).is_equal("test:b")
	assert_str(SuitOS.get_active_screen_id()).is_empty()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "test:b", "", ""])


# FD-304 §3: un tap NO abre un menu. El slot vacio responde con un deny y no pasa nada mas; el
# radial fijado a ese slot es el hold, que es la accion deliberada.
func test_slot_key_tap_on_an_empty_slot_offers_the_dial_for_it() -> void:
	# Un slot vacio no tiene nada que abrir, asi que el tap ofrece el dial fijado a ese slot,
	# que es como se llena. Ofrecerlo es mas util que no hacer nada, y todavia no fija nada:
	# nada se autoasigna (Manual §3.3).
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_slot_and_play(3, [UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_bool(overlay._selector.is_open()).is_true()
	assert_int(overlay._target_slot).is_equal(2)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])


# El hold del mismo slot vacio si abre el radial fijado a el, y lo elegido queda fijado ahi.
func test_slot_key_hold_on_an_empty_slot_opens_the_radial_for_it() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_slot_and_play(3, _slot_held(3, Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	assert_int(overlay._target_slot).is_equal(2)
	_play(overlay, [{"hud_slot": 3, "mouse_delta": [0.0, overlay_aim_radius()]}])
	_play(overlay, [UP])
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:b", ""])


func test_tab_pick_with_no_empty_slot_opens_without_pinning() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	for i in range(4):
		SuitOS.pin_to_slot(i, "other:%d" % i)
	_open_and_pick_second()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_array(SuitOS.get_pinned_slots()).is_equal(["other:0", "other:1", "other:2", "other:3"])


func test_tab_pick_of_a_pinned_screen_does_not_move_it() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(3, "test:b")
	_open_and_pick_second()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", "test:b"])


func test_aiming_into_the_dead_zone_selects_nothing() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	_play(overlay, [{"mouse_delta": [0.0, 20.0]}])
	# 20 px cae en el hub: no hay nada marcado, y nada se fija solo.
	assert_bool(overlay._selector.has_selection()).is_false()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])


func test_pulling_the_mouse_back_to_the_middle_clears_the_selection() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	# Con el radio completo, no con 60 px: en la ventana de CI el hub llega a 65 px y el aim
	# nunca salia del centro, asi que la primera afirmacion (hay algo marcado) no se cumplia.
	var overlay = _open_and_play([UP])
	_play(overlay, [{"hud_mode": true, "mouse_delta": [0.0, overlay_aim_radius()]}])
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)
	# Volver al centro: el mouse suma, asi que el delta opuesto deja el aim en cero.
	_play(overlay, [{"hud_mode": true, "mouse_delta": [0.0, -overlay_aim_radius()]}])
	assert_bool(overlay._selector.has_selection()).is_false()


func test_slot_key_opens_a_widget_only_screen_on_press() -> void:
	# Sin vista diegetica no hay transicion que disimule la espera del tap: abre al oprimir.
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(0, "test:a")
	var overlay = _open_slot_and_play(1, [])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	assert_object(overlay._mount.get_widget()).is_not_null()
	# Soltar esa misma pulsacion no la cierra...
	_play(overlay, [UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	# ...y un segundo tap si.
	_play(overlay, [{"hud_slot": 1}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_slot_key_hold_released_in_the_dead_zone_leaves_nothing_open() -> void:
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(0, "test:a")
	# Slot 3 vacio: el hold abre el radial; soltar sin marcar nada cierra sin abrir pantalla.
	var overlay = _open_slot_and_play(3, _slot_held(3, Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	_play(overlay, [UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:a", "", "", ""])


func test_empty_slot_placeholders_do_not_respond_to_touch() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var placeholder: Control = host.get_widget_root().get_node("SuitOS_Placeholder_slot_4")
	assert_bool(placeholder.visible).is_true() # en el modo HUD se ven
	assert_int(placeholder.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# Fuera del grupo: la camara tactil toma ese toque como cualquier otro.
	assert_bool(placeholder.is_in_group("touch_control")).is_false()
	assert_bool(placeholder.is_connected("gui_input", host, "_on_widget_gui_input")).is_false()


func test_touch_emulated_click_does_not_close_the_radial() -> void:
	# Con el arbol pausado MobileUIManager no marca el puntero como tactil: el clic que Godot emula
	# al apoyar el dedo (device -1) cerraba el dial antes de poder elegir.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	click.device = -1
	overlay._input(click)
	assert_bool(overlay._selector.is_open()).is_true()


func test_mouse_press_waits_for_release_before_confirming_the_radial() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	overlay._point_at(Vector2(0.0, -overlay.AIM_RADIUS))
	overlay._confirm_was_down = false
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	click.position = overlay._selector.get_global_rect().position + overlay._selector.rect_size * 0.5
	overlay._input(click)
	var stream := InputDataV2.new()
	stream.tool_fire_primary = true
	overlay._drive_from_stream(stream)
	assert_bool(overlay._selector.is_open()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_empty()


func test_right_mouse_releases_capture_to_the_desktop_controlled_hud_cursor() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	var right := InputEventMouseButton.new()
	right.button_index = BUTTON_RIGHT
	right.pressed = true
	right.position = Vector2(120.0, 80.0)
	overlay._input(right)
	assert_bool(overlay._virtual_mouse.is_desktop_mouse_mode()).is_true()
	overlay._input(right)
	assert_bool(overlay._virtual_mouse.is_desktop_mouse_mode()).is_true()
	overlay._exit()
	assert_bool(overlay._virtual_mouse.is_desktop_mouse_mode()).is_false()


func test_dragging_a_radial_item_onto_a_slot_pins_it_there() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var sel = overlay._selector
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	var mid: float = (sqrt(sel.width_min) + sqrt(sel.width_max)) / 4.0 * sel._ring_size()
	var top: Vector2 = center + Vector2(0.0, -mid) # la segunda opcion, Beta
	overlay._input(_touch(true, top))
	overlay._touch_press_msec = OS.get_ticks_msec() - 500 # pasado el hold
	var slot_3: Rect2 = host.slot_rect(2)
	var drag := InputEventScreenDrag.new()
	drag.position = slot_3.position + slot_3.size * 0.5
	overlay._input(drag)
	assert_object(overlay._drag_ghost).is_not_null()
	assert_str(overlay._drag_ghost.text).is_equal("Beta")
	assert_bool(host.get_widget_root().get_node("SuitOS_Placeholder_slot_3").visible).is_true()
	overlay._input(_touch(false, drag.position))
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:b", ""])
	# El dial sigue abierto para seguir asignando, y los destinos se apagan.
	assert_bool(sel.is_open()).is_true()
	assert_bool(host._drop_targets_visible).is_false()


func test_tapping_the_button_of_an_enlarged_widget_presses_it_instead_of_closing() -> void:
	# El rect de la vista sumaba dos veces el corrimiento del pivote: el boton, del lado derecho
	# del widget ampliado, caia "fuera" y el toque cerraba el modo HUD sin oprimirlo.
	_widget_screen("test:a", "Linterna")
	SuitOS.pin_to_slot(0, "test:a")
	var overlay = _open_and_play([UP])
	var widget = overlay._mount.get_widget()
	var toggle: Control = widget.get_node("Margin/VBox/StatusRow/ToggleButton")
	var xf: Transform2D = toggle.get_global_transform_with_canvas()
	var on_button: Vector2 = xf.origin + toggle.rect_size * xf.get_scale() * 0.5
	assert_bool(overlay._is_outside_view(on_button)).is_false()
	var drawn := Rect2(widget.get_global_transform_with_canvas().origin,
		widget.rect_size * widget.get_global_transform_with_canvas().get_scale())
	assert_bool(overlay._view_screen_rect().is_equal_approx(drawn)).is_true()
	overlay._input(_touch(true, on_button))
	overlay._input(_touch(false, on_button))
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func _drag_enlarged_widget(overlay: Node, to: Vector2) -> void:
	var widget: Control = overlay._mount.get_widget()
	var xf: Transform2D = widget.get_global_transform_with_canvas()
	var on_body: Vector2 = xf.origin + Vector2(6, 6) * xf.get_scale() # el borde, lejos del boton
	overlay._input(_touch(true, on_body))
	overlay._touch_press_msec = OS.get_ticks_msec() - 500 # pasado el hold
	var drag := InputEventScreenDrag.new()
	drag.position = to
	overlay._input(drag)
	assert_bool(overlay._dragging_view).is_true()
	overlay._input(_touch(false, to))


func test_a_widget_only_screen_is_dragged_from_its_view_to_a_slot_and_stays() -> void:
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(false, "test:a")).is_true()
	var overlay = _overlay()
	var host = SuitOS.get_node("SuitOSWidgetHost")
	# Soltado fuera de todo slot: vuelve a la vista ampliada, nada se fija.
	_drag_enlarged_widget(overlay, overlay.get_viewport_rect().size * 0.5)
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_object(overlay._mount.get_widget()).is_not_null()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])
	# Sobre el slot 3: queda fijado ahi y el modo HUD se cierra.
	var slot_3: Rect2 = host.slot_rect(2)
	_drag_enlarged_widget(overlay, slot_3.position + slot_3.size * 0.5)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:a", ""])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_bool(host._drop_targets_visible).is_false()


func test_a_shoulder_and_the_stick_drag_the_open_widget_screen_to_a_slot() -> void:
	# FD-304 §6 (modo pantalla): hombro sostenido + stick ancla la pantalla abierta a otro slot.
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(false, "test:a")).is_true()
	var overlay = _overlay()
	var host = SuitOS.get_node("SuitOSWidgetHost")
	# El hombro del slot 1, sostenido hasta el hold, levanta la vista abierta.
	_play(overlay, _slot_held(1, Gesture.HOLD_TICKS))
	assert_bool(overlay._dragging_view).is_true()
	assert_bool(overlay._view_drag_from_gamepad).is_true()
	# El stick la lleva hasta el slot 3 (indice 2).
	var target: Vector2 = host.slot_rect(2).get_center()
	for _i in range(200):
		var step: Vector2 = target - overlay._cursor
		if step.length() < 8.0:
			break
		step = step.normalized()
		_play(overlay, [{"hud_slot": 1, "move_vec": [step.x, step.y], "analog_move_active": true}])
	assert_int(host.slot_at(overlay._cursor)).is_equal(2)
	# Soltar el hombro la fija ahi y cierra el modo HUD.
	_play(overlay, [{}])
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:a", ""])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


# --- Oprimir sin nada marcado / fuera del radial (restaurados) ---

func test_click_with_nothing_marked_closes_the_radial_without_acting() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	# Directo al dial (hold sobre un widget), sin pantalla detras.
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	_play(overlay, [UP, {"tool_fire_primary": true}])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])


func test_click_outside_the_radial_over_a_screen_exits_hud() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	# El dial se abre con un tap desde el juego (sostener va al cajon).
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	# Clic sin nada marcado: el hub, que cierra sin elegir.
	_play(overlay, [CONFIRM])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_releasing_the_hud_touch_button_on_the_hub_opens_the_drawer() -> void:
	# En touch no hay boton A: el hold del boton del HUD que termina en el "..." confirma el hub.
	# El stick de vuelta al centro (gamepad) sigue descartando (test_letting_go_on_the_hub...).
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	MobileUIManager._spawn_mobile_ui()
	var button = MobileUIManager._mobile_ui.get_node("Container/ActionButtons/HUDButton")
	MobileUIManager.note_hud_touch() # lo que hace el boton tactil al apoyar el dedo
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS))
	# Sin pasar por el hub: sostener el boton tactil abre el cajon directo, igual que Y.
	assert_bool(overlay._drawer_open()).is_true()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	button.drag_vector = Vector2.ZERO # no dejar el dedo pegado para el proximo test


func test_touch_tap_started_on_the_hub_opens_the_drawer_even_with_finger_drift() -> void:
	# El dedo casi nunca queda quieto: si empezo y solto dentro del "..." no puede quedar en nada
	# por haberse corrido unos pixeles mas que el umbral del tap.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var sel = overlay._selector
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	overlay._input(_touch(true, center))
	overlay._input(_touch(false, center + Vector2(0.0, 30.0)))
	assert_bool(overlay._drawer_open()).is_true()


func test_touch_tap_on_a_slice_picks_it_and_outside_closes() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var sel = overlay._selector
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	var mid: float = (sqrt(sel.width_min) + sqrt(sel.width_max)) / 4.0 * sel._ring_size()
	# FD-306 §1: el centro ya no es un hueco sino el hub, y tocarlo abre el drawer (sin salir).
	overlay._input(_touch(true, center))
	overlay._input(_touch(false, center))
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_bool(overlay._drawer_open()).is_true()
	assert_bool(sel.is_open()).is_false()

	SuitOS.close_hud_mode()
	yield(_await_overlay_freed(), "completed")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	overlay = _overlay()
	sel = overlay._selector
	center = sel.get_global_rect().position + sel.rect_size * 0.5
	# La segunda opcion esta a las 12: tocar su sector la elige.
	var top: Vector2 = center + Vector2(0.0, -mid)
	overlay._input(_touch(true, top))
	overlay._input(_touch(false, top))
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")


func test_touch_tap_with_a_marked_option_presses_it_like_the_elevator() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var sel = overlay._selector
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	var mid: float = (sqrt(sel.width_min) + sqrt(sel.width_max)) / 4.0 * sel._ring_size()
	# Marcada la de abajo (Alpha, a las 6): un tap fuera de los sectores la oprime. Fuera del hub
	# (FD-306 §1): el centro tiene dueño y tocarlo abre el drawer, no oprime lo marcado.
	var hollow: Vector2 = center + Vector2(90.0, 0.0)
	overlay._point_at(Vector2(0.0, 100.0))
	assert_int(sel.get_hovered_index()).is_equal(0)
	overlay._input(_touch(true, hollow))
	overlay._input(_touch(false, hollow))
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	assert_bool(sel.is_open()).is_false()

	# Con una marcada, tocar OTRO sector elige ese sector, no la marcada.
	overlay._open_radial()
	overlay._point_at(Vector2(0.0, 100.0))
	var top: Vector2 = center + Vector2(0.0, -mid)
	overlay._input(_touch(true, top))
	overlay._input(_touch(false, top))
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")


# --- Asa de la pantalla abierta ---

func test_a_widget_only_screen_has_no_drag_handle_and_drags_from_its_panel() -> void:
	# El asa es solo para las Pantallas con vista propia. El widget ampliado se arrastra desde su
	# panel entero, asi que no la lleva.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:b", [UP])
	var host = SuitOS.get_node("SuitOSWidgetHost")
	assert_bool(overlay._view_handle.visible).is_false()
	# Arrastrarlo desde el cuerpo de su panel hasta el slot 2 lo ancla ahi y cierra el modo HUD.
	_drag_enlarged_widget(overlay, host.slot_rect(1).get_center())
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "test:b", "", ""])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_an_enlarged_widget_panel_drags_to_a_slot_with_the_mouse() -> void:
	# Revision 2026-09-19: el panel del widget ampliado se arrastra con el mouse desde su cuerpo
	# (como un item del radial), sin hold: el mouse levanta al instante.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:b", [UP])
	var host = SuitOS.get_node("SuitOSWidgetHost")
	# Modo pantalla: el puntero se libera (HIDDEN, no capturado).
	assert_bool(overlay._virtual_mouse.is_desktop_mouse_mode()).is_true()
	var rect: Rect2 = overlay._view_screen_rect()
	var on_body := Vector2(rect.position.x + 6.0, rect.position.y + 6.0)

	var down := InputEventMouseButton.new()
	down.button_index = BUTTON_LEFT
	down.pressed = true
	down.position = on_body
	overlay._input(down)
	assert_bool(overlay._dragging_view).is_true()

	var target: Vector2 = host.slot_rect(1).get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = target
	overlay._input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = BUTTON_LEFT
	up.pressed = false
	up.position = target
	overlay._input(up)

	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "test:b", "", ""])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_widgets_ignore_taps_in_hud_mode_and_the_tap_that_closed_it() -> void:
	# En el telefono el clic emulado del toque cierra el modo HUD (fuera de la pantalla) y el
	# ScreenTouch del mismo toque caia sobre el widget que reaparecia: lo volvia a abrir.
	_widget_screen("test:a", "Linterna")
	SuitOS.pin_to_slot(0, "test:a")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget: Control = host.get_widget_root().get_node("SuitOS_Widget_slot_1")
	# El cuerpo del widget, lejos de su boton: el host decide "es del boton" por la ultima posicion
	# del puntero, y sin fijarla heredaba la de otro test (en CI caia sobre ENCENDER).
	var xf: Transform2D = widget.get_global_transform_with_canvas()
	var body: Vector2 = xf.origin + Vector2(4, 4) * xf.get_scale()
	var overlay = _open_screen_and_play("test:a", [UP])
	# Tocar fuera cierra; el resto de ese toque sobre el widget no lo reabre.
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	click.position = Vector2.ZERO
	overlay._input(click)
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	host._input(_touch(true, body))
	host._on_widget_gui_input(_touch(true, body), widget, "slot_1")
	assert_object(host._pressed_control).is_null() # descartado: mismo cuadro en que se cerro
	host._on_widget_gui_input(_touch(false, body), widget, "slot_1")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	# Un toque nuevo, un cuadro despues, si cuenta. Sin esperar cuadros ni reabrir el modo HUD: en CI,
	# con toda la suite en un proceso, esperar dejaba que otro estado global impidiera reabrirlo.
	host._hud_state_frame = Engine.get_idle_frames() - 1
	host._on_widget_gui_input(_touch(true, body), widget, "slot_1")
	assert_object(host._pressed_control).is_same(widget)
	host._pressed_control = null


# --- Widgets con el dial a la vista ---

func _dial_with_widget(id: String, slot_index: int) -> Array:
	var host = SuitOS.get_node("SuitOSWidgetHost")
	SuitOS.pin_to_slot(slot_index, id)
	var widget: Control = host.get_widget_root().get_node("SuitOS_Widget_slot_%d" % (slot_index + 1))
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	host._hud_state_frame = -1 # el toque llega cuadros despues de abrir (con el arbol pausado no se espera)
	assert_bool(widget.is_visible_in_tree()).is_true() # con solo el dial se ven
	return [_overlay(), host, widget]


func test_with_the_dial_open_tapping_a_widget_opens_its_screen() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var parts: Array = _dial_with_widget("test:a", 0)
	var overlay = parts[0]
	var widget: Control = parts[2]
	var xf: Transform2D = widget.get_global_transform_with_canvas()
	var on_widget: Vector2 = xf.origin + Vector2(4, 4) * xf.get_scale()
	# Solo por el overlay: con el dial encima la GUI no le entrega el toque al widget.
	overlay._input(_touch(true, on_widget))
	overlay._input(_touch(false, on_widget))
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")


func test_with_the_dial_open_a_widget_button_is_pressable() -> void:
	_widget_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	var parts: Array = _dial_with_widget("test:a", 0)
	var overlay = parts[0]
	var widget: Control = parts[2]
	var toggle: Button = widget.get_node("Margin/VBox/StatusRow/ToggleButton")
	var presses := PressCounter.new()
	toggle.connect("pressed", presses, "on_pressed")
	var xf: Transform2D = toggle.get_global_transform_with_canvas()
	var on_button: Vector2 = xf.origin + toggle.rect_size * xf.get_scale() * 0.5
	overlay._input(_touch(true, on_button))
	overlay._input(_touch(false, on_button))
	assert_int(presses.count).is_equal(1)
	assert_str(SuitOS.get_active_screen_id()).is_empty() # el boton no abre la pantalla
	assert_bool(overlay._selector.is_open()).is_true()


func test_with_the_dial_open_a_widget_can_be_dragged_to_another_slot() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var parts: Array = _dial_with_widget("test:a", 0)
	var overlay = parts[0]
	var host = parts[1]
	var widget: Control = parts[2]
	var from: Vector2 = widget.get_global_transform_with_canvas().origin + Vector2(4, 4)
	overlay._input(_touch(true, from))
	host._press_msec = OS.get_ticks_msec() - 500
	var slot_4: Rect2 = host.slot_rect(3)
	var drag := InputEventScreenDrag.new()
	drag.position = slot_4.position + slot_4.size * 0.5
	overlay._input(drag)
	host._input(drag)
	assert_bool(host._dragging).is_true()
	assert_bool(overlay._selector.has_selection()).is_false() # el dedo no apunto el dial
	host._input(_touch(false, drag.position))
	overlay._input(_touch(false, drag.position))
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", "test:a"])
	assert_bool(overlay._selector.is_open()).is_true() # el dial sigue a la vista


class ToggleScreen extends HUDableComponent:
	var on := false
	func widget_snapshot() -> Dictionary:
		return {"proto": 1, "id": hud_screen_id, "title": hud_screen_title, "on": on, "source": "online"}


func test_the_enlarged_widget_updates_when_its_screen_changes() -> void:
	# Oprimir ENCENDER en el widget ampliado prendia la linterna pero el rotulo seguia en APAGADA.
	var screen = auto_free(ToggleScreen.new())
	screen.hud_screen_id = "test:toggle"
	screen.hud_screen_title = "Linterna"
	screen.hud_widget_scene = load("res://core_v2/ui/hud/FlashlightWidget.tscn")
	add_child(screen)
	var overlay = _open_screen_and_play("test:toggle", [UP])
	var widget = overlay._mount.get_widget()
	var status: Label = widget.get_node("Margin/VBox/StatusRow/StatusLabel")
	var before: String = status.text
	screen.on = true
	screen.notify_state_changed()
	assert_str(status.text).is_not_equal(before)


# --- Mando (FD-304) ---

# Una pantalla que declara que hace cada boton de cara. Es el contrato nuevo de §4: opcional, y
# cuando existe manda sobre la navegacion por foco de la GUI.
class GamepadScreen:
	extends HUDableComponent

	var toggled: int = 0

	func _init() -> void:
		allowed_actions_list = ["toggle"]
		hud_widget_scene = load("res://core_v2/ui/hud/FlashlightWidget.tscn")

	func hud_gamepad_actions() -> Array:
		return [{"button": "a", "op": "toggle", "label": "Encender/Apagar", "confirm": true}]

	func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
		if op == "toggle":
			toggled += 1
			notify_state_changed()
			return {"ok": true, "on": toggled % 2 == 1}
		return {"ok": false, "error": "no"}


func _gamepad_screen(id: String, title: String) -> Node:
	var screen = auto_free(GamepadScreen.new())
	screen.hud_screen_id = id
	screen.hud_screen_title = title
	add_child(screen)
	return screen


func test_the_shoulders_feed_the_slot_actions_of_the_hud_layer() -> void:
	# FD-304 §1.1: 1 y 2 a la izquierda (L1/L2), 3 y 4 a la derecha (R1/R2), para que el hombro
	# del lado sea el slot del lado. Con deadzone 0.5, como hud_mode.
	var expected := {"slot_1": JOY_L, "slot_2": JOY_L2, "slot_3": JOY_R, "slot_4": JOY_R2}
	for action in expected.keys():
		var found := false
		for event in InputMap.get_action_list(action):
			if event is InputEventJoypadButton and event.button_index == expected[action]:
				found = true
		assert_bool(found) \
			.override_failure_message("%s sin su boton de hombro" % action).is_true()
		assert_float(InputMap.action_get_deadzone(action)).is_equal_approx(0.5, 0.001)


func test_a_shoulder_event_does_not_open_the_hud_mode() -> void:
	# Revision 2026-09-19: los hombros son slots en gameplay y los resuelve el stream determinista
	# (HudSlotGamepadV2.tick en _physics_process), no el _input del autoload. Un evento crudo no
	# abre nada aca.
	_screen("test:a", "Alpha")
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_R
	event.pressed = true
	SuitOS._input(event)
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_bool(SuitOS.open_hud_mode(false, "", 2)).is_true() # el radial si lo abre, por su ruta
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	SuitOS.close_hud_mode()


func test_the_slot_frame_fills_while_the_shoulder_is_held_and_empties_if_let_go() -> void:
	# FD-304 §3.1: el hold no puede ser invisible.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_slot_and_play(3, _slot_held(3, 6))
	var early: float = overlay._hold_progress
	assert_float(early).is_greater(0.0)
	assert_float(early).is_less(1.0)
	_play(overlay, _slot_held(3, 6))
	assert_float(overlay._hold_progress).is_greater(early) # proporcional al tiempo
	# Soltado antes del umbral: es un tap. Con el slot vacio, ofrece el dial fijado a el.
	_play(overlay, [UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_bool(overlay._selector.is_open()).is_true()


func test_a_declares_its_screen_action_and_the_gui_does_not_press_it_twice() -> void:
	# FD-304 §4: con la pantalla abierta, A ejecuta la operacion que ella declara, por la misma
	# ruta que su boton tactil (asi funciona igual en local y en el control remoto).
	var screen = _gamepad_screen("test:a", "Linterna")
	_screen("test:b", "Beta")
	var overlay = _open_screen_and_play("test:a", [UP])
	assert_bool(overlay._mount.is_showing()).is_true()
	_play(overlay, [{"crouch": true}, UP])
	assert_int(screen.toggled).is_equal(1)
	# Sostenido no repite, y el boton enfocado del widget NO se oprime ademas: un flanco, una vez.
	_play(overlay, [{"crouch": true}, {"crouch": true}, UP])
	assert_int(screen.toggled).is_equal(2)


func test_tap_a_shoulder_in_hud_opens_the_screen_of_that_slot() -> void:
	# El mismo verbo por hombro que por tecla (Manual §5, verbo 2).
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(2, "test:a")
	_open_and_play_slot([{"hud_slot": 3}, {}]) # tap del slot 3
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func test_hold_on_a_slot_that_is_not_a_favorite_opens_the_drawer_on_that_row() -> void:
	# El hold de un hombro abre el radial con el widget del slot si es favorito. Si NO lo es, abre
	# el drawer con esa opcion marcada.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(1, "test:b")
	if SuitOS.is_favorite("test:b"):
		SuitOS.toggle_favorite("test:b")
	assert_bool(SuitOS.is_favorite("test:b")).is_false()
	var overlay = _open_and_play_slot(_slot_held(2, Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_false()
	assert_bool(overlay._drawer_open()).is_true()
	assert_str(overlay._drawer.focused_screen_id()).is_equal("test:b")


func test_confirm_after_a_slot_hold_selects_that_slot_screen() -> void:
	# El hold de un hombro abre el radial con su widget marcado; confirmar (A/clic) activa ESE
	# item, no el centro.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(1, "test:b")
	var overlay = _open_and_play_slot(_slot_held(2, Gesture.HOLD_TICKS))
	assert_int(overlay._selector.get_hovered_index()).is_equal(overlay._dial_ids.find("test:b"))
	_play(overlay, [{"crouch": true}, {}])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")


func test_mouse_click_without_moving_on_a_slot_hold_radial_selects_the_slot_item() -> void:
	# Un clic sin haber movido el mouse activa lo marcado (el widget del slot que abrio el radial),
	# no el centro por posicion.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_to_slot(1, "test:b")
	var overlay = _open_and_play_slot(_slot_held(2, Gesture.HOLD_TICKS))
	var center: Vector2 = overlay._selector.get_global_rect().position + overlay._selector.rect_size * 0.5
	overlay._input(_mouse_click(true, center))
	overlay._input(_mouse_click(false, center))
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")


func test_crouch_click_on_the_dial_selects_the_aimed_item_like_the_mouse() -> void:
	# Revision 2026-09-19: A (crouch / right action) en el dial selecciona el item apuntado, igual
	# que un clic del mouse. Antes el evento ui_accept ademas confirmaba por su cuenta.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	overlay._point_at(Vector2(0.0, -overlay.AIM_RADIUS))
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)
	_play(overlay, [{"crouch": true}, {}]) # tap de A
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")


func test_x_and_b_cancel_the_dial() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	_play(overlay, [{"hud_mode": true, "interact": true}])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_the_dpad_steps_through_the_arc() -> void:
	# FD-304 §7.2: ademas del stick, la cruceta recorre las opciones en pasos.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	_screen("test:c", "Charlie")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._selector.is_open()).is_true()
	# Al entrar, el item del centro (hub) queda marcado.
	assert_int(overlay._selector.get_hovered_index()).is_equal(RadialSelectorV2.HUB_INDEX)
	# Desde el hub, el primer paso entra por el primer sector (a las 6), vaya donde vaya.
	_play(overlay, [{"hud_mode": true, "hud_nav": -1}])
	assert_int(overlay._selector.get_hovered_index()).is_equal(0)
	# Sostenida no repite hasta pasar el umbral: un paso por pulsacion.
	_play(overlay, [{"hud_mode": true, "hud_nav": -1}, {"hud_mode": true, "hud_nav": -1}])
	assert_int(overlay._selector.get_hovered_index()).is_equal(0)
	# Soltar y volver a pulsar si sube por el arco, y hacia abajo vuelve.
	_play(overlay, [{"hud_mode": true}, {"hud_mode": true, "hud_nav": -1}])
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)
	_play(overlay, [{"hud_mode": true}, {"hud_mode": true, "hud_nav": 1}])
	assert_int(overlay._selector.get_hovered_index()).is_equal(0)
	# Y no se pasa de los extremos del arco.
	for _i in range(6):
		_play(overlay, [{"hud_mode": true}, {"hud_mode": true, "hud_nav": -1}])
	assert_int(overlay._selector.get_hovered_index()).is_equal(2)


func test_with_the_hub_every_release_has_a_meaning() -> void:
	# FD-304 §7.1 pedia una memoria corta para cuando soltar dejaba "nada elegido". Con el hub de
	# FD-306 §1 ese estado no existe: apuntar en cualquier direccion cae en un sector, y el centro
	# es el hub. Se prueba justamente eso, que no hay agujero donde soltar no signifique nada.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	_screen("test:c", "Charlie")
	var overlay = _open_and_play([UP])
	var sel = overlay._selector
	for hour in range(12):
		var angle: float = (float(hour) / 12.0) * TAU - PI / 2.0
		overlay._point_at(Vector2(cos(angle), sin(angle)) * overlay.AIM_RADIUS)
		assert_int(sel.get_hovered_index()) \
			.override_failure_message("agujero a las %d en punto" % hour) \
			.is_not_equal(RadialSelectorV2.NONE)
	# Y soltar el boton CON el stick todavia apuntando abre esa pantalla, sin ambiguedad. El
	# stick no vuelve al centro porque se suelte el hombro: eso es soltar el stick, y entonces
	# queda marcado el hub, que cierra (test_letting_go_on_the_hub_...).
	_play(overlay, [{"move_vec": [0.0, -1.0], "analog_move_active": true}])
	assert_bool(sel.has_selection()).is_true()
	# Confirmar con el stick todavia apuntando abre esa pantalla, sin ambiguedad.
	_play(overlay, [{"move_vec": [0.0, -1.0], "analog_move_active": true, "tool_fire_primary": true}])
	assert_str(SuitOS.get_active_screen_id()).is_not_empty()


func test_letting_go_on_the_hub_closes_without_opening_the_drawer() -> void:
	# FD-306 §1.1: el movimiento reflejo de volver el stick al centro y soltar no puede tener
	# consecuencias. Ahi vive el hub, pero soltar no lo elige.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	_play(overlay, [{"hud_mode": true, "move_vec": [0.0, -1.0], "analog_move_active": true}])
	assert_bool(overlay._selector.has_selection()).is_true()
	# Stick de vuelta al centro: queda marcado el hub, que no cuenta como seleccion.
	_play(overlay, [{"hud_mode": true, "move_vec": [0.0, 0.0], "analog_move_active": true}])
	assert_bool(overlay._selector.hub_hovered()).is_true()
	assert_bool(overlay._selector.has_selection()).is_false()
	_play(overlay, [UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_a_on_the_hub_opens_the_drawer_which_never_lists_itself() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	# Apuntar y volver al centro: el stick en el medio marca el hub.
	_play(overlay, [
		{"hud_mode": true, "move_vec": [0.0, -1.0], "analog_move_active": true},
		{"hud_mode": true, "move_vec": [0.0, 0.0], "analog_move_active": true}])
	assert_bool(overlay._selector.hub_hovered()).is_true()
	_play(overlay, [{"hud_mode": true, "crouch": true}])
	assert_bool(overlay._drawer_open()).is_true()
	assert_bool(overlay._selector.is_open()).is_false()
	# El "..." es chrome del overlay, no un HUDable registrado: no puede listarse a si mismo.
	for row in overlay._drawer._rows:
		assert_str(String(row["id"])).is_not_equal("...")
	assert_int(overlay._drawer.row_count()).is_equal(2)


func test_mouse_click_on_the_hub_opens_the_drawer() -> void:
	# FD-306 §1.1 / Open Question 1: el hub se confirma con A o con un click, no solo con touch.
	# Nada apuntado todavia: el click cae sobre el "..." dibujado en el centro y debe abrir el
	# drawer, no descartar el dial (que era lo que hacia _confirm_or_dismiss con el hub marcado).
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var sel = overlay._selector
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	overlay._input(_mouse_click(true, center))
	overlay._input(_mouse_click(false, center))
	assert_bool(overlay._drawer_open()).is_true()
	assert_bool(sel.is_open()).is_false()


func test_mouse_click_with_the_aim_on_a_sector_picks_it_not_the_hub() -> void:
	# El mouse capturado warpea el click al centro, que es el hub. La opcion que vale es la que
	# el aim ya marco, no el puntero: un click con la Linterna apuntada la abre, no el drawer.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var sel = overlay._selector
	overlay._point_at(Vector2(0.0, 100.0)) # Alpha, a las 6
	assert_int(sel.get_hovered_index()).is_equal(0)
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	var previous_mode: int = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # con el grab, el click llega warpeado al centro
	# Sin ventana (el headless de CI) el grab no prospera y el click se resuelve por posicion,
	# que en el centro es el hub: ahi esta premisa no se cumple y no hay nada que afirmar. Mismo
	# resguardo que test_captured_mouse_dragging_a_radial_item_pins_it_to_a_slot.
	var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	overlay._input(_mouse_click(true, center))
	overlay._input(_mouse_click(false, center))
	Input.set_mouse_mode(previous_mode)
	if captured:
		assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
		assert_bool(sel.is_open()).is_false()


# Abre el drawer directo (sin pasar por el hub) y le da un tamaño de pantalla a mano: la escena de
# test no corre layout, y sin rect las filas no tienen geometria con la que hacer hit-test.
func _drawer_overlay() -> Node:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	overlay._open_drawer()
	overlay._drawer.rect_size = overlay.get_viewport_rect().size
	return overlay


func test_drawer_mouse_has_no_pointer_and_scrolls_relatively() -> void:
	# Sin puntero: el mouse mueve la lista en relativo, como el arma del radial. No hay fila
	# bajo el cursor que re-resolver, asi que no puede correr a un extremo.
	var overlay = _drawer_overlay()
	var drawer = overlay._drawer
	var before: float = drawer._scroll
	overlay._input(_mouse_motion(Vector2(400.0, 300.0), Vector2(0.0, 20.0)))
	assert_float(drawer._scroll).is_greater(before)


func test_mouse_scroll_settles_on_a_centred_row_without_runaway() -> void:
	var overlay = _drawer_overlay()
	var drawer = overlay._drawer
	for i in range(4):
		overlay._input(_mouse_motion(Vector2(400.0, 300.0), Vector2(0.0, 14.0)))
	assert_float(drawer._scroll).is_equal_approx(56.0, 0.01) # clamp a max_scroll (2 filas)
	for i in range(120):
		drawer.drive(0.0, 0, 1.0 / 60.0)
	assert_int(drawer.focused_index()).is_equal(1)
	assert_float(drawer._scroll).is_equal_approx(56.0, 0.5)


func test_drawer_wheel_steps_the_list_like_the_dpad() -> void:
	var overlay = _drawer_overlay()
	var drawer = overlay._drawer
	drawer.focus_row(0)
	overlay._input(_wheel(BUTTON_WHEEL_DOWN))
	assert_int(drawer.focused_index()).is_equal(1)
	overlay._input(_wheel(BUTTON_WHEEL_UP))
	assert_int(drawer.focused_index()).is_equal(0)


func test_mouse_right_click_leaves_the_drawer() -> void:
	# Sin puntero el click izquierdo acciona la fila centrada; el derecho sale. Vuelve al dial
	# si el drawer salio de el, o al juego si se entro directo.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	overlay._select(RadialSelectorV2.HUB_INDEX)
	assert_bool(overlay._drawer_open()).is_true()
	overlay._input(_mouse_click(true, Vector2(400.0, 300.0), BUTTON_RIGHT))
	assert_bool(overlay._drawer_open()).is_false()
	assert_bool(overlay._selector.is_open()).is_true()


func test_hud_nav_reads_the_arrow_keys_like_the_dpad() -> void:
	var provider := InputProviderV2.new()
	Input.action_press("ui_down")
	var down = provider.get_input()
	Input.action_release("ui_down")
	assert_int(int(down.hud_nav)).is_equal(1)
	Input.action_press("ui_up")
	var up = provider.get_input()
	Input.action_release("ui_up")
	assert_int(int(up.hud_nav)).is_equal(-1)


func test_hud_widget_activate_slot_travels_in_the_stream() -> void:
	# El tap de un widget de interactuable fijado viaja como campo del stream: el replay lo repite.
	var frame := InputDataV2.new()
	frame.hud_widget_activate_slot = 2
	var round_trip := InputDataV2.new()
	round_trip.from_dict(frame.to_dict())
	assert_int(round_trip.hud_widget_activate_slot).is_equal(2)


func test_ui_accept_no_longer_fires_on_space() -> void:
	# Espacio es jump (B/cancelar en el HUD). Si ademas fuera ui_accept, con el dial abierto
	# confirmaba y cancelaba en el mismo frame. Enter/A/Start siguen confirmando.
	var has_space: bool = false
	var has_enter: bool = false
	for ev in InputMap.get_action_list("ui_accept"):
		if ev is InputEventKey and not ev.echo:
			if ev.scancode == KEY_SPACE:
				has_space = true
			elif ev.scancode == KEY_ENTER:
				has_enter = true
	assert_bool(has_space).is_false()
	assert_bool(has_enter).is_true()
	for ev in InputMap.get_action_list("ui_select"):
		if ev is InputEventKey:
			assert_int(ev.scancode).is_not_equal(KEY_SPACE)


func test_drawer_touch_star_toggles_favorite_and_row_tap_opens() -> void:
	var overlay = _drawer_overlay()
	var drawer = overlay._drawer
	drawer.focus_row(0)
	var id: String = drawer.row_id(0)
	var was_favorite: bool = SuitOS.is_favorite(id)
	# La estrella alterna favorito sin abrir la pantalla.
	var star: Vector2 = drawer.favorite_center(0)
	overlay._input(_touch(true, star))
	overlay._input(_touch(false, star))
	assert_int(int(SuitOS.is_favorite(id))).is_not_equal(int(was_favorite))
	assert_str(SuitOS.get_active_screen_id()).is_not_equal(id)
	# El resto de la fila si la abre (la pantalla queda abierta).
	var center: Vector2 = drawer.focused_row_center()
	overlay._input(_touch(true, center))
	overlay._input(_touch(false, center))
	assert_str(SuitOS.get_active_screen_id()).is_equal(id)


func test_dragging_a_drawer_row_onto_a_slot_pins_it_there() -> void:
	var overlay = _drawer_overlay()
	var drawer = overlay._drawer
	drawer.focus_row(1)
	var id: String = drawer.row_id(1)
	assert_str(id).is_equal("test:b")
	var start: Vector2 = drawer.focused_row_center()
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var slot: Rect2 = host.slot_rect(2)
	var drop: Vector2 = slot.position + slot.size * 0.5
	# El dedo si es puntero: toca la fila, la arrastra al slot y la suelta.
	overlay._input(_touch(true, start))
	overlay._input(_screen_drag(drop))
	assert_object(overlay._drag_ghost).is_not_null()
	assert_str(overlay._drag_ghost.text).is_equal("Beta")
	assert_bool(host._drop_targets_visible).is_true()
	overlay._input(_touch(false, drop))
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:b", ""])
	# El drawer sigue abierto para seguir asignando, y los destinos se apagan.
	assert_bool(overlay._drawer_open()).is_true()
	assert_bool(host._drop_targets_visible).is_false()


func test_the_arc_is_ordered_by_relevance_when_it_opens() -> void:	# FD-306 §2: relevancia alta al primer sector (a las 6), que es el que el pulgar encuentra.
	_screen("test:a", "Alpha", 0.0)
	_screen("test:b", "Beta", 0.9)
	var overlay = _open_and_play([UP])
	assert_array(overlay._dial_ids).is_equal(["test:b", "test:a"])
	assert_str(overlay._selector.option_id(0)).is_equal("test:b")


func test_registering_a_screen_with_the_hud_open_reaches_the_list() -> void:
	# FD-306 §5: el overlay leia el registry una sola vez en _ready().
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play([UP])
	assert_int(overlay._screen_ids.size()).is_equal(2)
	_screen("test:c", "Charlie")
	assert_int(overlay._screen_ids.size()).is_equal(3)
	SuitOS.unregister_screen("test:c")
	assert_int(overlay._screen_ids.size()).is_equal(2)


func test_the_gamepad_script_replays_the_same_way_it_played() -> void:
	# FD-304 §11: hombros y botones de cara entran por el stream, asi que el mismo guion tiene
	# que dar el mismo resultado dos veces.
	var script := _slot_held(3, Gesture.HOLD_TICKS) \
		+ [{"hud_slot": 3, "move_vec": [0.0, -1.0], "analog_move_active": true},
			{"move_vec": [0.0, -1.0], "analog_move_active": true}]
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	_open_slot_and_play(3, script)
	var first: Array = [SuitOS.get_active_screen_id(), SuitOS.get_pinned_slots()]
	SuitOS.close_hud_mode()
	yield(_await_overlay_freed(), "completed")
	SuitOS.clear_slots()

	_open_slot_and_play(3, script)
	assert_str(SuitOS.get_active_screen_id()).is_equal(first[0])
	assert_array(SuitOS.get_pinned_slots()).is_equal(first[1])


func test_crouch_drags_a_dial_item_onto_a_slot_with_the_stick() -> void:
	# Revision 2026-09-19: CROUCH es el clic del dial. Sostenido y con el stick levanta el item
	# marcado y lo lleva a un slot; soltar lo fija ahi (drag/drop con mando).
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var host = SuitOS.get_node("SuitOSWidgetHost")
	# La segunda opcion (Beta) esta arriba del centro; apuntando ahi el dial la marca.
	overlay._point_at(Vector2(0.0, -overlay.AIM_RADIUS))
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)
	_play(overlay, [{}]) # un frame neutro suelta los flancos de cara que arrancan en "apretados"
	_play(overlay, [{"crouch": true}])
	assert_bool(overlay._crouch_drag_active).is_true()
	assert_object(overlay._drag_ghost).is_not_null()
	assert_str(overlay._drag_ghost.text).is_equal("Beta")

	# Stick hacia el slot 3: el cursor cruza y el fantasma lo sigue.
	var target: Vector2 = host.slot_rect(2).get_center()
	var push := {"crouch": true, "move_vec": [0.0, 0.0], "analog_move_active": true}
	for _i in range(160):
		var dir: Vector2 = (target - overlay._cursor).normalized()
		push["move_vec"] = [dir.x, dir.y]
		_play(overlay, [push])
		if host.slot_at(overlay._cursor) == 2:
			break
	assert_int(host.slot_at(overlay._cursor)).is_equal(2)

	# Soltar CROUCH (sin mover mas) suelta el item ahi; el dial sigue abierto para seguir asignando.
	_play(overlay, [{}])
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:b", ""])

func test_dropping_with_the_stick_does_not_also_activate_the_item_on_hold_release() -> void:
	# El gesto real sostiene el boton del HUD mientras arrastra. Al soltarlo, _release_tab_hold
	# caia en _confirm_or_dismiss() y ABRIA el item recien soltado: se arrastraba Y se activaba.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	assert_bool(SuitOS.open_hud_mode(true)).is_true()
	var overlay = _overlay()
	var host = SuitOS.get_node("SuitOSWidgetHost")
	overlay._tab_hold_active = true # el boton del HUD sigue apretado, como en el gesto real
	overlay._point_at(Vector2(0.0, -overlay.AIM_RADIUS))
	_play(overlay, [{}])
	_play(overlay, [{"crouch": true}])
	assert_bool(overlay._crouch_drag_active).is_true()

	var target: Vector2 = host.slot_rect(2).get_center()
	var push := {"crouch": true, "move_vec": [0.0, 0.0], "analog_move_active": true}
	for _i in range(160):
		var dir: Vector2 = (target - overlay._cursor).normalized()
		push["move_vec"] = [dir.x, dir.y]
		_play(overlay, [push])
		if host.slot_at(overlay._cursor) == 2:
			break
	_play(overlay, [{}]) # soltar A: suelta el item en el slot
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "test:b", ""])

	# Y ahora el release del boton del HUD: no debe activar nada.
	overlay._release_tab_hold()
	assert_str(SuitOS.get_active_screen_id()).is_equal("")
	assert_bool(overlay._crouch_drag_active).is_false()
	assert_bool(overlay._selector.is_open()).is_true()
