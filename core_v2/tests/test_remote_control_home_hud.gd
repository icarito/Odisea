extends GdUnitTestSuite

# test_remote_control_home_hud.gd - Tests for RemoteControlHome HUD UI client (FD-296 F4)

var RemoteControlHomeScene = load("res://core_v2/ui/RemoteControlHome.tscn")

func test_remote_home_instantiates_slot_widgets():
	var home = RemoteControlHomeScene.instance()
	add_child(home)

	var screen_list = [
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.2}
	]

	home._on_ui_directive("screen_list", screen_list)

	# Slot A should mount screen_a (highest relevance)
	assert_bool(home._mounted_widgets.has("slot_a")).is_true()
	var widget_a = home._mounted_widgets["slot_a"]
	assert_object(widget_a).is_not_null()
	assert_str(home._get_node_screen_id(widget_a)).is_equal("screen_a")

	home.queue_free()

func test_remote_home_pin_local_screen():
	var home = RemoteControlHomeScene.instance()
	add_child(home)

	var screen_list = [
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.2}
	]

	home._on_ui_directive("screen_list", screen_list)
	home.pin_local_screen("screen_b")

	# Slot B should mount screen_b
	assert_bool(home._mounted_widgets.has("slot_b")).is_true()
	var widget_b = home._mounted_widgets["slot_b"]
	assert_object(widget_b).is_not_null()
	assert_str(home._get_node_screen_id(widget_b)).is_equal("screen_b")

	home.queue_free()

func test_remote_home_fullscreen_view_mounting():
	var home = RemoteControlHomeScene.instance()
	add_child(home)

	var active_payload = {
		"id": "screen_active_1",
		"title": "Active Screen 1",
		"view": "widget",
		"snapshot": {"proto": 1, "id": "screen_active_1", "status_text": "OPERATIONAL"}
	}

	home._on_ui_directive("screen_active", active_payload)

	assert_bool(home.fullscreen_overlay.visible).is_true()
	assert_object(home._fullscreen_view_node).is_not_null()
	assert_str(home._get_node_screen_id(home._fullscreen_view_node)).is_equal("screen_active_1")

	# Sending empty screen_active closes view
	home._on_ui_directive("screen_active", {"id": "", "title": "", "view": "widget", "snapshot": {}})
	assert_bool(home.fullscreen_overlay.visible).is_false()
	assert_object(home._fullscreen_view_node).is_null()

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

class DummyManager extends Node:
	var client: Node = null

const VIEW_SIZE := Vector2(1024.0, 600.0)
const TabGestureScript = preload("res://core_v2/ui/hud/HudTabGesture.gd")

# El dial mide sus opciones contra su propio rect: sin tamaño todas caerian en (0,0) y
# cualquier toque acertaria una. Se fija aca en vez de esperar un frame de layout.
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
	home._radial_selector.rect_size = VIEW_SIZE
	if not screens.empty():
		home._on_ui_directive("screen_list", screens)
	return home

# Dos pantallas: con una sola el dial no se abre (entra directo, como en el host). La de relleno
# va primero, asi screen_a queda en la opcion de arriba (indice 1, las 12) y es la mas relevante.
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

func test_radial_uses_the_same_config_as_the_game_hud():
	var home = _home_with_dial()
	var radial = home._radial_selector

	# Mismos valores que HudModeOverlay.tscn: el dial del control se ve igual que el de
	# la partida (RadialSelectorV2.tscn viene medido para el dial 3D del ascensor).
	assert_vector2(radial.option_size).is_equal(Vector2(400.0, 48.0))
	assert_int((radial.option_font as DynamicFont).size).is_equal(22)
	# Sin estado que mostrar no hay aguja, y el titulo va oculto.
	assert_bool(radial.show_indicator).is_false()
	assert_bool((radial.get_node("Title") as Label).visible).is_false()
	# Y tapa lo de atras.
	assert_object(radial.get_node_or_null("Dim")).is_not_null()

	home.queue_free()

func test_open_radial_hides_what_is_behind():
	var home = _home_with_dial(_dial_screens())
	assert_bool(home.widget_host.visible).is_true()

	home._open_radial()
	assert_bool(home.widget_host.visible).is_false()
	assert_bool(home.fullscreen_overlay.visible).is_false()

	home._close_radial()
	assert_bool(home.widget_host.visible).is_true()

	home.queue_free()

func test_radial_drag_and_release_selects_screen():
	var home = _home_with_dial(_dial_screens())
	home._open_radial()
	assert_bool(home._radial_is_open()).is_true()
	home._client().ui_directives.clear()

	# Arriba es la ultima opcion del arco (la primera queda a las 6): con
	# ["[Cerrar Vista]", "Screen A"] apuntar hacia arriba marca screen_a.
	var start := Vector2(500.0, 400.0)
	home._handle_radial_input(_touch(0, start, true))
	home._handle_radial_input(_drag(0, start + Vector2(0.0, -120.0)))
	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)
	home._handle_radial_input(_touch(0, start + Vector2(0.0, -120.0), false))

	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(sent[0]["op"]).is_equal("screen_select")
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")
	# Elegir cierra el dial: si no, se queda comiendose la entrada.
	assert_bool(home._radial_is_open()).is_false()

	home.queue_free()

func test_radial_tap_on_option_selects_it():
	var home = _home_with_dial(_dial_screens())
	home._open_radial()
	home._client().ui_directives.clear()

	# La etiqueta de screen_a esta arriba del centro; un toque directo sobre ella elige.
	var at: Vector2 = home._radial_selector._buttons[1].get_global_rect().position + Vector2(8.0, 8.0)
	home._handle_radial_input(_touch(0, at, true))
	home._handle_radial_input(_touch(0, at, false))

	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")

	home.queue_free()

func test_radial_tap_outside_closes_without_exit_dialog():
	var home = _home_with_dial(_dial_screens())
	home._open_radial()
	home._client().ui_directives.clear()

	# La esquina no es ninguna opcion: cierra el dial y NADA mas (no la sesion).
	home._handle_radial_input(_touch(0, Vector2(2.0, 2.0), true))
	home._handle_radial_input(_touch(0, Vector2(2.0, 2.0), false))

	assert_bool(home._radial_is_open()).is_false()
	assert_bool(home.exit_confirm.visible).is_false()
	assert_array(home._client().ui_directives).is_empty()

	home.queue_free()

func test_radial_ui_cancel_closes_dial_not_session():
	var home = _home_with_dial(_dial_screens())
	home._open_radial()

	assert_bool(home._handle_radial_input(_action("ui_cancel"))).is_true()
	assert_bool(home._radial_is_open()).is_false()
	assert_bool(home.exit_confirm.visible).is_false()

	home.queue_free()

func test_open_dial_keeps_the_touch_stream_flowing():
	# En tactil los controles virtuales no se apagan nunca: con el dial abierto el
	# joystick sigue manejando al host (el dial solo toma el dedo que apunta).
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	var client = home._client()

	home._open_radial()
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

	home._open_radial()
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

	home._open_radial()

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

	# El snapshot de la lista queda cacheado: es lo que le da nombre y estado al widget.
	var cached: Dictionary = home._snapshots_cache.get("holoterminal:Dome_Intro/HoloTerminal", {})
	assert_str(String(cached.get("title", ""))).is_equal("Terminal del domo")
	assert_bool(bool(cached.get("active", false))).is_true()

	# Y la escena del widget se resuelve por la ruta que mando el host, no por el
	# SuitOS local (que en el control no tiene ninguna pantalla registrada).
	var scene = home._resolve_widget_scene("holoterminal:Dome_Intro/HoloTerminal")
	assert_object(scene).is_not_null()

	var widget = home._mounted_widgets.get("slot_a", null)
	assert_object(widget).is_not_null()
	var title_label = widget.get_node_or_null("Margin/VBox/Header/TitleLabel")
	assert_object(title_label).is_not_null()
	assert_str(title_label.text).is_equal("Terminal del domo")

	home.queue_free()

func test_slot_widget_falls_back_to_title_not_id():
	# Sin snapshot (host viejo o pantalla recien registrada) igual se usa el titulo.
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.5}])

	var widget = home._mounted_widgets.get("slot_a", null)
	assert_object(widget).is_not_null()
	var label = widget.get_node_or_null("TitleLabel")
	assert_object(label).is_not_null()
	assert_str(label.text).contains("Linterna")
	assert_bool(label.text.find("player:flashlight") == -1).is_true()

	home.queue_free()

# Un tap: apretar y soltar entre dos muestras. Un hold: seguir apretado HOLD_TICKS.
func _tab_tap(home) -> void:
	Input.action_press("hud_mode")
	home._step_tab_gesture()
	Input.action_release("hud_mode")
	home._step_tab_gesture()

# Mantiene TAB hasta que sale el HOLD y lo deja apretado: el release es aparte (_tab_release),
# porque soltar tras el hold ya significa algo (elegir o salir).
func _tab_hold(home) -> void:
	Input.action_press("hud_mode")
	for _i in range(TabGestureScript.HOLD_TICKS + 1):
		home._step_tab_gesture()

func _tab_release(home) -> void:
	Input.action_release("hud_mode")
	home._step_tab_gesture()

func test_tab_tap_opens_the_last_screen_and_taps_again_to_close():
	var home = _home_with_dial(_dial_screens())
	home._client().ui_directives.clear()

	# Tap: abre la ultima pantalla (la del slot A si no hay ninguna fijada), sin dial.
	_tab_tap(home)
	assert_bool(home._radial_is_open()).is_false()
	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")

	# Con la pantalla abierta (la confirma el host), otro tap la cierra.
	home._on_ui_directive("screen_active", {"id": "screen_a", "title": "Screen A",
		"view": "widget", "snapshot": {}})
	home._client().ui_directives.clear()
	_tab_tap(home)
	sent = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["payload"]["id"])).is_equal("")

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
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
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
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
	home._handle_radial_input(_click(VIEW_SIZE * 0.5))
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

func test_radial_aims_with_relative_motion_while_mouse_is_captured():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true
	home._open_radial()
	home._client().ui_directives.clear()

	# Con el mouse CAPTURADO (asi se maneja al host) la posicion del evento no se mueve
	# del centro: apuntando por posicion absoluta esto no marcaria ninguna opcion.
	var frozen: Vector2 = VIEW_SIZE * 0.5

	# Un clic sin haber apuntado todavia no cierra el dial: se queda hasta elegir.
	home._handle_radial_input(_click(frozen))
	assert_bool(home._radial_is_open()).is_true()
	assert_array(home._client().ui_directives).is_empty()

	# Arriba es la ultima opcion del arco, o sea screen_a.
	home._handle_radial_input(_motion(frozen, Vector2(0.0, -40.0)))
	home._handle_radial_input(_motion(frozen, Vector2(0.0, -40.0)))
	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)

	home._handle_radial_input(_click(frozen))
	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")
	assert_bool(home._radial_is_open()).is_false()

	home.queue_free()

func test_radial_keeps_every_input_while_open():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true # teclado y mouse: ahi el dial se queda con todo
	home._open_radial()

	# Con el dial abierto ningun evento sigue viaje: ni al host ni a la UI de abajo
	# (boton de salir, joystick tactil).
	var events: Array = [
		_action("jump"),
		_motion(VIEW_SIZE * 0.5, Vector2(3.0, 0.0)),
		_touch(3, Vector2(9.0, 9.0), true),
		_drag(3, Vector2(40.0, 40.0))
	]
	for ev in events:
		assert_bool(home._handle_radial_input(ev)).is_true()
	assert_bool(home._radial_is_open()).is_true()

	home.queue_free()

func test_aim_resets_between_openings():
	var home = _home_with_dial(_dial_screens())
	home._open_radial()
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
	home._close_radial()
	assert_vector2(home._radial_aim).is_equal(Vector2.ZERO)

	# Reabrir no debe heredar el rumbo anterior (marcaria una opcion sin apuntar nada).
	home._open_radial()
	assert_vector2(home._radial_aim).is_equal(Vector2.ZERO)
	assert_int(home._radial_selector.get_hovered_index()).is_equal(-1)

	home.queue_free()

func test_repeated_screen_list_does_not_steal_the_dial_focus():
	# El host reenvia screen_list en cada cambio de widget; el dial abierto no puede
	# perder el marcado por eso (era lo que lo volvia inutilizable).
	var home = _home_with_dial(_dial_screens())
	home._open_radial()
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)

	var label_before = home._radial_selector._buttons[1]
	for _i in range(5):
		home._on_ui_directive("screen_list", [
			{"id": "screen_z", "title": "Screen Z", "relevance": 0.1},
			{"id": "screen_a", "title": "Screen A", "relevance": 0.4,
				"snapshot": {"proto": 1, "id": "screen_a", "battery": 80.0}}])

	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)
	# Y ni se reconstruyeron las Labels.
	assert_bool(home._radial_selector._buttons[1] == label_before).is_true()
	# El snapshot nuevo si entra (la lista sigue alimentando los widgets).
	assert_float(float(home._snapshots_cache["screen_a"].get("battery", 0.0))).is_equal(80.0)

	home.queue_free()

func test_new_screen_in_the_list_does_rebuild_the_dial():
	var home = _home_with_dial(_dial_screens())
	home._update_radial_options()
	assert_int(home._radial_selector._buttons.size()).is_equal(2) # solo pantallas, sin cerrar

	home._on_ui_directive("screen_list", _dial_screens() + [
		{"id": "screen_b", "title": "Screen B", "relevance": 0.1}
	])
	assert_int(home._radial_selector._buttons.size()).is_equal(3)

	home.queue_free()

func test_full_screen_view_mounts_the_scene_the_host_sent():
	var home = _home_with_dial()
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

	assert_object(home._fullscreen_view_node).is_not_null()
	assert_object(home._resolve_view_scene("holoterminal:cryo")).is_not_null()

	# Igual que el host: la UI se dibuja en un Viewport a su resolucion de diseño y lo
	# que se escala es la textura. Escalar el Control lo remuestrea contra el stretch del
	# proyecto y no se ve igual.
	var viewport = home._fullscreen_view_node.get_parent()
	assert_bool(viewport is Viewport).is_true()
	assert_vector2((viewport as Viewport).size).is_equal(Vector2(1280.0, 816.0))
	var container = home._view_viewport_container()
	assert_object(container).is_not_null()
	assert_bool(container.stretch).is_false()

	# Escalado uniforme por el lado que sobra, y centrado.
	container.get_parent().rect_size = Vector2(640.0, 480.0)
	home._fit_view_node()
	assert_vector2(container.rect_scale).is_equal(Vector2(0.5, 0.5))
	assert_vector2(container.rect_position).is_equal(Vector2(0.0, 36.0))

	home.queue_free()

func test_view_without_scene_still_falls_back_to_the_widget():
	# Una pantalla que presta su Viewport en vivo no se puede replicar: queda el widget.
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna",
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"}])
	home._on_ui_directive("screen_active", {
		"id": "player:flashlight", "title": "Linterna", "view": "widget",
		"view_scene": "", "view_size": [], "snapshot": {"proto": 1, "id": "player:flashlight"}
	})

	assert_object(home._fullscreen_view_node).is_not_null()
	assert_str(home._fullscreen_view_node.get_parent().name).is_not_equal("ViewFrame")

	home.queue_free()

func test_widget_button_sends_remote_action_instead_of_calling_local_suitos():
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna",
		"relevance": 0.9, "widget": "res://core_v2/ui/hud/FlashlightWidget.tscn",
		"snapshot": {"proto": 1, "id": "player:flashlight", "title": "Linterna",
			"on": false, "battery": 90.0, "battery_max": 100.0, "source": "online"}}])
	home._client().ui_directives.clear()

	var widget = home._mounted_widgets.get("slot_a", null)
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

func test_slot_widgets_are_placed_in_fixed_rows_without_overlap():
	var home = _home_with_dial([
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.2}
	])
	home.pin_local_screen("screen_b") # el slot B solo se monta con pantalla fijada

	var widget_a = home._mounted_widgets.get("slot_a", null)
	var widget_b = home._mounted_widgets.get("slot_b", null)
	assert_object(widget_a).is_not_null()
	assert_object(widget_b).is_not_null()

	# Filas fijas (como SuitOSWidgetHost en el host): B abajo de A aunque quepa al lado.
	# Pegado al borde en unidades nominales (el WidgetHost esta compensado por render_scale):
	# SLOT_PADDING mas el recorte de pantalla, si lo hay.
	var inset: Vector2 = home._safe_area_inset_nominal()
	var pos_a: Vector2 = (widget_a as Control).rect_position
	var pos_b: Vector2 = (widget_b as Control).rect_position
	assert_float(pos_a.x).is_equal_approx(home.SLOT_PADDING + inset.x, 0.01)
	assert_float(pos_a.y).is_equal_approx(home.SLOT_PADDING + inset.y, 0.01)
	assert_float(pos_b.y).is_equal_approx(pos_a.y + home.SLOT_ROW_HEIGHT + home.SLOT_GAP, 0.01)
	# Con compensacion de escala ningun widget invade la fila del otro.
	assert_float((widget_a as Control).rect_scale.y).is_less_equal(1.0)
	assert_float(pos_b.y).is_greater_equal(pos_a.y + home.SLOT_ROW_HEIGHT * (widget_a as Control).rect_scale.y)

	home.queue_free()

func test_widget_tap_opens_its_screen():
	var home = _home_with_dial(_dial_screens())
	home._client().ui_directives.clear()
	var widget = home._mounted_widgets.get("slot_a", null)
	assert_object(widget).is_not_null()

	# Tap: press + release seguidos (muy por debajo del umbral de hold).
	home._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), true), widget, "slot_a")
	home._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), false), widget, "slot_a")

	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(sent[0]["op"]).is_equal("screen_select")
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")
	# El tap ademas fija la pantalla: el proximo TAB corto la reabre (como en el host).
	assert_str(home._local_pinned_screen_id).is_equal("screen_a")
	assert_bool(home._radial_is_open()).is_false()

	home.queue_free()

func test_widget_hold_opens_the_radial():
	var home = _home_with_dial(_dial_screens())
	var widget = home._mounted_widgets.get("slot_a", null)
	assert_object(widget).is_not_null()

	home._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), true), widget, "slot_a")
	# El hold se mide con el reloj: simular un press que empezo hace 500 ms.
	home._widget_press_msec = OS.get_ticks_msec() - home.WIDGET_HOLD_MSEC - 100
	home._on_widget_gui_input(_touch(0, Vector2(40.0, 20.0), false), widget, "slot_a")

	assert_bool(home._radial_is_open()).is_true()

	home.queue_free()

func test_widget_internal_buttons_stay_clickable():
	# La linterna se enciende desde el widget: sus botones internos conservan la entrada
	# aunque el cuerpo del widget sea el boton de abrir pantalla (a diferencia del host).
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.9,
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"}])

	var widget = home._mounted_widgets.get("slot_a", null)
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
	home._open_radial()

	# El dedo sobre el joystick es del joystick: el dial no lo reclama ni lo consume.
	var on_joystick: Vector2 = _center_of(joystick)
	assert_bool(MobileUIManager.is_point_on_touch_controls(on_joystick)).is_true()
	assert_bool(home._handle_radial_input(_touch(0, on_joystick, true))).is_false()
	assert_bool(home._handle_radial_input(_drag(0, on_joystick + Vector2(40.0, 0.0)))).is_false()
	assert_int(home._radial_touch_index).is_equal(-1)
	# Y soltarlo no cierra el dial (no era un toque fuera de las opciones).
	assert_bool(home._handle_radial_input(_touch(0, on_joystick, false))).is_false()
	assert_bool(home._radial_is_open()).is_true()

	home.queue_free()
	_hide_virtual_controls()

func test_second_finger_aims_while_the_joystick_is_held():
	var joystick := _spawn_virtual_controls()
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	home._open_radial()
	home._client().ui_directives.clear()

	# Dedo 0 caminando en el joystick, dedo 1 eligiendo en el dial: los dos a la vez.
	home._handle_radial_input(_touch(0, _center_of(joystick), true))
	var start := Vector2(600.0, 300.0)
	assert_bool(MobileUIManager.is_point_on_touch_controls(start)).is_false()
	assert_bool(home._handle_radial_input(_touch(1, start, true))).is_true()
	assert_bool(home._handle_radial_input(_drag(1, start + Vector2(0.0, -120.0)))).is_true()
	assert_bool(home._handle_radial_input(_drag(0, _center_of(joystick) + Vector2(30.0, 0.0)))).is_false()
	home._handle_radial_input(_touch(1, start + Vector2(0.0, -120.0), false))

	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")

	home.queue_free()
	_hide_virtual_controls()

func test_emulated_mouse_from_touch_does_not_drive_the_dial():
	# En tactil el mouse que llega es el emulado de los toques: un arrastre del joystick
	# no puede apuntar el dial, ni un toque en un boton confirmarlo.
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	home._open_radial()
	home._client().ui_directives.clear()

	assert_bool(home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -80.0)))).is_false()
	assert_int(home._radial_selector.get_hovered_index()).is_equal(-1)
	assert_bool(home._handle_radial_input(_click(VIEW_SIZE * 0.5))).is_false()
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
	# locales que nunca llegaban al host.
	var home = _home_with_dial()
	assert_object(home.find_node("VirtualMouse", true, false)).is_null()
	assert_object(home.find_node("VirtualMouseLayer", true, false)).is_null()
	home.queue_free()

func test_stick_aims_the_open_radial_without_a_mouse():
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = true # el Anbernic corre en modo escritorio, sin mouse
	home._open_radial()
	home._client().ui_directives.clear()

	# Stick hacia arriba = la ultima opcion del arco (screen_a). Con la correccion de ejes
	# del handheld el mismo gesto fisico llega invertido: se prueba el rumbo esperado.
	var up: String = "move_backward" if InputProviderV2.wants_handheld_axis_inversion() else "move_forward"
	Input.action_press(up, 1.0)
	home._physics_process(0.016)
	Input.action_release(up)
	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)

	# A (ui_accept) confirma.
	home._handle_radial_input(_action("ui_accept"))
	var sent: Array = home._client().ui_directives
	assert_int(sent.size()).is_equal(1)
	assert_str(String(sent[0]["payload"]["id"])).is_equal("screen_a")

	home.queue_free()

func test_stick_does_not_aim_the_dial_on_touch():
	# En tactil el joystick virtual sigue caminando: el dial lo apunta el dedo.
	var home = _home_with_dial(_dial_screens())
	home._raw_passthrough = false
	home._open_radial()
	Input.action_press("move_forward", 1.0)
	home._physics_process(0.016)
	Input.action_release("move_forward")
	assert_int(home._radial_selector.get_hovered_index()).is_equal(-1)
	home.queue_free()

# --- Slots como en el host: arriba a la izquierda y tocables en el celular ---

func test_touch_ui_draws_above_the_hud():
	# La UI tactil se dibuja siempre encima de las pantallas del HUD.
	var home = _home_with_dial()
	var hud_layer: CanvasLayer = home.widget_host.get_parent() as CanvasLayer
	assert_object(hud_layer).is_not_null()
	var touch_ui = load("res://core_v2/ui/MobileUI.tscn").instance()
	assert_int(hud_layer.layer).is_greater(0) # por encima de la escena (titulo, fondo)
	assert_int(hud_layer.layer).is_less(touch_ui.layer)
	assert_object(home.get_node_or_null("ExitLayer")).is_null() # sin boton Salir: ESC y back
	touch_ui.free()
	# La vista y el dial van en la misma capa que los slots.
	assert_bool(home.fullscreen_overlay.get_parent() == hud_layer).is_true()
	assert_bool(home.radial_overlay.get_parent() == hud_layer).is_true()
	home.queue_free()

func test_touch_ui_lets_taps_through_only_while_the_remote_is_open():
	# Con la UI tactil encima, su Container de pantalla completa (STOP) se quedaba con el
	# toque y tocar un widget no abria nada. Se abre paso solo aca y se restaura al salir.
	MobileUIManager._spawn_mobile_ui()
	var container: Control = MobileUIManager._mobile_ui.get_node("Container")
	container.mouse_filter = Control.MOUSE_FILTER_STOP

	var home = RemoteControlHomeScene.instance()
	add_child(home)
	assert_int(container.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

	remove_child(home) # _exit_tree ya, no al final del frame
	assert_int(container.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	home.free()

func test_slot_stays_stuck_to_the_side_when_render_scale_changes_at_runtime():
	var home = _home_with_dial(_dial_screens())
	var widget: Control = home._mounted_widgets["slot_a"]
	var x_before: float = widget.rect_position.x
	var before_scale: float = SettingsManager.render_scale

	# Baja el render en runtime: el compensador reescala el WidgetHost y el slot conserva su
	# posicion nominal pegada al borde (antes el margen en pixeles fijos lo despegaba).
	SettingsManager.render_scale = 0.6
	home.get_node("HUDLayer/WidgetHostScale").apply()
	home._relayout_widgets()
	assert_float(home.widget_host.rect_scale.x).is_equal_approx(0.6, 0.001)
	assert_float(widget.rect_position.x).is_equal_approx(x_before, 0.001)
	assert_float(widget.rect_scale.x).is_less_equal(1.0) # sin k: la escala la pone el host

	SettingsManager.render_scale = before_scale
	home.get_node("HUDLayer/WidgetHostScale").apply()
	home.queue_free()

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
	home._on_ui_directive("screen_active", {
		"id": "holoterminal:cryo", "title": "Criogenia", "view": "scene",
		"view_scene": "res://core_v2/ui/hud/HoloTerminalWidget.tscn",
		"view_size": [1280.0, 816.0], "snapshot": {"proto": 1, "id": "holoterminal:cryo"}
	})
	var container = home._view_viewport_container()
	container.get_parent().rect_size = frame_size
	home._fit_view_node()
	home._client().ui_directives.clear()
	return home

func _screen_selects(home) -> Array:
	var ids: Array = []
	for d in home._client().ui_directives:
		if String(d["op"]) == "screen_select":
			ids.append(String(d["payload"]["id"]))
	return ids

func test_tap_outside_the_view_closes_it_on_touch():
	# En tactil no hay TAB: sin esto no habia forma de salir de una pantalla.
	var home = _home_with_open_view()
	var outside: Vector2 = home._view_screen_rect().end + Vector2(4.0, 4.0)

	home._input(_touch(0, outside, true))
	home._input(_touch(0, outside, false))

	assert_array(_screen_selects(home)).is_equal([""])
	home.queue_free()

func test_dragging_outside_the_view_is_camera_not_close():
	var home = _home_with_open_view()
	var outside: Vector2 = home._view_screen_rect().end + Vector2(4.0, 4.0)

	home._input(_touch(0, outside, true))
	home._input(_touch(0, outside + Vector2(60.0, 0.0), false))

	assert_array(_screen_selects(home)).is_empty()
	home.queue_free()

func test_tap_inside_the_view_does_not_close_it():
	var home = _home_with_open_view()
	var inside: Vector2 = home._view_screen_rect().position + home._view_screen_rect().size * 0.5

	home._input(_touch(0, inside, true))
	home._input(_touch(0, inside, false))

	assert_array(_screen_selects(home)).is_empty()
	home.queue_free()

func test_tap_on_a_virtual_control_does_not_close_the_view():
	var joystick := _spawn_virtual_controls()
	# Vista chica arriba: el joystick (abajo a la izquierda) queda fuera de ella, que es el caso
	# que importa. Si cae dentro, la regla "dentro no cierra" ya lo cubre y no probaria nada.
	var home = _home_with_open_view(Vector2(200.0, 150.0))
	var on_joystick: Vector2 = _center_of(joystick)
	# Control: el joystick de verdad esta fuera de la vista.
	assert_bool(home._view_screen_rect().has_point(on_joystick)).is_false()

	home._input(_touch(0, on_joystick, true))
	home._input(_touch(0, on_joystick, false))

	assert_array(_screen_selects(home)).is_empty()
	home.queue_free()
	_hide_virtual_controls()

func test_click_outside_closes_only_with_the_cursor_released():
	var home = _home_with_open_view()
	home._raw_passthrough = true
	var outside: Vector2 = home._view_screen_rect().end + Vector2(4.0, 4.0)

	# Mouse capturado: su posicion no significa nada (esta congelada), no cierra.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	home._input(_click(outside))
	assert_array(_screen_selects(home)).is_empty()

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	home._input(_click(outside))
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
	client.last_screen_list = [{"id": "screen_a", "title": "Screen A", "relevance": 0.9}]
	client.last_screen_active = null

	var home = RemoteControlHomeScene.instance()
	add_child(home) # sin ningun ui directive entregado a esta pantalla

	assert_bool(home._mounted_widgets.has("slot_a")).is_true()
	assert_str(home._get_node_screen_id(home._mounted_widgets["slot_a"])).is_equal("screen_a")

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
	# El back de Android llega como accion ui_cancel (PauseManager._send_ui_cancel).
	home._input(_action("ui_cancel"))
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

func test_gamepad_left_face_button_is_hud_mode():
	var x := InputEventJoypadButton.new()
	x.button_index = JOY_BUTTON_2
	x.pressed = true
	assert_bool(x.is_action_pressed("hud_mode")).is_true()

func test_slots_never_repeat_the_same_screen():
	# Como SuitOS en el host: la pantalla fijada (B) no compite por el slot A.
	var home = _home_with_dial([
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
		{"id": "screen_b", "title": "Screen B", "relevance": 0.4}
	])
	home.pin_local_screen("screen_a") # la mas relevante, fijada

	assert_str(home._get_node_screen_id(home._mounted_widgets["slot_b"])).is_equal("screen_a")
	assert_str(home._get_node_screen_id(home._mounted_widgets["slot_a"])).is_equal("screen_b")

	# Con una sola pantalla y fijada, el A queda vacio en vez de repetirla.
	home._on_ui_directive("screen_list", [{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	assert_bool(home._mounted_widgets.has("slot_a")).is_false()
	assert_bool(home._mounted_widgets.has("slot_b")).is_true()

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
	# a la ultima opcion del arco, screen_a.
	button._input(_touch(7, origin, true))
	home._physics_process(0.016)
	button._input(_drag(7, origin + Vector2(0.0, -120.0)))
	home._physics_process(0.016)
	assert_bool(home._radial_is_open()).is_true()
	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)

	# Soltar el dedo suelta TAB: elige lo marcado.
	button._input(_touch(7, origin + Vector2(0.0, -120.0), false))
	home._physics_process(0.016)
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
	# Abrir Criogenia (con tamaño de diseño, en su marco) despues de la linterna (widget montado
	# directo) dejaba la linterna dibujada detras.
	var home = _home_with_dial([
		{"id": "player:flashlight", "title": "Linterna", "relevance": 0.5,
			"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"},
		{"id": "holoterminal:cryo", "title": "Criogenia", "relevance": 0.9}
	])
	home._on_ui_directive("screen_active", {"id": "player:flashlight", "title": "Linterna",
		"view": "widget", "view_scene": "", "view_size": [], "snapshot": {}})
	assert_int(home.view_host.get_child_count()).is_equal(1)

	home._on_ui_directive("screen_active", {"id": "holoterminal:cryo", "title": "Criogenia",
		"view": "scene", "view_scene": "res://core_v2/ui/hud/HoloTerminalWidget.tscn",
		"view_size": [1280.0, 816.0], "snapshot": {}})
	assert_int(home.view_host.get_child_count()).is_equal(1)
	assert_str(home.view_host.get_child(0).name).is_equal("ViewFrame")

	# Y al reves: de Criogenia a la linterna tampoco queda el marco.
	home._on_ui_directive("screen_active", {"id": "player:flashlight", "title": "Linterna",
		"view": "widget", "view_scene": "", "view_size": [], "snapshot": {}})
	assert_int(home.view_host.get_child_count()).is_equal(1)
	assert_str(home.view_host.get_child(0).name).is_not_equal("ViewFrame")

	home.queue_free()

# --- Hudable sin Pantalla: el widget ampliado en el lugar de una Pantalla ---

func test_default_screen_design_matches_the_hud_view_presenter():
	# Leido del .tscn sin instanciarlo (es una escena 3D con script).
	var state: SceneState = load("res://core_v2/ui/hud/HudViewPresenter.tscn").get_state()
	var design = null
	for i in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, i) == "screen_resolution":
			design = state.get_node_property_value(0, i)
	assert_object(design).is_not_null()
	assert_vector2(design).is_equal(load("res://core_v2/ui/RemoteControlHome.gd").DEFAULT_SCREEN_DESIGN)

func test_widget_without_screen_uses_the_same_space_as_a_screen():
	var home = _home_with_dial([{"id": "player:flashlight", "title": "Linterna", "relevance": 0.9,
		"widget": "res://core_v2/ui/hud/FlashlightWidget.tscn"}])
	home._on_ui_directive("screen_active", {"id": "player:flashlight", "title": "Linterna",
		"view": "widget", "view_scene": "", "view_size": [], "snapshot": {}})
	var frame: Control = home._widget_placeholder_frame()
	assert_object(frame).is_not_null()
	frame.rect_size = Vector2(640.0, 480.0)
	home._fit_widget_placeholder()

	# Una Pantalla de 1280x816 en 640x480 ocupa 640x408 centrada: ese es el lugar del widget.
	var space: Rect2 = home._screen_space_in(frame.rect_size)
	assert_vector2(space.size).is_equal(Vector2(640.0, 408.0))
	var widget: Control = home._fullscreen_view_node
	var drawn := Rect2(widget.rect_position, widget.rect_size * widget.rect_scale)
	# Ampliado uniforme (sin estirar), adentro de ese lugar y tocando dos de sus bordes.
	assert_float(widget.rect_scale.x).is_equal_approx(widget.rect_scale.y, 0.001)
	assert_bool(space.grow(0.5).encloses(drawn)).is_true()
	var fills_width: bool = abs(drawn.size.x - space.size.x) < 0.5
	var fills_height: bool = abs(drawn.size.y - space.size.y) < 0.5
	assert_bool(fills_width or fills_height).is_true()
	# Y no a pantalla completa: tocar fuera de ese lugar cierra, como con una Pantalla.
	assert_vector2(home._view_screen_rect().size).is_equal(space.size)

	home.queue_free()

func test_radial_has_only_screens_no_close_option():
	var home = _home_with_dial(_dial_screens())
	home._open_radial()
	assert_int(home._radial_selector._buttons.size()).is_equal(2)
	for button in home._radial_selector._buttons:
		assert_bool(String(button.text).find("Cerrar") == -1).is_true()
	home.queue_free()

func test_single_screen_opens_directly_without_the_radial():
	# Como el modo HUD del host: con una sola pantalla no hay nada que elegir.
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._client().ui_directives.clear()
	home._open_radial()
	assert_bool(home._radial_is_open()).is_false()
	assert_array(_screen_selects(home)).is_equal(["screen_a"])
	home.queue_free()
