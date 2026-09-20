extends GdUnitTestSuite

# test_suitos_widget_host.gd - Integration tests for SuitOSWidgetHost, HangingDisplay, and auto-mounting (FD-296 F1.5)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const SuitOSWidgetHostScript = preload("res://core_v2/ui/hud/SuitOSWidgetHost.gd")
const HoloTerminalWidgetScript = preload("res://core_v2/ui/hud/HoloTerminalWidget.gd")
const HudSlots = preload("res://core_v2/ui/hud/HudSlots.gd")

var _widget_host: Node = null
var _overlay_mgr = null

func before() -> void:
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)

func before_test() -> void:
	var root = get_tree().root
	_overlay_mgr = root.get_node_or_null("OverlayUIManager")
	if _overlay_mgr == null:
		_overlay_mgr = OverlayUIManager.new()
		_overlay_mgr.name = "OverlayUIManager"
		root.add_child(_overlay_mgr)

	# Sin la ultima posicion del puntero de otra suite (decide si un toque es de un boton del widget).
	SuitOS.get_node("SuitOSWidgetHost")._last_pointer_position = Vector2(-10000, -10000)
	_widget_host = SuitOSWidgetHostScript.new()
	_widget_host.name = "SuitOSWidgetHost"
	root.add_child(_widget_host)

func after_test() -> void:
	if is_instance_valid(_widget_host):
		_widget_host.free()

func test_suitos_auto_mounts_driver_and_widget_host() -> void:
	assert_object(SuitOS.get_node_or_null("SuitOSContextDriver")).is_not_null()
	assert_object(SuitOS.get_node_or_null("SuitOSWidgetHost")).is_not_null()


func test_context_widget_sits_at_the_bottom_centered_and_leaves_with_clear() -> void:
	# El widget del interactuable va abajo-centro y NO depende de un slot libre: es efimero, no se
	# fija, y se va con clear_context. Aunque todos los slots esten ocupados, se muestra.
	for i in range(HudSlots.COUNT):
		SuitOS.clear_slot(i)
	var slot_hud = _widget_host.get_widget_root()
	assert_bool(_widget_host.show_context({"title": "Caja", "action": "Interactuar"})).is_true()
	var context = slot_hud.get_node_or_null("SuitOS_Context")
	assert_object(context).is_not_null()
	assert_bool(context.visible).is_true()
	assert_str((context.get_node("Row/VBox/Title") as Label).text).is_equal("Caja")
	var view: Vector2 = _widget_host.get_viewport_rect().size
	assert_float(context.rect_position.y).is_greater(view.y * 0.5)
	for i in range(HudSlots.COUNT):
		SuitOS.pin_to_slot(i, "test:x%d" % i)
	# Con todos los slots ocupados igual se muestra: no compite por un slot.
	assert_bool(_widget_host.show_context({"title": "Otra", "action": "x"})).is_true()
	_widget_host.clear_context()
	var gone = slot_hud.get_node_or_null("SuitOS_Context")
	assert_bool(gone == null or gone.is_queued_for_deletion()).is_true()
	for i in range(HudSlots.COUNT):
		SuitOS.clear_slot(i)

func test_widget_changed_mounts_and_unmounts_overlay() -> void:
	var dummy_screen = auto_free(HUDableComponentScript.new())
	dummy_screen.hud_screen_id = "test:dummy_screen"
	dummy_screen.hud_screen_title = "Dummy Screen Title"
	dummy_screen.default_relevance = 0.9
	add_child(dummy_screen)

	SuitOS.register_screen(dummy_screen)
	SuitOS.pin_to_slot(0, "test:dummy_screen")

	var slot_hud = _widget_host.get_widget_root()
	assert_object(slot_hud).is_not_null()

	var overlay_node = slot_hud.get_node_or_null("SuitOS_Widget_slot_1")
	assert_object(overlay_node).is_not_null()
	assert_bool(overlay_node is Label).is_true()
	assert_str((overlay_node as Label).text).contains("Dummy Screen Title")

	# Vaciar el slot -> empty snapshot -> remove_overlay (desregistrar lo dejaria offline, fijado)
	SuitOS.clear_slot(0)
	SuitOS.unregister_screen(dummy_screen)
	yield(get_tree(), "idle_frame")

	var freed_node = slot_hud.get_node_or_null("SuitOS_Widget_slot_1")
	assert_bool(freed_node == null or freed_node.is_queued_for_deletion()).is_true()

func test_hanging_display_registration_and_slot_flow() -> void:
	var hanging_display_scene = load("res://core_v2/levels/interiors/DomeIntroCryoDiagnosticsDisplay.tscn")
	assert_object(hanging_display_scene).is_not_null()

	var display_inst = auto_free(hanging_display_scene.instance())
	assert_object(display_inst).is_not_null()
	display_inst.translation = Vector3(1.0, 2.0, 3.0)
	add_child(display_inst)

	var hudable_comp = display_inst.get_node_or_null("HoloTerminalHUDable")
	assert_object(hudable_comp).is_not_null()

	var screen_id: String = hudable_comp.screen_id()
	assert_bool(SuitOS.has_screen(screen_id)).is_true()

	SuitOS.pin_to_slot(0, screen_id)

	var slot_1_snap: Dictionary = SuitOS.get_slot_snapshot("slot_1")
	assert_str(String(slot_1_snap.get("id", ""))).is_equal(screen_id)

	var slot_hud = _widget_host.get_widget_root()
	var widget_a = slot_hud.get_node_or_null("SuitOS_Widget_slot_1")
	assert_object(widget_a).is_not_null()
	assert_object(widget_a.get_script()).is_equal(HoloTerminalWidgetScript)

	# Pin to slot 3
	SuitOS.pin_to_slot(2, screen_id)
	var slot_3_snap: Dictionary = SuitOS.get_slot_snapshot("slot_3")
	assert_str(String(slot_3_snap.get("id", ""))).is_equal(screen_id)

	var widget_3 = slot_hud.get_node_or_null("SuitOS_Widget_slot_3")
	assert_object(widget_3).is_not_null()
	assert_object(widget_3.get_script()).is_equal(HoloTerminalWidgetScript)

	SuitOS.clear_slots()

# Cada slot tiene su lugar fijo: 1 y 2 a la izquierda, 3 y 4 a la derecha. No se pisan, y un
# slot no se mueve si otro queda vacio.
func test_slots_sit_in_fixed_places_without_overlap() -> void:
	var widgets := {}
	var screens := []
	for i in range(4):
		var screen = auto_free(HUDableComponentScript.new())
		screen.hud_screen_id = "test:s%d" % i
		screen.hud_widget_scene = preload("res://core_v2/ui/hud/SystemStatusWidget.tscn")
		add_child(screen)
		screens.append(screen)
		SuitOS.pin_to_slot(i, screen.hud_screen_id)
	SuitOS.set_context({})

	var slot_hud = _widget_host.get_widget_root()
	var rects := []
	for i in range(4):
		var widget: Control = slot_hud.get_node("SuitOS_Widget_slot_%d" % (i + 1))
		widgets[i] = widget
		rects.append(Rect2(widget.rect_position, widget.rect_size * widget.rect_scale))
	for i in range(4):
		for j in range(i + 1, 4):
			assert_bool(rects[i].intersects(rects[j])) \
				.override_failure_message("%d %s pisa a %d %s" % [i + 1, rects[i], j + 1, rects[j]]).is_false()
	var width: float = _widget_host.get_viewport().get_visible_rect().size.x
	# 1 y 2 a la izquierda, uno sobre otro; 3 y 4 a la derecha, uno sobre otro.
	assert_float(rects[0].position.x).is_equal(rects[1].position.x)
	assert_float(rects[2].position.x).is_equal(rects[3].position.x)
	assert_bool(rects[0].position.x < width * 0.5).is_true()
	assert_bool(rects[2].position.x > width * 0.5).is_true()
	assert_bool(rects[1].position.y > rects[0].position.y).is_true()
	assert_float(rects[2].position.y).is_equal(rects[0].position.y)

	var position_4: Vector2 = widgets[3].rect_position
	SuitOS.clear_slot(2)
	yield(await_idle_frame(), "completed")
	assert_vector2(slot_hud.get_node("SuitOS_Widget_slot_4").rect_position).is_equal(position_4)

	SuitOS.clear_slots()
	for screen in screens:
		SuitOS.unregister_screen(screen)


func test_widgets_are_opaque_and_hide_with_the_idle_touch_controls() -> void:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:opaque"
	add_child(screen)
	SuitOS.pin_to_slot(0, "test:opaque")
	var widget: CanvasItem = _widget_host.get_widget_root().get_node("SuitOS_Widget_slot_1")
	assert_float(widget.modulate.a).is_equal(1.0)

	var was_mobile: bool = MobileUIManager._is_mobile
	var was_active: bool = MobileUIManager._is_touch_active
	MobileUIManager._is_mobile = true
	MobileUIManager._is_touch_active = true
	MobileUIManager.emit_signal("touch_active_changed", true)
	assert_bool(widget.visible).is_true()
	# Inactividad en el telefono: se van con los controles tactiles...
	MobileUIManager._deactivate_touch()
	assert_bool(widget.visible).is_false()
	assert_bool(_widget_host.get_widget_root().get_node("SuitOS_Placeholder_slot_2").visible).is_false()
	# ...y vuelven con el proximo toque.
	MobileUIManager._is_touch_active = true
	MobileUIManager.emit_signal("touch_active_changed", true)
	assert_bool(widget.visible).is_true()

	MobileUIManager._is_mobile = was_mobile
	MobileUIManager._is_touch_active = was_active
	MobileUIManager.emit_signal("touch_active_changed", was_active)
	SuitOS.clear_slots()
	SuitOS.unregister_screen(screen)

func test_widgets_hide_during_cinematics_and_return_afterwards() -> void:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:cinematic_visibility"
	add_child(screen)
	SuitOS.pin_to_slot(0, "test:cinematic_visibility")
	var widget: CanvasItem = _widget_host.get_widget_root().get_node("SuitOS_Widget_slot_1")
	assert_bool(widget.visible).is_true()

	_widget_host._on_cinematic_started("test_rig")
	assert_bool(_widget_host._cinematic_active).is_true()
	yield(await_millis(250), "completed")
	assert_bool(widget.visible).is_false()
	_widget_host._on_cinematic_stopped()
	yield(await_millis(250), "completed")
	assert_bool(widget.visible).is_true()

	SuitOS.clear_slots()
	SuitOS.unregister_screen(screen)


func _pointer(pressed: bool, at: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.position = at
	return ev


func _swipe(slot: String, from: Vector2, to: Vector2) -> Control:
	var widget: Control = auto_free(Control.new())
	_widget_host._input(_pointer(true, from))
	_widget_host._on_widget_gui_input(_pointer(true, from), widget, slot)
	_widget_host._input(_pointer(false, to))
	_widget_host._on_widget_gui_input(_pointer(false, to), widget, slot)
	return widget


func test_outward_swipe_empties_the_slot_and_inward_does_not() -> void:
	SuitOS.pin_to_slot(0, "test:left")
	SuitOS.pin_to_slot(3, "test:right")
	# Hacia adentro (el 1 hacia la derecha): no vacia. Sin pantallas registradas tampoco abre nada.
	_swipe("slot_1", Vector2(100, 50), Vector2(200, 50))
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:left", "", "", "test:right"])
	# Hacia afuera: el 1 a la izquierda, el 4 a la derecha.
	var left := _swipe("slot_1", Vector2(100, 50), Vector2(10, 55))
	assert_bool(_widget_host._exiting_controls.has(left)).is_true()
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:left", "", "", "test:right"])
	yield(await_millis(int(_widget_host.SWIPE_EXIT_DURATION * 500.0)), "completed")
	assert_float(left.rect_position.x).is_less(0.0)
	assert_float(left.modulate.a).is_less(1.0)
	yield(await_millis(int(_widget_host.SWIPE_EXIT_DURATION * 500.0) + 50), "completed")
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", "test:right"])
	var right := _swipe("slot_4", Vector2(500, 50), Vector2(600, 45))
	assert_bool(_widget_host._exiting_controls.has(right)).is_true()
	yield(await_millis(int(_widget_host.SWIPE_EXIT_DURATION * 1000.0) + 50), "completed")
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])
	assert_bool(SuitOS.is_hud_mode_active()).is_false()


func test_widget_buttons_stay_pressable_and_their_touch_does_not_open_hud_mode():
	# Como en el control remoto: el toggle de la linterna se oprime con clic o dedo, y ese toque
	# no abre la pantalla (en Godot 3 un ScreenTouch sube por encima de un control STOP).
	var host = SuitOS.get_node("SuitOSWidgetHost")
	var widget: Control = auto_free(load("res://core_v2/ui/hud/FlashlightWidget.tscn").instance())
	add_child(widget)
	host._make_tappable(widget, "slot_2")
	var toggle: Control = widget.get_node("Margin/VBox/StatusRow/ToggleButton")
	assert_int(toggle.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(widget.get_node("Margin/VBox/StatusRow/StatusLabel").mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	yield(await_idle_frame(), "completed")

	var xf: Transform2D = toggle.get_global_transform_with_canvas()
	var on_button: Vector2 = xf.origin + toggle.rect_size * xf.get_scale() * 0.5
	var touch := InputEventScreenTouch.new()
	touch.position = on_button
	touch.pressed = true
	host._input(touch)
	host._on_widget_gui_input(touch, widget, "slot_2")
	touch = touch.duplicate()
	touch.pressed = false
	host._on_widget_gui_input(touch, widget, "slot_2")
	assert_bool(SuitOS.is_hud_mode_active()).is_false()



func test_widgets_stick_to_their_edge_at_any_render_scale() -> void:
	# En el celular la margen que reserva la UI tactil (borde derecho del joystick) empujaba el
	# widget a media pantalla. Va pegado a su borde, con el padding en unidades nominales (x k).
	# Se prueba _place sobre un widget propio: en este archivo conviven el host de SuitOS y el de
	# before_test, que se pisan el overlay montado por widget_changed.
	MobileUIManager._spawn_mobile_ui()
	MobileUIManager._mobile_ui.visible = true
	var widget := Label.new()
	widget.text = "widget"
	_widget_host.get_widget_root().add_child(widget)

	var before_scale: float = SettingsManager.render_scale
	for k in [1.0, 0.6]:
		SettingsManager.render_scale = k
		var safe: Rect2 = _widget_host._safe_rect()
		_widget_host._place(widget, "slot_2")
		assert_float(widget.rect_position.x).is_equal_approx(safe.position.x + HudSlots.SLOT_PADDING * k, 0.01)
		assert_float(widget.rect_position.y).is_equal_approx(safe.position.y
			+ (HudSlots.SLOT_PADDING + HudSlots.SLOT_ROW_HEIGHT + HudSlots.SLOT_GAP) * k, 0.01)
		assert_float(widget.rect_scale.x).is_less_equal(k + 0.001)
		_widget_host._place(widget, "slot_3")
		var right_edge: float = widget.rect_position.x + widget.rect_size.x * widget.rect_scale.x
		assert_float(right_edge).is_equal_approx(safe.end.x - HudSlots.SLOT_PADDING * k, 0.01)
		assert_float(widget.rect_position.y).is_equal_approx(safe.position.y + HudSlots.SLOT_PADDING * k, 0.01)

	SettingsManager.render_scale = before_scale
	MobileUIManager._mobile_ui.visible = false
	widget.free()



func test_widgets_draw_below_the_touch_controls_the_pause_menu_and_the_hud_mode() -> void:
	# Capa propia por debajo de la UI tactil (10), del menu de pausa (50) y de OverlayUIManager
	# (115, donde viven el dial y la vista del modo HUD). Antes estaban en esa capa 115.
	var layer = _widget_host.get_widget_root().get_parent()
	assert_bool(layer is CanvasLayer).is_true()
	var touch_ui = load("res://core_v2/ui/MobileUI.tscn").instance()
	assert_int(layer.layer).is_less(touch_ui.layer)
	assert_int(layer.layer).is_less(50)
	assert_int(layer.layer).is_less(_overlay_mgr.layer)
	touch_ui.free()


func test_empty_slots_show_only_in_hud_mode_or_while_dragging() -> void:
	var root = _widget_host.get_widget_root()
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.clear_slots()
	var placeholder: Control = root.get_node("SuitOS_Placeholder_slot_3")
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:pinned"
	add_child(screen)
	# Jugando: los vacios no se ven.
	assert_bool(placeholder.visible).is_false()
	# Arrastrando: se ven como destino.
	_widget_host.show_drop_targets(true, -1)
	assert_bool(placeholder.visible).is_true()
	_widget_host.show_drop_targets(false)
	assert_bool(placeholder.visible).is_false()
	# En el modo HUD (solo el dial): se ven, del lado de su slot y sin texto.
	SuitOS._hud_mode_active = true
	_widget_host.refresh_visibility()
	assert_bool(placeholder.visible).is_true()
	assert_bool(placeholder.rect_position.x > _widget_host.get_viewport().get_visible_rect().size.x * 0.5).is_true()
	assert_int(placeholder.get_child_count()).is_equal(0)
	# Con un widget en el slot el contorno se oculta.
	SuitOS.pin_to_slot(2, "test:pinned")
	assert_bool(placeholder.visible).is_false()
	SuitOS._hud_mode_active = false
	SuitOS.clear_slots()
	_widget_host.refresh_visibility()
	assert_bool(placeholder.visible).is_false()
	SuitOS.unregister_screen(screen)

func test_a_right_slot_widget_that_grows_stays_against_its_edge() -> void:
	var widget := Label.new()
	widget.text = "corto"
	_widget_host.get_widget_root().add_child(widget)
	_widget_host._place(widget, "slot_4")
	var safe: Rect2 = _widget_host._safe_rect()
	var edge := func_right_edge(widget)
	widget.text = "un texto bastante mas largo que el anterior"
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	assert_float(func_right_edge(widget)).is_equal_approx(edge, 0.5)
	assert_float(func_right_edge(widget)).is_less_equal(safe.end.x)
	widget.free()


func func_right_edge(control: Control) -> float:
	return control.rect_position.x + control.rect_size.x * control.rect_scale.x


func _drag_widget(widget: Control, slot: String, to: Vector2) -> void:
	var from: Vector2 = widget.get_global_rect().position + Vector2(10, 10)
	_widget_host._input(_pointer(true, from))
	_widget_host._on_widget_gui_input(_pointer(true, from), widget, slot)
	_widget_host._press_msec = OS.get_ticks_msec() - 500 # pasado el hold
	var drag := InputEventScreenDrag.new()
	drag.position = to
	_widget_host._input(drag)
	assert_bool(_widget_host._dragging).is_true()
	# Mientras se arrastra, el slot de abajo se ve como destino.
	var target: int = _widget_host.slot_at(to)
	if target >= 0:
		assert_bool(_widget_host.get_widget_root().get_node("SuitOS_Placeholder_slot_%d" % (target + 1)).visible).is_true()
	_widget_host._input(_pointer(false, to))
	_widget_host._on_widget_gui_input(_pointer(false, to), widget, slot)
	assert_bool(_widget_host._dragging).is_false()


func test_dragging_a_widget_onto_another_slot_swaps_them_and_elsewhere_returns_it() -> void:
	var screens := []
	for id in ["test:a", "test:b"]:
		var screen = auto_free(HUDableComponentScript.new())
		screen.hud_screen_id = id
		add_child(screen)
		screens.append(screen)
	SuitOS.pin_to_slot(0, "test:a")
	SuitOS.pin_to_slot(2, "test:b")
	var root = _widget_host.get_widget_root()
	var widget: Control = root.get_node("SuitOS_Widget_slot_1")
	assert_bool(widget.is_in_group("touch_control")).is_true() # la camara no toma ese toque

	# Al medio de la pantalla (ningun slot): vuelve a su lugar, nada cambia.
	var home: Vector2 = widget.rect_position
	_drag_widget(widget, "slot_1", _widget_host.get_viewport().get_visible_rect().size * 0.5)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:a", "", "test:b", ""])
	assert_vector2(widget.rect_position).is_equal(home)

	# Sobre el slot 3: intercambian.
	var slot_3: Rect2 = _widget_host.slot_rect(2)
	_drag_widget(widget, "slot_1", slot_3.position + slot_3.size * 0.5)
	assert_array(SuitOS.get_pinned_slots()).is_equal(["test:b", "", "test:a", ""])
	SuitOS.clear_slots()
	for screen in screens:
		SuitOS.unregister_screen(screen)


func test_dropping_a_dragged_widget_on_the_recycle_zone_removes_it() -> void:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:a"
	add_child(screen)
	SuitOS.pin_to_slot(2, "test:a")
	var widget: Control = _widget_host.get_widget_root().get_node("SuitOS_Widget_slot_3")
	var recycle: Rect2 = _widget_host.recycle_rect()
	var from: Vector2 = widget.get_global_rect().position + Vector2(10, 10)
	_widget_host._input(_pointer(true, from))
	_widget_host._on_widget_gui_input(_pointer(true, from), widget, "slot_3")
	_widget_host._press_msec = OS.get_ticks_msec() - 500
	var drag := InputEventScreenDrag.new()
	drag.position = recycle.position + recycle.size * 0.5
	_widget_host._input(drag)
	# Aparece solo mientras se arrastra, y se enciende con el dedo encima.
	assert_bool(_widget_host._recycle.visible).is_true()
	assert_bool(_widget_host._recycle_hot).is_true()
	_widget_host._input(_pointer(false, drag.position))
	_widget_host._on_widget_gui_input(_pointer(false, drag.position), widget, "slot_3")
	assert_array(SuitOS.get_pinned_slots()).is_equal(["", "", "", ""])
	assert_bool(_widget_host._recycle.visible).is_false()
	# Ningun slot se llena solo con lo que se quito.
	for i in range(4):
		assert_str(SuitOS.slot_screen_id(i)).is_empty()
	SuitOS.unregister_screen(screen)


func test_a_dragged_widget_is_not_snapped_back_while_its_data_changes() -> void:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:a"
	add_child(screen)
	SuitOS.pin_to_slot(0, "test:a")
	var widget: Control = _widget_host.get_widget_root().get_node("SuitOS_Widget_slot_1")
	var from: Vector2 = widget.get_global_rect().position + Vector2(10, 10)
	_widget_host._input(_pointer(true, from))
	_widget_host._on_widget_gui_input(_pointer(true, from), widget, "slot_1")
	_widget_host._press_msec = OS.get_ticks_msec() - 500
	var drag := InputEventScreenDrag.new()
	drag.position = from + Vector2(200, 150)
	_widget_host._input(drag)
	var held: Vector2 = widget.rect_position
	# Llega un snapshot que lo redimensiona y hay un relayout: sigue donde esta el dedo.
	widget.emit_signal("resized")
	yield(await_idle_frame(), "completed")
	_widget_host._relayout()
	assert_vector2(widget.rect_position).is_equal(held)
	# El reciclaje va arriba, lejos de la mano.
	assert_bool(_widget_host.recycle_rect().position.y < _widget_host.get_viewport().get_visible_rect().size.y * 0.5).is_true()
	_widget_host._input(_pointer(false, from))
	_widget_host._on_widget_gui_input(_pointer(false, from), widget, "slot_1")
	SuitOS.clear_slots()
	SuitOS.unregister_screen(screen)



class FakeZoomPlayer extends KinematicBody:
	var base_spring_length_3d := 4.0
	var _cinematic_zoom_target_fov := -1.0


func test_zoom_ruler_shows_only_while_zooming_and_spreads_when_zooming_in() -> void:
	var ruler = SuitOS.get_node("SuitOSWidgetHost").get_widget_root().get_node("ZoomRuler")
	var player = auto_free(FakeZoomPlayer.new())
	add_child(player)
	var previous = SessionManager.player
	SessionManager.player = player
	ruler._process(0.016)
	# Quieto: no se ve (tampoco al aparecer el jugador, que no es un zoom).
	assert_bool(ruler.visible).is_false()
	var level_far: float = ruler._level
	player.base_spring_length_3d = 2.0 # acercar: la mitad de distancia, el doble de aumento
	ruler._process(0.016)
	assert_bool(ruler.visible).is_true()
	assert_float(ruler._level - level_far).is_equal_approx(1.0, 0.001)
	# Pasado el hold y el fundido sin cambios, se va.
	ruler._last_change_msec = OS.get_ticks_msec() - ruler.HOLD_MSEC - ruler.FADE_MSEC - 10
	ruler._process(0.016)
	assert_bool(ruler.visible).is_false()
	SessionManager.player = previous


func test_a_pinned_slot_is_not_shown_where_no_screens_are_registered() -> void:
	# En el menu no hay pantallas: la linterna por defecto no debe aparecer como "offline".
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.pin_to_slot(0, "player:flashlight")
	var widget: Control = _widget_host.get_widget_root().get_node("SuitOS_Widget_slot_1")
	_widget_host.refresh_visibility()
	assert_bool(widget.visible).is_false()
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:any"
	add_child(screen)
	assert_bool(widget.visible).is_true()
	SuitOS.clear_slots()
	SuitOS.unregister_screen(screen)


func test_a_slot_pinned_before_its_screen_exists_becomes_the_real_widget_when_it_arrives() -> void:
	# La linterna por defecto se fija desde el menu, antes de que exista su pantalla: nacia como rotulo
	# de reserva y se quedaba asi aunque la pantalla llegara despues.
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.pin_to_slot(0, "test:late")
	var root = _widget_host.get_widget_root()
	assert_bool(root.get_node("SuitOS_Widget_slot_1") is Label).is_true()
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:late"
	screen.hud_widget_scene = preload("res://core_v2/ui/hud/FlashlightWidget.tscn")
	add_child(screen)
	var widget = root.get_node("SuitOS_Widget_slot_1")
	assert_bool(widget is Label).is_false()
	assert_str(widget.filename).is_equal("res://core_v2/ui/hud/FlashlightWidget.tscn")
	SuitOS.clear_slots()
	SuitOS.unregister_screen(screen)
