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

	func send_input_data(payload: Dictionary) -> void:
		inputs.append({"type": "input_data", "payload": payload})

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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	assert_bool(home.widget_host.visible).is_true()

	home._open_radial()
	assert_bool(home.widget_host.visible).is_false()
	assert_bool(home.fullscreen_overlay.visible).is_false()

	home._close_radial()
	assert_bool(home.widget_host.visible).is_true()

	home.queue_free()

func test_radial_drag_and_release_selects_screen():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._open_radial()

	assert_bool(home._handle_radial_input(_action("ui_cancel"))).is_true()
	assert_bool(home._radial_is_open()).is_false()
	assert_bool(home.exit_confirm.visible).is_false()

	home.queue_free()

func test_open_dial_suspends_input_forwarding():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._raw_passthrough = false # el celu: se reenvia InputDataV2 por tick
	var client = home._client()

	client.inputs.clear()
	home._physics_process(0.016)
	assert_int(client.inputs.size()).is_equal(1) # control: con el dial cerrado si manda

	home._open_radial()
	client.inputs.clear()
	home._physics_process(0.016)
	assert_array(client.inputs).is_empty()

	home.queue_free()

func test_open_dial_releases_held_input_on_passthrough():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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

func _tab_hold(home) -> void:
	Input.action_press("hud_mode")
	for _i in range(TabGestureScript.HOLD_TICKS + 1):
		home._step_tab_gesture()
	Input.action_release("hud_mode")
	home._step_tab_gesture()

func test_tab_tap_opens_the_last_screen_and_taps_again_to_close():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._client().ui_directives.clear()

	_tab_hold(home)

	# El hold saca el dial, y no eligio ninguna pantalla por su cuenta.
	assert_bool(home._radial_is_open()).is_true()
	assert_array(home._client().ui_directives).is_empty()

	home.queue_free()

func test_tab_is_never_forwarded_to_the_host():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._raw_passthrough = true
	var client = home._client()
	client.inputs.clear()

	# Ni el press ni el release: alla abriria el modo HUD del host.
	home._input(_action("hud_mode"))
	home._unhandled_input(_action("hud_mode"))
	for entry in client.inputs:
		assert_str(String(entry["type"])).is_not_equal("event")

	home.queue_free()

# Hermano del anterior para el OTRO camino: en tactil/gamepad el boton no viaja como
# evento sino como campo del InputDataV2 que se manda por tick, asi que comerse el evento
# en _input no alcanza.
func test_hud_button_is_never_forwarded_in_the_input_stream():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._raw_passthrough = false # el celu: se reenvia InputDataV2 por tick
	# Proveedor en REPLAY con el boton apretado: el real lee el Input del proceso de test,
	# donde hud_mode sale false y el test pasaria igual con el bug puesto.
	var provider := InputProviderV2.new()
	provider.mode = InputProviderV2.Mode.REPLAY
	provider.playback_buffer = [{"hud_mode": true, "jump": true}]
	home._input_provider = provider
	var client = home._client()
	client.inputs.clear()

	home._physics_process(0.016)

	assert_int(client.inputs.size()).is_equal(1)
	var payload: Dictionary = client.inputs[0]["payload"]
	assert_bool(bool(payload["hud_mode"])).is_false()
	# Y el resto del stream sigue viajando: no se vacia el payload, se apaga un campo.
	assert_bool(bool(payload["jump"])).is_true()

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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
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
	var screens: Array = [{"id": "screen_a", "title": "Screen A", "relevance": 0.9}]
	var home = _home_with_dial(screens)
	home._open_radial()
	home._handle_radial_input(_motion(VIEW_SIZE * 0.5, Vector2(0.0, -40.0)))
	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)

	var label_before = home._radial_selector._buttons[1]
	for _i in range(5):
		home._on_ui_directive("screen_list", [{"id": "screen_a", "title": "Screen A",
			"relevance": 0.4, "snapshot": {"proto": 1, "id": "screen_a", "battery": 80.0}}])

	assert_int(home._radial_selector.get_hovered_index()).is_equal(1)
	# Y ni se reconstruyeron las Labels.
	assert_bool(home._radial_selector._buttons[1] == label_before).is_true()
	# El snapshot nuevo si entra (la lista sigue alimentando los widgets).
	assert_float(float(home._snapshots_cache["screen_a"].get("battery", 0.0))).is_equal(80.0)

	home.queue_free()

func test_new_screen_in_the_list_does_rebuild_the_dial():
	var home = _home_with_dial([{"id": "screen_a", "title": "Screen A", "relevance": 0.9}])
	home._open_radial()
	assert_int(home._radial_selector._buttons.size()).is_equal(2) # [Cerrar Vista] + A

	home._on_ui_directive("screen_list", [
		{"id": "screen_a", "title": "Screen A", "relevance": 0.9},
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
