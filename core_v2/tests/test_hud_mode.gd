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
	_play(overlay, _held(1) + [UP])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	assert_str(SuitOS.get_active_screen_id()).is_empty()


func test_in_view_tap_closes_and_hold_switches_without_closing() -> void:
	_screen("test:a", "Alpha")
	_screen("test:b", "Beta")
	SuitOS.pin_screen("test:a")
	var overlay = _open_and_play([UP])
	assert_str(SuitOS.get_active_screen_id()).is_equal("test:a")
	_play(overlay, _held(Gesture.HOLD_TICKS) + [UP])
	assert_bool(overlay._selector.is_open()).is_true()
	assert_bool(SuitOS.is_hud_mode_active()).is_true()
	# Tap en el radial (o en la vista): cierra y reanuda.
	_play(overlay, [{"hud_mode": true}, UP])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_tap_in_view_closes() -> void:
	_screen("test:a", "Alpha")
	var overlay = _open_and_play([UP, {"hud_mode": true}, UP])
	assert_object(_overlay()).is_null()
	assert_bool(get_tree().paused).is_false()


# Gesto hacia arriba (mouse_delta +Y = arriba) y click: con dos pantallas el dial pone la
# primera a las 6 y la segunda a las 12, asi que elige la segunda.
func _hold_and_pick_second() -> Array:
	return _held(Gesture.HOLD_TICKS) + [UP, {"mouse_delta": [0.0, 12.0]}, {"tool_fire_primary": true}]


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
	var overlay = _open_and_play([UP]) # unica pantalla: tap = vista
	var presenter = overlay._mount.get_presenter()
	assert_object(presenter).is_not_null()
	assert_object(presenter.get_parent()).is_equal(get_tree().current_scene)
	assert_int(presenter.pause_mode).is_equal(Node.PAUSE_MODE_PROCESS)
	assert_bool(presenter.is_in_group("replay_sync")).is_false()
	assert_bool(presenter.is_active).is_true()
	# Misma UI del terminal, en el Viewport PROPIO del presentador y a su resolucion de diseño.
	var viewport: Viewport = presenter.get_node("Viewport")
	assert_str(viewport.get_child(viewport.get_child_count() - 1).filename).is_equal(CRYO_UI_PATH)
	assert_vector2(viewport.size).is_equal(Vector2(1280, 816))
	# Lectura holografica del casco: vidrio casi transparente y tinta emisiva.
	assert_float(presenter.hud_cfg_background_alpha).is_equal_approx(0.15, 0.001)
	assert_float(presenter.hud_cfg_background_emission).is_equal_approx(3.0, 0.001)
	# El ScreenMesh ya no cuelga del presentador si el bridge lo engancho a la camara.
	var mesh = presenter._get_hud_attach_target()
	assert_object(mesh).is_not_null()
	var material: ShaderMaterial = mesh.material
	# El binario headless usa el rasterizer dummy: los ShaderMaterial no guardan uniformes
	# y get_shader_param() devuelve null. La config del casco ya se asierta sobre el nodo;
	# el material se revisa solo donde el rasterizer si lo expone. Mismo criterio que
	# test_ice_level.gd.
	if _exposes_shader_param(material, "albedo"):
		assert_float(material.get_shader_param("albedo").a).is_equal_approx(0.15, 0.001)
		assert_float(material.get_shader_param("emission_energy")).is_equal_approx(3.0, 0.001)

	# El overlay sale con queue_free: al final del frame cierra el presentador (se encoge y se va).
	SuitOS.close_hud_mode()
	yield(await_idle_frame(), "completed")
	assert_bool(presenter.is_active).is_false()


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


class MockFocusScreen:
	extends HUDableComponent

	var enter_called: bool = false
	var exit_called: bool = false
	var mock_origin: Dictionary = {}

	func view_transition_origin() -> Dictionary:
		return mock_origin

	func enter_focus_mode() -> void:
		enter_called = true

	func exit_focus_mode() -> void:
		exit_called = true

func test_focus_rig_origin_triggers_enter_and_exit_focus_mode() -> void:
	var mock = auto_free(MockFocusScreen.new())
	mock.hud_screen_id = "test:focus"
	mock.hud_screen_title = "Focus Screen"
	mock.mock_origin = {"kind": "focus_rig", "path": NodePath("Test/Path")}
	add_child(mock)

	_open_and_play([UP])
	assert_bool(mock.enter_called).is_true()
	assert_bool(mock.exit_called).is_false()

	SuitOS.close_hud_mode()
	yield(await_idle_frame(), "completed")
	assert_bool(mock.exit_called).is_true()

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


# El binario headless de CI usa el rasterizer dummy: los ShaderMaterial no guardan
# parametros y get_shader_param() devuelve null (float(null) es error de script). Mismo
# criterio que test_ice_level.gd / test_leak_fissure_visual.gd.
func _exposes_shader_param(material, param: String) -> bool:
	return material != null and material.get_shader_param(param) != null
