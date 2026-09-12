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
const CRYO_UI_PATH := "res://core_v2/levels/interiors/DomeIntroCryoDiagnosticsUI.tscn"
const HINT_BACKUP := "user://suitos_hints.cfg.test_bak"

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
	# El hint guarda en user:// si el hold ya se descubrio: se respalda el del jugador.
	var dir := Directory.new()
	if dir.file_exists(Gesture.HINT_CFG):
		dir.rename(Gesture.HINT_CFG, HINT_BACKUP)


func after() -> void:
	if is_instance_valid(_fake_scene):
		get_tree().current_scene = null
		_fake_scene.free()
	var dir := Directory.new()
	dir.remove(Gesture.HINT_CFG)
	if dir.file_exists(HINT_BACKUP):
		dir.rename(HINT_BACKUP, Gesture.HINT_CFG)


func before_test() -> void:
	_overlay_mgr = get_tree().root.get_node("OverlayUIManager")
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.unpin_screen()
	Directory.new().remove(Gesture.HINT_CFG)


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


func _held(ticks: int) -> Array:
	var frames: Array = []
	for _i in range(ticks):
		frames.append({"hud_mode": true})
	return frames


const UP := {"hud_mode": false}


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


func test_tap_opens_the_pinned_screen() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_screen("test:b")
	var overlay = _open_and_play([UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_bool(overlay._selector.is_open()).is_false()
	assert_bool(overlay._mount.is_showing()).is_true()


func test_tap_without_pin_opens_slot_a() -> void:
	_screen("test:a", "Alpha", 0.9)
	_screen("test:b", "Beta", 0.0)
	SuitOS.set_context({})
	_open_and_play([UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	assert_str(SuitOS.get_pinned_screen_id()).is_empty() # abrir por tap no fija


func test_hold_opens_the_radial_and_its_release_is_not_a_tap() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS - 1))
	assert_bool(overlay._selector.is_open()).is_false() # 0.38 s: todavia no
	_play(overlay, _held(1))
	assert_bool(overlay._selector.is_open()).is_true()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	# Soltar sin nada marcado y sin pantalla detras: el dial no se queda abierto. Y el release
	# no fue un tap (un tap habria abierto la ultima pantalla).
	_play(overlay, [UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_str(SuitOS.get_active_screen_id()).is_empty()


func test_in_view_tap_closes_and_hold_switches_without_closing() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_screen("test:a")
	var overlay = _open_and_play([UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	_play(overlay, _held(Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	# Soltar sin nada marcado vuelve a la pantalla que habia: el hold cambia sin cerrar.
	_play(overlay, [UP])
	assert_bool(overlay._selector.is_open()).is_false()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	# Tap en la vista: cierra y reanuda.
	_play(overlay, [{"hud_mode": true}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_tap_in_view_closes() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([UP, {"hud_mode": true}, UP])
	assert_object(_overlay()).is_null()
	assert_bool(get_tree().paused).is_false()


# Mantener TAB, apuntar hacia arriba (mouse_delta +Y = arriba) y soltar: con dos pantallas el
# dial pone la primera a las 6 y la segunda a las 12, y soltar elige lo marcado.
func _hold_and_pick_second() -> Array:
	return _held(Gesture.HOLD_TICKS) + [{"hud_mode": true, "mouse_delta": [0.0, 12.0]}, UP]


func test_pick_while_holding_is_a_peek_and_release_exits() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS)
		+ [{"hud_mode": true, "mouse_delta": [0.0, 12.0]}, {"hud_mode": true, "tool_fire_primary": true}])
	# Elegida con TAB todavia apretado: se entra y se usa (mouse virtual y clic)...
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_bool(overlay._selector.is_open()).is_false()
	# ...y soltar TAB sale del modo HUD.
	_play(overlay, [UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


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


func test_radial_pick_by_stream_pins_and_persists() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var overlay = _open_and_play(_hold_and_pick_second())
	assert_str(SuitOS.get_pinned_screen_id()).is_equal("test:b")
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_str(overlay._slots_label.text).contains("B · Beta")
	# Persistencia: viaja por el contrato replay_sync de SuitOS.
	assert_str(String(SuitOS.get_snapshot().get("pinned_screen_id", ""))).is_equal("test:b")


# Verification 1b: el mismo input grabado da el mismo resultado, sin leer estado en vivo.
func test_replaying_the_same_stream_gives_the_same_result() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	_open_and_play(_hold_and_pick_second())
	var first: Array = [SuitOS.get_pinned_screen_id(), SuitOS.get_active_screen_id()]
	SuitOS.close_hud_mode()
	SuitOS.unpin_screen()
	yield(await_idle_frame(), "completed")

	_open_and_play(_hold_and_pick_second())
	assert_array([SuitOS.get_pinned_screen_id(), SuitOS.get_active_screen_id()]).is_equal(first)


func test_single_screen_never_shows_the_radial() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_false()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")


func test_hold_hint_shows_until_first_use() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_screen("test:a")
	var overlay = _open_and_play([UP])
	assert_bool(overlay._hint.visible).is_true()
	assert_str(overlay._hint.text).is_equal("Mantén TAB para cambiar de pantalla")
	_play(overlay, _held(Gesture.HOLD_TICKS))
	assert_bool(overlay._hint.visible).is_false()
	assert_bool(Gesture.hold_discovered()).is_true()
	SuitOS.close_hud_mode()
	yield(await_idle_frame(), "completed")

	overlay = _open_and_play([UP])
	assert_bool(overlay._hint.visible).is_false()


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


func test_widget_tap_opens_the_screen_of_that_slot() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	host._active_screen_ids["slot_b"] = "test:b"
	var widget: Control = auto_free(Control.new())
	host._on_widget_gui_input(_touch(true), widget, "slot_b")
	host._on_widget_gui_input(_touch(false), widget, "slot_b")
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	_play(_overlay(), [UP]) # el dedo ya se solto: eso no es un tap que cierre
	assert_bool(SuitOS.is_hud_mode_active()).is_true()


func test_widget_hold_opens_the_radial() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	host._press_msec = OS.get_ticks_msec() - 500 # > HOLD_MSEC
	host._on_widget_gui_input(_touch(false), auto_free(Control.new()), "slot_a")
	assert_bool(_overlay()._selector.is_open()).is_true()


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
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS))
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
	SuitOS.pin_screen("test:a")
	var overlay = _open_and_play([UP])
	var dim: ColorRect = overlay.get_node("RadialSelector/Dim")
	assert_float(dim.color.a).is_less_equal(0.5)
	assert_bool(dim.is_visible_in_tree()).is_false()
	_play(overlay, _held(Gesture.HOLD_TICKS))
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
	SuitOS.pin_screen("test:a")
	var saved: Dictionary = SuitOS.get_snapshot()
	assert_array(saved.keys()).contains_exactly_in_any_order(["pinned_screen_id", "last_snapshots"])
	# JSON-safe: sobrevive ida y vuelta por JSON sin perder nada.
	assert_str(to_json(parse_json(to_json(saved)))).is_equal(to_json(saved))

	SuitOS.unpin_screen()
	SuitOS.restore_snapshot(saved)
	assert_str(SuitOS.get_pinned_screen_id()).is_equal("test:a")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_hud_widgets_hide_during_the_pause_menu_but_not_in_hud_mode() -> void:
	# Los widgets viven en el slot HUD (capa 115) y quedaban dibujados encima del menu de pausa.
	_screen("test:a", "Alpha", 0.9)
	SuitOS.set_context({})
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget = _overlay_mgr.get_slot(_overlay_mgr.SLOT_HUD).get_node_or_null("SuitOS_Widget_slot_a")
	assert_object(widget).is_not_null()
	assert_bool(widget.visible).is_true()

	# Pausa del menu: se esconden.
	get_tree().paused = true
	host.refresh_for_pause()
	assert_bool(widget.visible).is_false()

	# Pausa del modo HUD: se ven (tocarlos cambia de pantalla).
	PauseManager._hud_mode_paused = true
	host.refresh_for_pause()
	assert_bool(widget.visible).is_true()
	PauseManager._hud_mode_paused = false

	# Reanudar: vuelven.
	get_tree().paused = false
	host.refresh_for_pause()
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
	var overlay = _open_and_play(_held(Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	var cursor = overlay._virtual_mouse
	assert_bool(cursor.is_processing_input()).is_false() # el gamepad no lo activa
	assert_bool(cursor.is_processing()).is_false()        # el stick no lo mueve
	assert_bool(cursor.visible).is_false()

	# Elegida una pantalla vuelve: ahi si sirve para hacer clic en su UI.
	_play(overlay, [{"hud_mode": true, "mouse_delta": [0.0, 12.0]}, UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:b")
	assert_bool(cursor.is_processing_input()).is_true()
	assert_bool(cursor.is_processing()).is_true()



func test_widget_without_screen_frees_the_pointer_like_a_screen_cursor() -> void:
	# Un hudable sin Pantalla muestra su widget ampliado; el terminal trae su propio cursor y el
	# widget no: con el mouse capturado no habia con que hacerle clic.
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_screen("test:a")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var overlay = _open_and_play([UP])
	assert_bool(is_instance_valid(overlay._mount.get_widget())).is_true()
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)

	# El dial se apunta con el mouse capturado.
	_play(overlay, _held(Gesture.HOLD_TICKS))
	assert_bool(overlay._selector.is_open()).is_true()
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)

	# Soltar sin elegir vuelve al widget: puntero libre otra vez.
	_play(overlay, [UP])
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)

	# Salir devuelve el mouse como estaba.
	overlay._exit()
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
