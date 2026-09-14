extends GdUnitTestSuite

# test_remote_control_home_hud.gd - Tests for RemoteControlHome HUD UI client (FD-296 F4)

var RemoteControlHomeScene = load("res://core_v2/ui/RemoteControlHome.tscn")

func test_remote_home_instantiates_slot_widgets():
	# Los slots del telefono son suyos: la linterna en el 1 por defecto, y la lista del host no
	# autoasigna nada a los demas.
	var home = _home_with_dial([
		{"id": "player:flashlight", "title": "Linterna"},
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9}
	])
	assert_array(home.hud_backend.get_pinned_slots()).is_equal(["player:flashlight", "", "", ""])
	assert_object(_slot_widget(home, 0)).is_not_null()
	assert_str(String(home.widget_host._active_screen_ids.get("slot_1", ""))).is_equal("player:flashlight")
	for i in range(1, 4):
		assert_object(_slot_widget(home, i)).is_null()

	home.queue_free()

func test_remote_home_pin_local_screen():
	var home = _home_with_dial([
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.2}
	])
	home.hud_backend.pin_to_slot(2, "screen_b")

	assert_object(_slot_widget(home, 2)).is_not_null()
	assert_str(String(home.widget_host._active_screen_ids.get("slot_3", ""))).is_equal("screen_b")

	home.queue_free()

# --- Dial de pantallas en tactil (FD-296 F4) ---

class DummyClient extends Node:
	var host_paused: bool = false
	var ui_directives: Array = []
	var inputs: Array = []

	func send_ui_directive(op: String, payload) -> void:
		ui_directives.append({"op": op, "payload": payload})

	func send_input(input_type: String, payload: Dictionary) -> void:
		inputs.append({"type": input_type, "payload": payload})

	func get_resume_time_left() -> float:
		return 0.0

	var since_rx_ms: int = 100
	func ms_since_last_rx() -> int:
		return since_rx_ms

class DummyManager extends Node:
	var client: Node = null

const VIEW_SIZE := Vector2(1024.0, 600.0)
const TabGestureScript = preload("res://core_v2/ui/hud/HudTabGesture.gd")

func _home_with_dial(screens: Array = []) -> Control:
	var client = auto_free(DummyClient.new())
	var mgr = auto_free(DummyManager.new())
	mgr.client = client
	add_child(client)
	add_child(mgr)
	var home = RemoteControlHomeScene.instance()
	add_child(home)
	home._remote_control_manager = mgr
	home.rect_size = VIEW_SIZE
	if not screens.empty():
		home._on_ui_directive("screen_list", screens)
	return home

# El modo HUD del control: el mismo HudModeOverlay del juego, montado por RemoteHudBackend.
func _open_dial(home, slot: int = -1):
	home.hud_backend.open_hud_mode(true, "", slot)
	return home.hud_backend.get_overlay()

# Un tick del control y, si esta abierto, de su modo HUD (en el juego corren los dos solos).
func _tick(home) -> void:
	home._physics_process(0.016)
	var overlay = home.hud_backend.get_overlay()
	if overlay != null:
		overlay._physics_process(0.016)

# El centro del sector de la opcion de arriba (las 12), en pantalla.
func _top_slice(overlay) -> Vector2:
	var sel = overlay._selector
	var center: Vector2 = sel.get_global_rect().position + sel.rect_size * 0.5
	var mid: float = (sqrt(sel.width_min) + sqrt(sel.width_max)) / 4.0 * sel._ring_size()
	return center + Vector2(0.0, -mid)
func _slot_widget(home, index: int) -> Control:
	return home.widget_host.get_widget_root().get_node_or_null("SuitOS_Widget_slot_%d" % (index + 1)) as Control

func _dial_screens() -> Array:
	return [
		{"id": "screen_z", "title": "Screen Z", "relevance": 0.1},
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9}
	]

func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = at
	ev.pressed = pressed
	return ev

func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	return ev

func _motion(at: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.relative = relative
	return ev

func _click(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = BUTTON_LEFT
	ev.position = at
	ev.pressed = true
	return ev

func _action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev

func test_the_hud_mode_is_the_same_overlay_as_the_game():
	var home = _home_with_dial(_dial_screens())
	var overlay = _open_dial(home)
	assert_str(overlay.filename).is_equal("res://core_v2/ui/hud/HudModeOverlay.tscn")
	assert_bool(overlay.backend == home.hud_backend).is_true()
	assert_bool(overlay.get_parent() == home.get_node("HUDLayer")).is_true()
	assert_bool(overlay._selector.is_open()).is_true()
	# Sin pausa: el mundo sigue en el host.
	assert_bool(get_tree().paused).is_false()
	home.queue_free()

func test_open_radial_hides_what_is_behind():
	var home = _home_with_dial(_dial_screens())
	var root: Control = home.widget_host.get_widget_root()
	assert_bool(home.hud_backend.is_hud_mode_active()).is_false()
	assert_bool(root.get_node("SuitOS_Placeholder_slot_2").visible).is_false()

	# Con el dial a la vista los slots vacios muestran su contorno, como en el modo HUD del juego.
	_open_dial(home)
	assert_bool(home.hud_backend.is_hud_mode_active()).is_true()
	assert_bool(root.get_node("SuitOS_Placeholder_slot_2").visible).is_true()

	home._exit_hud_mode()
	assert_bool(root.get_node("SuitOS_Placeholder_slot_2").visible).is_false()

	home.queue_free()

func test_radial_tap_outside_closes_without_exit_dialog():
	var home = _home_with_dial(_dial_screens())
	var overlay = _open_dial(home)
	home._client().ui_directives.clear()

	# La esquina no es ninguna opcion: cierra el dial y NADA mas (no la sesion).
	overlay._input(_touch(0, Vector2(2.0, 2.0), true))
	overlay._input(_touch(0, Vector2(2.0, 2.0), false))

	assert_bool(home._hud_mode_active()).is_false()
	assert_bool(home.exit_confirm.visible).is_false()
	assert_array(home._client().ui_directives).is_empty()

	# Y tocar un sector lo elige.
	overlay = _open_dial(home)
	overlay._input(_touch(0, _top_slice(overlay), true))
	overlay._input(_touch(0, _top_slice(overlay), false))
	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	home.queue_free()

func test_radial_tap_confirms_the_marked_option():
	var home = _home_with_dial(_dial_screens())
	var overlay = _open_dial(home)
	# El mismo overlay sirve el HUD local y el control remoto: primero queda marcada
	# Screen A desde el stick/mouse, despues un tap en el hueco la confirma.
	overlay._point_at(Vector2(0.0, -overlay.AIM_RADIUS))
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)
	var center: Vector2 = overlay._selector.get_global_rect().position + overlay._selector.rect_size * 0.5
	overlay._input(_touch(0, center, true))
	overlay._input(_touch(0, center, false))

	assert_array(_screen_selects(home)).is_equal(["screen_a"])
	home.queue_free()

func test_radial_ui_cancel_closes_dial_not_session():
	var home = _home_with_dial(_dial_screens())
	var overlay = _open_dial(home)

	overlay._input(_action("ui_cancel"))
	assert_bool(home._hud_mode_active()).is_false()
	assert_bool(home.exit_confirm.visible).is_false()

	home.queue_free()

func test_open_dial_keeps_the_touch_stream_flowing():
	# En tactil los controles virtuales no se apagan nunca: con el dial abierto el
	# joystick sigue manejando al host (el dial solo toma el dedo que apunta).
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var client = home._client()

	_open_dial(home)
	client.inputs.clear()
	Input.action_press("crouch")
	home._physics_process(0.016)
	Input.action_release("crouch")
	assert_array(_acts(client, "crouch")).is_equal([true])

	home.queue_free()

func test_open_dial_suspends_mouse_forwarding_on_passthrough():
	# Con teclado y mouse si: mandar el mouse giraria la camara del host mientras se apunta.
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true
	var client = home._client()

	_open_dial(home)
	home._mouse_delta = Vector2(30.0, 0.0)
	client.inputs.clear()
	home._physics_process(0.016)
	assert_array(client.inputs).is_empty()

	home.queue_free()

func test_open_dial_releases_held_input_on_passthrough():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true # escritorio: los eventos crudos quedan apretados en el host
	var client = home._client()
	client.inputs.clear()

	_open_dial(home)

	assert_int(client.inputs.size()).is_equal(1)
	assert_str(String(client.inputs[0]["type"])).is_equal("release_all")

	home.queue_free()

func test_slot_widget_uses_title_and_snapshot_from_screen_list():
	var home = _home_with_dial([{
		"id": "holoterminal:Dome_Intro/HoloTerminal",
		"title": "Terminal del domo",
		"relevance": 0.9,
		"widget": "res://core_v2/ui/hud/HoloTerminalWidget.tscn",
		"snapshot": {"proto": 1, "id": "holoterminal:Dome_Intro/HoloTerminal",
			"title": "Terminal del domo", "active": true, "source": "online"}
	}])
	home.hud_backend.pin_to_slot(1, "holoterminal:Dome_Intro/HoloTerminal")

	# El snapshot de la lista queda guardado: es lo que le da nombre y estado al widget.
	var cached: Dictionary = home.hud_backend.snapshots.get("holoterminal:Dome_Intro/HoloTerminal", {})
	assert_str(String(cached.get("title", ""))).is_equal("Terminal del domo")
	assert_bool(bool(cached.get("active", false))).is_true()

	# Y la escena del widget se resuelve por la ruta que mando el host, no por el
	# SuitOS local (que en el control no tiene ninguna pantalla registrada).
	assert_object(home.hud_backend.resolve_widget_scene("holoterminal:Dome_Intro/HoloTerminal")).is_not_null()

	var widget = _slot_widget(home, 1)
	assert_object(widget).is_not_null()
	var title_label = widget.get_node_or_null("Margin/VBox/Header/TitleLabel")
	assert_object(title_label).is_not_null()
	assert_str(title_label.text).is_equal("Terminal del domo")

	home.queue_free()

func test_slot_widget_falls_back_to_title_not_id():
	# Sin snapshot ni escena (host viejo o pantalla recien registrada) igual se usa el titulo.
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.5}])

	var label = _slot_widget(home, 0)
	assert_bool(label is Label).is_true()
	assert_str(label.text).contains("Linterna")
	assert_bool(label.text.find("player:flashlight") == -1).is_true()

	home.queue_free()
func _tab_tap(home) -> void:
	Input.action_press("hud_mode")
	_tick(home)
	Input.action_release("hud_mode")
	_tick(home)
func _tab_hold(home) -> void:
	Input.action_press("hud_mode")
	for _i in range(TabGestureScript.HOLD_TICKS + 1):
		_tick(home)

func _tab_release(home) -> void:
	Input.action_release("hud_mode")
	_tick(home)

func test_tab_tap_opens_the_radial_and_taps_again_to_close():
	var home = _home_with_dial(_dial_screens())
	home._client().ui_directives.clear()

	# Tap: siempre el dial, como el modo HUD del juego. Otro tap lo cierra sin elegir.
	_tab_tap(home)
	assert_bool(home._radial_is_open()).is_true()
	_tab_tap(home)
	assert_bool(home._radial_is_open()).is_false()
	assert_array(home._client().ui_directives).is_empty()

	home.queue_free()

func test_tab_hold_opens_the_radial():
	var home = _home_with_dial(_dial_screens())
	home._client().ui_directives.clear()

	_tab_hold(home)

	# El hold saca el dial, y no eligio ninguna pantalla por su cuenta.
	assert_bool(home._radial_is_open()).is_true()
	assert_array(home._client().ui_directives).is_empty()

	# Soltar sin nada marcado: el dial no se queda abierto.
	_tab_release(home)
	assert_bool(home._radial_is_open()).is_false()
	assert_array(home._client().ui_directives).is_empty()

	home.queue_free()

func test_releasing_tab_picks_what_the_dial_has_marked():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true
	_tab_hold(home)
	home._client().ui_directives.clear()

	# Apunta hacia arriba (screen_a) con TAB todavia apretado, y suelta: queda elegida.
	var overlay = home.hud_backend.get_overlay()
	overlay._input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -80.0)))
	_tick(home)
	_tab_release(home)

	assert_bool(home._radial_is_open()).is_false()
	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	home.queue_free()

func test_pick_while_holding_tab_is_a_peek_and_release_exits():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true
	_tab_hold(home)
	home._client().ui_directives.clear()

	# Elige con clic sin soltar TAB: se entra ya...
	var overlay = home.hud_backend.get_overlay()
	overlay._input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -80.0)))
	_tick(home)
	overlay._input(_click(VIEW_SIZE * 0.5))
	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	# ...y soltar TAB sale, aunque el host todavia no haya confirmado la pantalla.
	_tab_release(home)
	assert_array(_screen_selects(home)).is_equal(["screen_a", ""])

	home.queue_free()

func test_tab_is_never_forwarded_to_the_host():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true
	var client = home._client()
	client.inputs.clear()

	# Ni el press ni el release: alla abriria el modo HUD del host.
	home._input(_action("hud_mode"))
	home._unhandled_input(_action("hud_mode"))
	for entry in client.inputs:
		assert_str(String(entry["type"])).is_not_equal("event")

	home.queue_free()

# Hermano del anterior para el camino tactil: el boton del HUD tampoco viaja como accion.
func test_hud_button_is_never_forwarded_as_an_action():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var client = home._client()
	client.inputs.clear()

	Input.action_press("hud_mode")
	Input.action_press("jump")
	home._physics_process(0.016)
	Input.action_release("hud_mode")
	Input.action_release("jump")

	assert_array(_acts(client, "hud_mode")).is_empty()
	# Y el resto sigue viajando: no se corta el stream, se excluye una accion.
	assert_array(_acts(client, "jump")).is_equal([true])

	home.queue_free()

func test_secondary_mouse_button_releases_mouse_instead_of_pausing_host():
	var home = _home_with_dial()
	home._raw_passthrough = true
	var client = home._client()
	client.inputs.clear()
	# Godot deja mouse_mode = CAPTURED aunque el grab falle (headless), asi que el
	# estado inicial es valido para el test.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var ev := InputEventMouseButton.new()
	ev.button_index = BUTTON_RIGHT
	ev.pressed = true
	home._input(ev)

	# El boton derecho esta mapeado a ui_cancel: reenviarlo pausaba la partida del host.
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_array(client.inputs).is_empty()

	home.queue_free()

func test_radial_keeps_every_input_while_open():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true # teclado y mouse: ahi el dial se queda con todo
	_open_dial(home)
	var client = home._client()
	client.inputs.clear()

	# Con el dial abierto nada de teclado, mouse ni gamepad viaja al host.
	home._unhandled_input(_action("jump"))
	home._unhandled_input(_joy(JOY_BUTTON_0, true))
	assert_array(client.inputs).is_empty()
	assert_bool(home._radial_is_open()).is_true()

	home.queue_free()

func test_repeated_screen_list_does_not_steal_the_dial_focus():
	# El host reenvia screen_list en cada cambio de widget; el dial abierto no puede
	# perder el marcado por eso (era lo que lo volvia inutilizable).
	var home = _home_with_dial(_dial_screens())
	var overlay = _open_dial(home)
	overlay._point_at(Vector2(0.0, -100.0))
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)

	var label_before = overlay._selector._buttons[1]
	for _i in range(5):
		home._on_ui_directive("screen_list", [
			{"id": "screen_z", "title": "Screen Z", "relevance": 0.1},
			{"id": "screen_a", "title": "Screen A", "relevance": 0.4,
				"snapshot": {"proto": 1, "id": "screen_a", "battery": 80.0}}])

	assert_int(overlay._selector.get_hovered_index()).is_equal(1)
	assert_bool(overlay._selector._buttons[1] == label_before).is_true()
	# El snapshot nuevo si entra (la lista sigue alimentando los widgets).
	assert_float(float(home.hud_backend.snapshots["screen_a"].get("battery", 0.0))).is_equal(80.0)

	# Una pantalla nueva si entra a la lista del dial abierto.
	home._on_ui_directive("screen_list", _dial_screens() + [{"id": "screen_b", "title": "Screen B"}])
	assert_int(overlay._screen_ids.size()).is_equal(3)

	home.queue_free()

func test_full_screen_view_mounts_the_scene_the_host_sent():
	var home = _home_with_dial([{"id": "holoterminal:cryo", "title": "Diagnostico de criogenia"}])
	home.hud_backend.open_hud_mode(false, "holoterminal:cryo")
	assert_array(_screen_selects(home)).is_equal(["holoterminal:cryo"])
	# La vista completa (UI del terminal) llega como ruta + resolucion de diseño: el
	# control no la puede resolver solo, no tiene la pantalla registrada.
	home._on_ui_directive("screen_active", {
		"id": "holoterminal:cryo",
		"title": "Diagnostico de criogenia",
		"view": "scene",
		"view_scene": "res://core_v2/ui/hud/HoloTerminalWidget.tscn",
		"view_size": [1280.0, 816.0],
		"snapshot": {"proto": 1, "id": "holoterminal:cryo", "title": "Diagnostico de criogenia"}
	})
	# Confirmarla no la vuelve a pedir.
	assert_array(_screen_selects(home)).is_equal(["holoterminal:cryo"])

	# Igual que el presentador del host: la UI se dibuja en un Viewport a su resolucion de diseño y
	# lo que se escala es la textura.
	var mount = home.hud_backend.get_overlay()._mount
	var frame: Control = mount._view_frame
	assert_object(frame).is_not_null()
	var container: ViewportContainer = frame.get_node("ViewViewport")
	assert_bool(container.stretch).is_false()
	# Y se ve como el holograma del host: su shader de vidrio, con el alfa del panel del presentador.
	var holo: ShaderMaterial = container.material
	assert_object(holo).is_not_null()
	assert_float((holo.get_shader_param("albedo") as Color).a).is_equal_approx(0.15, 0.001)
	assert_float(float(holo.get_shader_param("ink_level"))).is_equal_approx(0.686, 0.001)
	assert_float(float(holo.get_shader_param("emission_energy"))).is_equal_approx(3.0, 0.001)
	assert_vector2((container.get_child(0) as Viewport).size).is_equal(Vector2(1280.0, 816.0))

	# Escalado uniforme por el lado que sobra, y centrado.
	frame.rect_size = Vector2(640.0, 480.0)
	mount.fit_view_2d()
	assert_vector2(container.rect_scale).is_equal(Vector2(0.5, 0.5))
	assert_vector2(container.rect_position).is_equal(Vector2(0.0, 36.0))

	home.queue_free()

func test_terminal_camera_button_sends_focus_toggle_without_closing_remote_view():
	var home = _home_with_open_view()
	var overlay = home.hud_backend.get_overlay()
	home._on_ui_directive("screen_active", {
		"id": "holoterminal:cryo", "title": "Criogenia", "view": "scene",
		"view_scene": "res://core_v2/ui/hud/HoloTerminalWidget.tscn", "view_size": [1280.0, 816.0],
		"snapshot": {"proto": 1, "id": "holoterminal:cryo", "can_focus": true, "focused": false}
	})
	overlay._physics_process(0.016)
	assert_bool(overlay._camera_focus_button.visible).is_true()

	overlay._on_camera_focus_pressed()
	var sent: Dictionary = home._client().ui_directives.back()
	assert_str(String(sent["op"])).is_equal("remote_action")
	assert_str(String(sent["payload"]["screen_id"])).is_equal("holoterminal:cryo")
	assert_str(String(sent["payload"]["op"])).is_equal("toggle_focus")
	assert_bool(home._hud_mode_active()).is_true()
	assert_array(_screen_selects(home)).is_empty()
	home._on_ui_directive("screen_active", {
		"id": "holoterminal:cryo", "snapshot": {"proto": 1, "id": "holoterminal:cryo", "can_focus": true, "focused": true}
	})
	overlay._physics_process(0.016)
	assert_bool(overlay._camera_focus_button.pressed).is_true()
	home.queue_free()

func test_view_without_scene_still_falls_back_to_the_widget():
	# Una pantalla que presta su Viewport en vivo no se puede replicar: queda el widget ampliado.
	var home = _home_with_flashlight_view()
	var mount = home.hud_backend.get_overlay()._mount
	assert_object(mount.get_widget()).is_not_null()
	assert_object(mount._view_frame).is_null()
	home.queue_free()

func test_widget_button_sends_remote_action_instead_of_calling_local_suitos():
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna",
		"relevance": 0.9, "widget": "res://core_v2/ui/hud/FlashlightWidget.tscn",
		"snapshot": {"proto": 1, "id": "player:flashlight", "title": "Linterna",
			"on": false, "battery": 90.0, "battery_max": 100.0, "source": "online"}}])
	home._client().ui_directives.clear()

	var widget = _slot_widget(home, 0)
	assert_object(widget).is_not_null()
	var toggle = widget.get_node_or_null("Margin/VBox/StatusRow/ToggleButton")
	assert_object(toggle).is_not_null()

	toggle.emit_signal("pressed")

	# El SuitOS local no tiene esta pantalla (la partida corre en el host): la accion viaja.
	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["op"])).is_equal("remote_action")
	assert_str(String(sent[0]["payload"]["screen_id"])).is_equal("player:flashlight")
	assert_str(String(sent[0]["payload"]["op"])).is_equal("toggle")

	home.queue_free()

class LocalActionScreen extends HUDableComponent:
	var performed: Array = []

	func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
		performed.append(op)
		return {"ok": true}

func test_widget_action_still_goes_to_local_suitos_without_a_remote_host():
	# El mismo widget montado en el HUD local (sin ancestro que despache) tiene que
	# seguir llamando al SuitOS de aca: no se rompe el modo HUD del juego.
	var screen = auto_free(LocalActionScreen.new())
	screen.hud_screen_id = "player:flashlight"
	# SuitOS.perform_action filtra por allowed_actions antes de llamar a la pantalla.
	screen.allowed_actions_list = ["toggle"]
	SuitOS.register_screen(screen)

	var loose = auto_free(Control.new()) # auto_free() no declara tipo: := no puede inferir
	add_child(loose)
	preload("res://core_v2/ui/hud/HudWidgetAction.gd").perform(loose, "player:flashlight", "toggle")

	assert_array(screen.performed).is_equal(["toggle"])

	SuitOS.unregister_screen("player:flashlight")

# --- Layout de slots y toques sobre widgets (paridad con el host) ---

func test_slots_are_the_same_widget_host_as_the_game():
	# Los slots del telefono son el SuitOSWidgetHost del juego con otro backend: lo que se pule
	# alla (arrastre, reciclaje, swipe, contornos, ocultarse) llega aca sin copiarlo.
	var home = _home_with_dial(_dial_screens())
	assert_bool(home.widget_host is SuitOSWidgetHost).is_true()
	assert_bool(home.widget_host.backend == home.hud_backend).is_true()
	assert_bool(home.widget_host.is_in_group("hud_widget_host")).is_true()
	# Y la regla del zoom sigue el pellizco del telefono, que no tiene jugador.
	var ruler = home.widget_host.get_widget_root().get_node("ZoomRuler")
	var before: float = ruler._zoom_metric()
	home._on_camera_zoom(-1.0)
	assert_float(ruler._zoom_metric()).is_less(before)

	home.queue_free()

func test_widget_tap_opens_its_screen():
	var home = _home_with_dial(_dial_screens())
	home.hud_backend.pin_to_slot(1, "screen_a")
	home._client().ui_directives.clear()
	var widget = _slot_widget(home, 1)
	assert_object(widget).is_not_null()
	var host = home.widget_host
	host._last_pointer_position = Vector2(-10000, -10000)

	# Tap: press + release seguidos (muy por debajo del umbral de hold).
	host._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), true), widget, "slot_2")
	host._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), false), widget, "slot_2")

	assert_array(_screen_selects(home)).is_equal(["screen_a"])
	assert_bool(home._radial_is_open()).is_false()
	# Abrir no cambia los slots.
	assert_array(home.hud_backend.get_pinned_slots()).is_equal(["player:flashlight", "screen_a", "", ""])

	home.queue_free()

func test_only_the_dial_opened_for_a_slot_pins_what_is_picked():
	# La linterna (fijada por defecto) no esta en esta partida: tocarla abre el dial para su slot,
	# y lo elegido queda ahi.
	var home = _home_with_dial(_dial_screens())
	var host = home.widget_host
	var widget = _slot_widget(home, 0)
	host._last_pointer_position = Vector2(-10000, -10000)
	host._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), true), widget, "slot_1")
	host._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), false), widget, "slot_1")
	assert_bool(home._radial_is_open()).is_true()
	home.hud_backend.get_overlay()._select(1)
	assert_array(home.hud_backend.get_pinned_slots()).is_equal(["screen_a", "", "", ""])
	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	# El dial de TAB solo abre: nada se autoasigna.
	home._exit_hud_mode()
	_open_dial(home)._select(0)
	assert_array(home.hud_backend.get_pinned_slots()).is_equal(["screen_a", "", "", ""])

	home.queue_free()

func test_widget_internal_buttons_stay_clickable():
	# La linterna se enciende desde el widget: sus botones internos conservan la entrada
	# aunque el cuerpo del widget sea el boton de abrir pantalla.
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.9,
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"}])

	var widget = _slot_widget(home, 0)
	assert_object(widget).is_not_null()
	assert_int((widget as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var toggle = (widget as Control).get_node_or_null("Margin/VBox/StatusRow/ToggleButton")
	assert_object(toggle).is_not_null()
	assert_int((toggle as BaseButton).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# Los labels en cambio no se quedan comiendo los toques.
	var title_label = (widget as Control).get_node_or_null("Margin/VBox/Header/TitleLabel")
	if title_label != null:
		assert_int((title_label as Label).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

	home.queue_free()

# --- Controles virtuales con el dial abierto (tactil) ---

func _spawn_virtual_controls() -> Control:
	MobileUIManager._spawn_mobile_ui()
	MobileUIManager._mobile_ui.visible = true
	MobileUIManager._set_gameplay_controls_visible(true)
	return MobileUIManager._mobile_ui.get_node("Container/MoveJoystick") as Control

func _hide_virtual_controls() -> void:
	if is_instance_valid(MobileUIManager._mobile_ui):
		MobileUIManager._mobile_ui.visible = false

func _center_of(ctrl: Control) -> Vector2:
	var scale: Vector2 = ctrl.rect_scale
	return ctrl.rect_global_position + Vector2(ctrl.rect_size.x * abs(scale.x), ctrl.rect_size.y * abs(scale.y)) * 0.5

func test_touch_on_the_joystick_passes_through_the_open_dial():
	var joystick := _spawn_virtual_controls()
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var overlay = _open_dial(home)

	# El dedo sobre el joystick es del joystick: el dial no lo reclama ni lo consume.
	var on_joystick: Vector2 = _center_of(joystick)
	assert_bool(MobileUIManager.is_point_on_touch_controls(on_joystick)).is_true()
	overlay._input(_touch(0, on_joystick, true))
	overlay._input(_drag(0, on_joystick + Vector2(40.0, 0.0)))
	assert_int(overlay._touch_index).is_equal(-1)
	# Y soltarlo no cierra el dial (no era un toque fuera de las opciones).
	overlay._input(_touch(0, on_joystick, false))
	assert_bool(home._radial_is_open()).is_true()

	home.queue_free()
	_hide_virtual_controls()

func test_second_finger_picks_while_the_joystick_is_held():
	var joystick := _spawn_virtual_controls()
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var overlay = _open_dial(home)
	home._client().ui_directives.clear()

	# Dedo 0 caminando en el joystick, dedo 1 eligiendo en el dial: los dos a la vez.
	overlay._input(_touch(0, _center_of(joystick), true))
	var top: Vector2 = _top_slice(overlay)
	assert_bool(MobileUIManager.is_point_on_touch_controls(top)).is_false()
	overlay._input(_touch(1, top, true))
	overlay._input(_drag(0, _center_of(joystick) + Vector2(30.0, 0.0)))
	overlay._input(_touch(1, top, false))

	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	home.queue_free()
	_hide_virtual_controls()

func test_emulated_mouse_from_touch_does_not_drive_the_dial():
	# En tactil el mouse que llega es el emulado de los toques: un arrastre del joystick
	# no puede apuntar el dial, ni un toque en un boton confirmarlo.
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var overlay = _open_dial(home)
	home._client().ui_directives.clear()

	overlay._input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -80.0)))
	_tick(home)
	assert_int(overlay._selector.get_hovered_index()).is_equal(-1)
	var click := _click(VIEW_SIZE * 0.5)
	click.device = -1
	overlay._input(click)
	assert_array(home._client().ui_directives).is_empty()
	assert_bool(home._radial_is_open()).is_true()

	home.queue_free()

# --- Un solo protocolo: eventos de accion que dejan el estado sostenido en el host ---

# Las acciones enviadas para una accion dada, como lista de "apretada?" en orden.
func _acts(client, action: String) -> Array:
	var out: Array = []
	for entry in client.inputs:
		if String(entry["type"]) != "event":
			continue
		var p: Dictionary = entry["payload"]
		if String(p.get("k", "")) == "act" and String(p.get("a", "")) == action:
			out.append(bool(p.get("p", false)))
	return out

func test_held_crouch_is_sent_once_not_every_tick():
	# El bug: la foto por tick soltaba el crouch en cada hueco y el host sacaba flancos
	# falsos. Ahora viaja el cambio: apretar una vez, soltar una vez.
	var home = _home_with_dial()
	home._raw_passthrough = false
	var client = home._client()
	client.inputs.clear()

	Input.action_press("crouch")
	for _i in range(5):
		home._physics_process(0.016)
	Input.action_release("crouch")
	home._physics_process(0.016)
	home._physics_process(0.016)

	assert_array(_acts(client, "crouch")).is_equal([true, false])

	home.queue_free()

func test_analog_move_travels_as_strength_only_when_it_changes():
	var home = _home_with_dial()
	home._raw_passthrough = false
	var client = home._client()
	client.inputs.clear()

	Input.action_press("move_forward", 0.62)
	home._physics_process(0.016)
	home._physics_process(0.016) # mismo pulgar: nada nuevo
	Input.action_press("move_forward", 0.4)
	home._physics_process(0.016)
	Input.action_release("move_forward")
	home._physics_process(0.016)

	var strengths: Array = []
	for entry in client.inputs:
		var p: Dictionary = entry["payload"]
		if String(p.get("a", "")) == "move_forward":
			strengths.append(stepify(float(p["s"]), 0.01))
	assert_array(strengths).is_equal([0.62, 0.4, 0.0])

	home.queue_free()

func test_touch_camera_travels_in_its_own_units_once_per_tick():
	var home = _home_with_dial()
	home._raw_passthrough = false
	var client = home._client()
	client.inputs.clear()

	home._on_camera_drag(Vector2(3.0, -1.0))
	home._on_camera_drag(Vector2(2.0, 4.0))
	home._on_camera_zoom(0.5)
	home._physics_process(0.016)
	home._physics_process(0.016) # sin arrastre nuevo: no manda nada

	var looks: Array = []
	for entry in client.inputs:
		if String(entry["type"]) == "touch_camera":
			looks.append(entry["payload"])
	assert_int(looks.size()).is_equal(1)
	assert_float(float(looks[0]["x"])).is_equal(5.0)
	assert_float(float(looks[0]["y"])).is_equal(3.0)
	assert_float(float(looks[0]["zoom"])).is_equal(0.5)

	home.queue_free()

func test_losing_focus_releases_and_resends_what_is_still_held():
	var home = _home_with_dial()
	home._raw_passthrough = false
	var client = home._client()
	Input.action_press("run")
	home._physics_process(0.016)
	client.inputs.clear()

	# Se va el foco: el host suelta todo...
	home._notification(MainLoop.NOTIFICATION_WM_FOCUS_OUT)
	assert_str(String(client.inputs[0]["type"])).is_equal("release_all")
	# ...y lo que siga apretado aca vuelve a viajar, porque alla ya no lo esta.
	home._physics_process(0.016)
	Input.action_release("run")
	assert_array(_acts(client, "run")).is_equal([true])

	home.queue_free()

# --- Sin mouse virtual: el dial se apunta con el stick ---

func test_remote_control_never_attaches_a_virtual_mouse():
	# En un handheld el mouse virtual se activaba con el stick y convertia A/B en clics
	# locales que nunca llegaban al host. Tampoco con el modo HUD abierto.
	var home = _home_with_dial(_dial_screens())
	_open_dial(home)
	assert_object(home.find_node("VirtualMouse", true, false)).is_null()
	assert_object(home.find_node("VirtualMouseLayer", true, false)).is_null()
	home.queue_free()

func test_stick_aims_the_open_radial_without_a_mouse():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true # el Anbernic corre en modo escritorio, sin mouse
	var overlay = _open_dial(home)
	home._client().ui_directives.clear()

	# Stick hacia arriba = la opcion de arriba (screen_a). Con la correccion de ejes del handheld el
	# mismo gesto fisico llega invertido: se prueba el rumbo esperado.
	Input.action_press("move_forward", 1.0)
	_tick(home)
	Input.action_release("move_forward")
	assert_int(overlay._selector.get_hovered_index()).is_equal(1)

	# A (ui_accept) confirma.
	overlay._input(_action("ui_accept"))
	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	home.queue_free()

func test_stick_does_not_aim_the_dial_on_touch():
	# En tactil el joystick virtual sigue caminando: el dial lo apunta el dedo.
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var overlay = _open_dial(home)
	Input.action_press("move_forward", 1.0)
	_tick(home)
	Input.action_release("move_forward")
	assert_int(overlay._selector.get_hovered_index()).is_equal(-1)
	home.queue_free()

# --- Slots como en el host: arriba a la izquierda y tocables en el celular ---

func test_touch_ui_draws_above_the_hud():
	# La UI tactil se dibuja siempre encima de las pantallas del HUD, y el modo HUD encima de los
	# widgets.
	var home = _home_with_dial(_dial_screens())
	var hud_layer: CanvasLayer = home.get_node("HUDLayer")
	var widget_layer: CanvasLayer = home.widget_host.get_widget_root().get_parent() as CanvasLayer
	var touch_ui = load("res://core_v2/ui/MobileUI.tscn").instance()
	assert_int(widget_layer.layer).is_greater(0) # por encima de la escena (titulo, fondo)
	assert_int(widget_layer.layer).is_less(hud_layer.layer)
	assert_int(hud_layer.layer).is_less(touch_ui.layer)
	assert_object(home.get_node_or_null("ExitLayer")).is_null() # sin boton Salir: ESC y back
	touch_ui.free()
	assert_bool(_open_dial(home).get_parent() == hud_layer).is_true()
	home.queue_free()

func test_touch_ui_container_never_eats_gui_taps():
	# Con la UI tactil encima de las pantallas, su Container de pantalla completa (STOP por
	# defecto) se quedaba con el toque: tocar un widget no abria nada. El joystick y los
	# botones leen el toque en _input, no dependen de el.
	var touch_ui = load("res://core_v2/ui/MobileUI.tscn").instance()
	assert_int(touch_ui.get_node("Container").mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	touch_ui.free()

func test_touch_never_grabs_the_pointer():
	# Un clic emulado de un toque no recaptura el mouse (el grab mata el arrastre tactil).
	MobileUIManager._touch_pointer_until = OS.get_ticks_msec() + 1000
	assert_bool(SessionManager._pointer_is_from_touch()).is_true()
	MobileUIManager._touch_pointer_until = 0
	assert_bool(SessionManager._pointer_is_from_touch()).is_false()

# --- Salir de una pantalla tocando fuera, como en el host ---

# Abre una pantalla con vista a resolucion de diseño y la calza, para tener un rect conocido.
func _home_with_open_view(frame_size: Vector2 = Vector2(640.0, 480.0)):
	var home = _home_with_dial([{"id": "holoterminal:cryo", "title": "Criogenia", "relevance": 0.9}])
	home.hud_backend.open_hud_mode(false, "holoterminal:cryo")
	home._on_ui_directive("screen_active", {
		"id": "holoterminal:cryo", "title": "Criogenia", "view": "scene",
		"view_scene": "res://core_v2/ui/hud/HoloTerminalWidget.tscn",
		"view_size": [1280.0, 816.0], "snapshot": {"proto": 1, "id": "holoterminal:cryo"}
	})
	var mount = home.hud_backend.get_overlay()._mount
	mount._view_frame.rect_size = frame_size
	mount.fit_view_2d()
	home._client().ui_directives.clear()
	return home

func _view_rect(home) -> Rect2:
	return home.hud_backend.get_overlay()._view_screen_rect()

func _screen_selects(home) -> Array:
	var ids: Array = []
	for d in home._client().ui_directives:
		if String(d["op"]) == "screen_select":
			ids.append(String(d["payload"]["id"]))
	return ids

func test_tap_outside_the_view_closes_it_on_touch():
	# En tactil no hay TAB: sin esto no habia forma de salir de una pantalla.
	var home = _home_with_open_view()
	var overlay = home.hud_backend.get_overlay()
	var outside: Vector2 = _view_rect(home).end + Vector2(4.0, 4.0)

	overlay._input(_touch(0, outside, true))
	overlay._input(_touch(0, outside, false))

	assert_array(_screen_selects(home)).is_equal([""])
	assert_bool(home._hud_mode_active()).is_false()
	home.queue_free()

func test_dragging_outside_the_view_is_camera_not_close():
	var home = _home_with_open_view()
	var overlay = home.hud_backend.get_overlay()
	var outside: Vector2 = _view_rect(home).end + Vector2(4.0, 4.0)

	overlay._input(_touch(0, outside, true))
	overlay._input(_touch(0, outside + Vector2(60.0, 0.0), false))

	assert_array(_screen_selects(home)).is_empty()
	home.queue_free()

func test_tap_inside_the_view_does_not_close_it():
	var home = _home_with_open_view()
	var overlay = home.hud_backend.get_overlay()
	var inside: Vector2 = _view_rect(home).position + _view_rect(home).size * 0.5

	overlay._input(_touch(0, inside, true))
	overlay._input(_touch(0, inside, false))

	assert_array(_screen_selects(home)).is_empty()
	home.queue_free()

func test_tap_on_a_virtual_control_does_not_close_the_view():
	var joystick := _spawn_virtual_controls()
	# Vista chica arriba: el joystick (abajo a la izquierda) queda fuera de ella, que es el caso
	# que importa. Si cae dentro, la regla "dentro no cierra" ya lo cubre y no probaria nada.
	var home = _home_with_open_view(Vector2(200.0, 150.0))
	var overlay = home.hud_backend.get_overlay()
	var on_joystick: Vector2 = _center_of(joystick)
	assert_bool(_view_rect(home).has_point(on_joystick)).is_false()

	overlay._input(_touch(0, on_joystick, true))
	overlay._input(_touch(0, on_joystick, false))

	assert_array(_screen_selects(home)).is_empty()
	home.queue_free()
	_hide_virtual_controls()

func test_click_outside_closes_the_view():
	var home = _home_with_open_view()
	var overlay = home.hud_backend.get_overlay()
	overlay._input(_click(_view_rect(home).end + Vector2(4.0, 4.0)))
	assert_array(_screen_selects(home)).is_equal([""])
	home.queue_free()

# --- La lista que llega mientras el control sigue en el menu ---

func test_client_keeps_the_last_screen_list_and_active_screen():
	var client = auto_free(load("res://core_v2/net/RemoteControlClient.gd").new())
	client._handle_message({"type": "ui", "op": "screen_list",
		"payload": [{"id": "screen_a", "title": "Screen A", "relevance": 0.9}]})
	client._handle_message({"type": "ui", "op": "screen_active",
		"payload": {"id": "screen_a", "title": "Screen A", "view": "widget", "snapshot": {}}})
	assert_int((client.last_screen_list as Array).size()).is_equal(1)
	assert_str(String(client.last_screen_active["id"])).is_equal("screen_a")

	# Otra partida: no se arrastra la lista de la anterior.
	client.pair_with("127.0.0.1", 1, 2, "test")
	assert_object(client.last_screen_list).is_null()
	assert_object(client.last_screen_active).is_null()

func test_home_shows_the_hud_the_host_sent_before_it_existed():
	# El host manda screen_list pegado al pair_result; el control todavia esta en el menu
	# (change_scene es diferido) y la pantalla del control nunca lo escuchaba. Con el host en
	# pausa no volvia a llegar: el HUD no aparecia.
	var client = get_node("/root/RemoteControlManager").client
	client.last_screen_list = [{"id": "player:flashlight", "title": "Linterna",
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"}]
	client.last_screen_active = null

	var home = RemoteControlHomeScene.instance()
	add_child(home) # sin ningun ui directive entregado a esta pantalla

	assert_bool(home.hud_backend.has_screen("player:flashlight")).is_true()
	var widget = _slot_widget(home, 0)
	assert_object(widget).is_not_null()
	assert_bool(widget is Label).is_false() # el widget de verdad, no el rotulo de reserva

	client.last_screen_list = null
	home.queue_free()

# --- Sin boton Salir: ESC en escritorio, back en Android ---

func test_escape_asks_to_leave_when_no_screen_is_open():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true
	var client = home._client()
	client.inputs.clear()
	var esc := InputEventKey.new()
	esc.scancode = KEY_ESCAPE
	esc.pressed = true

	home._input(esc)

	assert_bool(home.exit_confirm.visible).is_true()
	# Ya no pausa el host: no viaja.
	for entry in client.inputs:
		assert_str(String(entry["type"])).is_not_equal("event")
	home.exit_confirm.hide()
	home.queue_free()

func test_android_back_closes_the_open_screen_first():
	var home = _home_with_open_view()
	# El back de Android llega como accion ui_cancel (PauseManager._send_ui_cancel); el modo HUD lo
	# ve antes que la pantalla del control (esta mas abajo en el arbol).
	home.hud_backend.get_overlay()._input(_action("ui_cancel"))
	assert_array(_screen_selects(home)).is_equal([""])
	assert_bool(home.exit_confirm.visible).is_false()
	home.queue_free()

func test_gamepad_b_is_not_taken_as_leave():
	# B es ui_cancel por defecto, pero en el juego es saltar: tiene que seguir viajando.
	var home = _home_with_dial()
	home._raw_passthrough = true
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_1
	b.pressed = true
	home._input(b)
	assert_bool(home.exit_confirm.visible).is_false()
	home.queue_free()

# --- Cuarto boton: TAB en tactil y gamepad ---

func test_touch_ui_has_a_hud_button_on_the_left_of_the_diamond():
	var touch_ui = load("res://core_v2/ui/MobileUI.tscn").instance()
	var buttons = touch_ui.get_node("Container/ActionButtons")
	var hud = buttons.get_node_or_null("HUDButton")
	assert_object(hud).is_not_null()
	assert_str(hud.action_name).is_equal("hud_mode")
	assert_str(hud.icon.resource_path).is_equal("res://assets/icon_hud.png")
	# Simetrico con Crouch (derecha): el rombo de los botones frontales de un gamepad.
	var crouch = buttons.get_node("CrouchButton")
	assert_float(hud.anchor_left).is_equal_approx(1.0 - crouch.anchor_left, 0.001)
	assert_float(hud.anchor_top).is_equal_approx(crouch.anchor_top, 0.001)
	touch_ui.free()

func test_gamepad_hud_button_is_hud_mode():
	# El boton que eligio project.godot (JOY_BUTTON_3). Mismo evento que TAB.
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_3
	button.pressed = true
	assert_bool(button.is_action_pressed("hud_mode")).is_true()

func test_slots_never_repeat_the_same_screen():
	# Como SuitOS en el host (HudSlots.pin_to): fijar una pantalla en otro slot la mueve.
	var home = _home_with_dial(_dial_screens())
	home.hud_backend.pin_to_slot(1, "screen_a")
	home.hud_backend.pin_to_slot(3, "screen_a")

	assert_array(home.hud_backend.get_pinned_slots()).is_equal(["player:flashlight", "", "", "screen_a"])
	assert_object(_slot_widget(home, 1)).is_null()
	assert_object(_slot_widget(home, 3)).is_not_null()

	home.queue_free()

# --- El boton del HUD como joystick: apoyar, arrastrar para apuntar, soltar para elegir ---

func _hud_button() -> Control:
	_spawn_virtual_controls()
	return MobileUIManager._mobile_ui.get_node("Container/ActionButtons/HUDButton") as Control

func test_hud_button_keeps_tab_held_while_dragging_out_and_reports_the_drag():
	var button := _hud_button()
	var origin: Vector2 = _center_of(button)

	button._input(_touch(7, origin, true))
	assert_bool(Input.is_action_pressed("hud_mode")).is_true()
	# Sale del boton arrastrando: sigue apretado (un boton comun se soltaria aca).
	button._input(_drag(7, origin + Vector2(0.0, -150.0)))
	assert_bool(Input.is_action_pressed("hud_mode")).is_true()
	assert_vector2(button.drag_vector).is_equal(Vector2(0.0, -150.0))

	button._input(_touch(7, origin + Vector2(0.0, -150.0), false))
	assert_bool(Input.is_action_pressed("hud_mode")).is_false()
	assert_vector2(button.drag_vector).is_equal(Vector2.ZERO)
	_hide_virtual_controls()

func test_dragging_the_hud_button_aims_the_dial_and_lifting_picks():
	var button := _hud_button()
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	home._client().ui_directives.clear()
	var origin: Vector2 = _center_of(button)

	# Apoyar y arrastrar hacia arriba: el dial se abre ya (sin esperar el hold) y apunta
	# a la opcion de arriba, screen_a.
	button._input(_touch(7, origin, true))
	_tick(home)
	button._input(_drag(7, origin + Vector2(0.0, -120.0)))
	_tick(home)
	assert_bool(home._radial_is_open()).is_true()
	assert_int(home.hud_backend.get_overlay()._selector.get_hovered_index()).is_equal(1)

	# Soltar el dedo suelta TAB: elige lo marcado.
	button._input(_touch(7, origin + Vector2(0.0, -120.0), false))
	_tick(home)
	assert_bool(home._radial_is_open()).is_false()
	assert_array(_screen_selects(home)).is_equal(["screen_a"])

	home.queue_free()
	_hide_virtual_controls()

func test_widgets_send_no_commands_while_the_host_is_paused():
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.9}])
	home._client().ui_directives.clear()

	home._on_ui_directive("host_paused", {"paused": true})
	home.perform_hud_widget_action("player:flashlight", "toggle")
	assert_array(home._client().ui_directives).is_empty()

	home._on_ui_directive("host_paused", {"paused": false})
	home.perform_hud_widget_action("player:flashlight", "toggle")
	assert_int(home._client().ui_directives.size()).is_equal(1)

	home.queue_free()

func test_only_one_screen_view_at_a_time():
	# Abrir Criogenia (con tamaño de diseño, en su marco) despues de la linterna (widget ampliado)
	# no deja la linterna detras, ni al reves.
	var home = _home_with_flashlight_view()
	home._on_ui_directive("screen_list", [
		{"id": "player:flashlight", "title": "Linterna", "widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"},
		{"id": "holoterminal:cryo", "title": "Criogenia"}])
	var mount = home.hud_backend.get_overlay()._mount
	home.hud_backend.open_hud_mode(false, "holoterminal:cryo")
	home._on_ui_directive("screen_active", {"id": "holoterminal:cryo", "title": "Criogenia",
		"view": "scene", "view_scene": "res://core_v2/ui/hud/HoloTerminalWidget.tscn",
		"view_size": [1280.0, 816.0], "snapshot": {}})
	assert_object(mount._view_frame).is_not_null()
	assert_object(mount.get_widget()).is_null()

	home.hud_backend.open_hud_mode(false, "player:flashlight")
	home._on_ui_directive("screen_active", {"id": "player:flashlight", "title": "Linterna",
		"view": "widget", "view_scene": "", "view_size": [], "snapshot": {}})
	assert_object(mount._view_frame).is_null()
	assert_object(mount.get_widget()).is_not_null()

	home.queue_free()

# --- Hudable sin Pantalla: el widget ampliado en el lugar de una Pantalla ---

func test_radial_has_only_screens_no_close_option():
	var home = _home_with_dial(_dial_screens())
	var overlay = _open_dial(home)
	assert_int(overlay._selector._buttons.size()).is_equal(2)
	for button in overlay._selector._buttons:
		assert_bool(String(button.text).find("Cerrar") == -1).is_true()
	home.queue_free()

func test_single_screen_opens_directly_without_the_radial():
	# Como el modo HUD del host: con una sola pantalla no hay nada que elegir.
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._client().ui_directives.clear()
	_open_dial(home)
	assert_bool(home._radial_is_open()).is_false()
	assert_array(_screen_selects(home)).is_equal(["screen_a"])
	home.queue_free()

# --- El boton de un widget no abre su pantalla ---

func test_tapping_the_button_inside_a_widget_does_not_open_its_screen():
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.9,
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn",
		"snapshot": {"proto": 1, "id": "player:flashlight", "title": "Linterna", "on": false,
			"battery": 90.0, "battery_max": 100.0, "source": "online"}}])
	yield(await_idle_frame(), "completed") # los contenedores del widget reparten tamaños en diferido
	var widget: Control = _slot_widget(home, 0)
	var host = home.widget_host
	var toggle: Control = widget.get_node("Margin/VBox/StatusRow/ToggleButton")
	var xf: Transform2D = toggle.get_global_transform_with_canvas()
	var on_button: Vector2 = xf.origin + toggle.rect_size * xf.get_scale() * 0.5
	home._client().ui_directives.clear()

	# Toque sobre el toggle: en Godot 3 el ScreenTouch sigue subiendo hasta el widget.
	host._input(_touch(0, on_button, true))
	host._on_widget_gui_input(_touch(0, on_button, true), widget, "slot_1")
	host._input(_touch(0, on_button, false))
	host._on_widget_gui_input(_touch(0, on_button, false), widget, "slot_1")
	assert_array(_screen_selects(home)).is_empty()

	# Control: tocar el cuerpo del widget (lejos del boton) si abre su pantalla.
	var wxf: Transform2D = widget.get_global_transform_with_canvas()
	var on_body: Vector2 = wxf.origin + Vector2(4.0, 4.0) * wxf.get_scale()
	host._input(_touch(0, on_body, true))
	host._on_widget_gui_input(_touch(0, on_body, true), widget, "slot_1")
	host._input(_touch(0, on_body, false))
	host._on_widget_gui_input(_touch(0, on_body, false), widget, "slot_1")
	assert_array(_screen_selects(home)).is_equal(["player:flashlight"])

	home.queue_free()

# --- Hints de interactuables tambien en el control ---

func test_hint_from_the_host_shows_on_the_remote_and_clears_on_exit():
	var home = _home_with_dial()
	home._on_ui_directive("hint", {"text": "Abrir compuerta", "mode": "hint"})
	assert_str(PlayerHintManager.get_visible_text()).is_equal("Abrir compuerta")

	home._on_ui_directive("hint", {"text": "", "mode": ""})
	assert_str(PlayerHintManager.get_visible_text()).is_equal("")

	# Uno que llego antes de que existiera la pantalla del control (pegado al emparejamiento).
	var client = get_node("/root/RemoteControlManager").client
	client.last_hint = {"text": "Encender consola", "mode": "status"}
	var late = RemoteControlHomeScene.instance()
	add_child(late)
	assert_str(PlayerHintManager.get_visible_text()).is_equal("Encender consola")
	assert_str(PlayerHintManager.get_visible_mode()).is_equal("status")

	# Al salir del control no queda colgado en el menu.
	remove_child(late)
	assert_str(PlayerHintManager.get_visible_text()).is_equal("")
	late.free()
	client.last_hint = null
	home.queue_free()

# --- Widget en modo pantalla en el control: foco en su boton, gatillo derecho como clic ---

func _home_with_flashlight_view(passthrough: bool = false):
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.9,
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"}])
	home._raw_passthrough = passthrough
	home.hud_backend.open_hud_mode(false, "player:flashlight")
	home._on_ui_directive("screen_active", {"id": "player:flashlight", "title": "Linterna",
		"view": "widget", "view_scene": "", "view_size": [], "snapshot": {}})
	return home

func _joy(button: int, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	return ev

func test_widget_view_focuses_its_button_and_trigger_presses_it_on_gamepad():
	var home = _home_with_flashlight_view(true)
	var toggle: Control = home._widget_view_widget().get_node("Margin/VBox/StatusRow/ToggleButton")
	assert_bool(toggle.has_focus()).is_true()
	var presses := PressCounter.new()
	toggle.connect("pressed", presses, "on_pressed")
	_tick(home)

	# Gatillo derecho (tool_fire_primary en el gamepad): oprime el boton y no dispara en el host.
	Input.action_press("tool_fire_primary")
	_tick(home)
	Input.action_release("tool_fire_primary")
	_tick(home)
	assert_int(presses.count).is_equal(1)
	home._input(_joy(JOY_BUTTON_7, true))
	assert_bool(get_viewport().is_input_handled()).is_true()

	home.queue_free()

func test_widget_view_trigger_on_touch_presses_once_and_keeps_jump_for_the_host():
	var home = _home_with_flashlight_view(false)
	var toggle: Control = home._widget_view_widget().get_node("Margin/VBox/StatusRow/ToggleButton")
	var presses := PressCounter.new()
	toggle.connect("pressed", presses, "on_pressed")
	var client = home._client()
	client.inputs.clear()
	home._widget_view_fire_was_down = false

	Input.action_press("tool_fire_primary")
	Input.action_press("jump")
	_tick(home)
	_tick(home) # sostenido: un solo clic
	Input.action_release("tool_fire_primary")
	Input.action_release("jump")
	_tick(home)

	assert_int(presses.count).is_equal(1)
	assert_array(_acts(client, "tool_fire_primary")).is_empty() # no dispara en el host
	assert_array(_acts(client, "jump")).is_equal([true, false])  # aca el host no esta en pausa

	home.queue_free()

class PressCounter extends Reference:
	var count := 0
	func on_pressed() -> void:
		count += 1

# --- Sin subtitulo ni ayudas: el fondo del gamepad dice el estado de la conexion ---

func test_remote_screen_has_no_subtitle_and_the_radial_no_help_text():
	var home = _home_with_dial(_dial_screens())
	assert_object(home.get_node_or_null("Hint")).is_null()
	var overlay = _open_dial(home)
	# Como el dial del host: sin "Toque fuera para cerrar".
	assert_str(String(overlay._selector.get_node("Status").text)).is_equal("")
	home.queue_free()

func test_gamepad_background_waves_show_the_connection_state():
	var home = _home_with_dial()
	var art = home.get_node_or_null("StatusArt")
	assert_object(art).is_not_null()
	assert_object(art.get_node_or_null("Pad")).is_not_null()
	var waves: TextureRect = art.get_node("Waves")
	# Detras de todo lo demas: justo encima del color de fondo.
	assert_int(art.get_index()).is_equal(home.get_node("Background").get_index() + 1)

	home._client().since_rx_ms = 200
	home._update_status_art(0.016)
	assert_str(home._connection_state()).is_equal("ok")
	assert_bool(waves.modulate.is_equal_approx(home.STATUS_WAVES_OK)).is_true()

	# El pong del latido viene tarde: lag.
	home._client().since_rx_ms = 2000
	home._update_status_art(0.016)
	assert_str(home._connection_state()).is_equal("lag")
	assert_bool(waves.modulate.is_equal_approx(home.STATUS_WAVES_LAG)).is_true()

	# Cortado y reintentando: rojo.
	home._on_connection_lost()
	home._update_status_art(0.3)
	assert_str(home._connection_state()).is_equal("lost")
	assert_float(waves.modulate.r).is_equal_approx(home.STATUS_WAVES_LOST.r, 0.001)
	home._on_connection_restored()
	assert_str(home._connection_state()).is_equal("lag") # vuelve a medir el latido

	home.queue_free()

func test_title_shows_the_suit_system_and_the_map_the_host_is_in():
	var home = _home_with_dial()
	assert_str(home.get_node("Title").text).is_equal("ODISEAOS")
	home._on_ui_directive("location", {"name": "Domo de Entrada"})
	assert_str(home.get_node("Title").text).is_equal("ODISEAOS · DOMO DE ENTRADA")
	# La pausa manda sobre el titulo y al volver queda el mapa.
	home._on_ui_directive("host_paused", {"paused": true})
	home._on_ui_directive("host_paused", {"paused": false})
	assert_str(home.get_node("Title").text).is_equal("ODISEAOS · DOMO DE ENTRADA")
	home.queue_free()

class CameraDragCounter extends Reference:
	var drags := 0
	func on_drag(_delta) -> void:
		drags += 1

# Apoya, arrastra y suelta un dedo en la camara tactil; cuantos camera_drag salieron.
func _camera_drags_for(camera, from: Vector2) -> int:
	var counter := CameraDragCounter.new()
	camera.connect("camera_drag", counter, "on_drag")
	camera._input(_touch(5, from, true))
	camera._input(_drag(5, from + Vector2(60.0, 40.0)))
	camera._input(_drag(5, from + Vector2(120.0, 80.0)))
	camera._input(_touch(5, from + Vector2(120.0, 80.0), false))
	camera.disconnect("camera_drag", counter, "on_drag")
	return counter.drags

func test_dragging_a_widget_or_the_hud_never_moves_the_camera():
	var camera = auto_free(TouchCameraControls.new())
	add_child(camera)
	var home = _home_with_flashlight_view()
	home._exit_hud_mode()
	yield(await_idle_frame(), "completed")
	var widget: Control = _slot_widget(home, 0)
	var xf: Transform2D = widget.get_global_transform_with_canvas()
	# El borde del widget tal como se dibuja (escalado), no su rect sin escala.
	var drawn_corner: Vector2 = xf.origin + widget.rect_size * xf.get_scale() - Vector2(2.0, 2.0)
	assert_int(_camera_drags_for(camera, drawn_corner)).is_equal(0)

	# Con el dial a la vista el dedo es del dial.
	home._on_ui_directive("screen_list", _dial_screens())
	_open_dial(home)
	assert_int(_camera_drags_for(camera, Vector2(500.0, 400.0))).is_equal(0)
	home._exit_hud_mode()
	home.queue_free()
	yield(await_idle_frame(), "completed")
	# Sin HUD ni widget, el mismo gesto vuelve a ser de camara.
	assert_int(_camera_drags_for(camera, Vector2(500.0, 400.0))).is_greater(0)

	# Con una pantalla abierta: sobre ella no es camara; fuera, si.
	var viewing = _home_with_open_view()
	var rect: Rect2 = _view_rect(viewing)
	assert_int(_camera_drags_for(camera, rect.position + rect.size * 0.5)).is_equal(0)
	assert_int(_camera_drags_for(camera, rect.end + Vector2(4.0, 4.0))).is_greater(0)
	viewing.queue_free()
