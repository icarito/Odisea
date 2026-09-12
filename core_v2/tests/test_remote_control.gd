extends GdUnitTestSuite

# test_remote_control.gd - GDScript unit test suite for ODISEA Remote Control v1 subsystem.

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var RemoteDiscovery = load("res://core_v2/net/RemoteDiscovery.gd")
var RemoteControlServer = load("res://core_v2/net/RemoteControlServer.gd")
var RemoteControlClient = load("res://core_v2/net/RemoteControlClient.gd")
var RemoteControlManager = load("res://core_v2/net/RemoteControlManager.gd")
var RemotePairingDialogScene = load("res://core_v2/ui/RemotePairingDialog.tscn")
var RemoteControlHomeScene = load("res://core_v2/ui/RemoteControlHome.tscn")
var RemoteControlMenuScene = load("res://core_v2/ui/RemoteControlMenu.tscn")

func test_protocol_serialize_and_parse():
	var announce = RemoteProtocol.create_announce_payload("Test Session", "v0.4.0", 10443, 10444)
	assert_bool(RemoteProtocol.is_valid_announce(announce)).is_true()

	var encoded = RemoteProtocol.encode_json(announce)
	var decoded = RemoteProtocol.decode_json(encoded)
	assert_str(decoded.get("session_name", "")).is_equal("Test Session")
	assert_str(decoded.get("version", "")).is_equal("v0.4.0")
	assert_int(int(decoded.get("ws_port", 0))).is_equal(10443)

func test_pair_request_and_result_messages():
	var req = RemoteProtocol.create_pair_request("Phone 1")
	assert_str(req.get("type", "")).is_equal("pair_request")
	assert_str(req.get("device_name", "")).is_equal("Phone 1")

	var pair_pin = RemoteProtocol.create_pair_pin("654321")
	assert_str(pair_pin.get("type", "")).is_equal("pair_pin")
	assert_str(pair_pin.get("pin", "")).is_equal("654321")

	var res_ok = RemoteProtocol.create_pair_result(true, "token_abc_123")
	assert_bool(bool(res_ok.get("ok", false))).is_true()
	assert_str(res_ok.get("token", "")).is_equal("token_abc_123")

	var res_fail = RemoteProtocol.create_pair_result(false, "", "PIN incorrecto")
	assert_bool(bool(res_fail.get("ok", true))).is_false()
	assert_str(res_fail.get("reason", "")).is_equal("PIN incorrecto")

func test_ui_and_input_messages():
	var ui_msg = RemoteProtocol.create_ui_message("prompt", {"text": "Aceptar transmisión?"})
	assert_str(ui_msg.get("type", "")).is_equal("ui")
	assert_str(ui_msg.get("op", "")).is_equal("prompt")

	var touch_input = RemoteProtocol.create_input_message("touch", {"x": 100, "y": 200}, "my_token")
	assert_str(touch_input.get("type", "")).is_equal("input")
	assert_str(touch_input.get("input_type", "")).is_equal("touch")
	assert_str(touch_input.get("token", "")).is_equal("my_token")

func test_discovery_session_stale_cleanup():
	var discovery = RemoteDiscovery.new()
	discovery.stasis_timeout = 0.1 # 100 ms timeout for test
	add_child(discovery)

	var mock_dict = RemoteProtocol.create_announce_payload("Stale Session", "v0.4.0", 10443, 10444)
	discovery.discovered_sessions["127.0.0.1:10443"] = {
		"key": "127.0.0.1:10443",
		"ip": "127.0.0.1",
		"session_name": "Stale Session",
		"version": "v0.4.0",
		"ws_port": 10443,
		"sensor_port": 10444,
		"last_seen": OS.get_system_time_msecs() - 500 # 500 ms ago -> stale
	}

	assert_int(discovery.discovered_sessions.size()).is_equal(1)
	discovery._cleanup_stale_sessions(0.1)
	assert_int(discovery.discovered_sessions.size()).is_equal(0)

	discovery.queue_free()

func test_server_pin_generation():
	var server = RemoteControlServer.new()
	add_child(server)

	var pin1 = server.generate_pin()
	var pin2 = server.generate_pin()

	assert_int(pin1.length()).is_equal(6)
	assert_int(pin2.length()).is_equal(6)
	assert_bool(pin1.is_valid_integer()).is_true()
	assert_bool(pin2.is_valid_integer()).is_true()

	server.queue_free()

func test_hosting_is_limited_to_gameplay_scenes():
	var manager = RemoteControlManager.new()
	assert_bool(manager._is_gameplay_scene("res://scenes/Menu.tscn")).is_false()
	assert_bool(manager._is_gameplay_scene("res://core_v2/bootstrap/Boot.tscn")).is_false()
	assert_bool(manager._is_gameplay_scene("res://core_v2/ui/RemoteControlHome.tscn")).is_false()
	assert_bool(manager._is_gameplay_scene("res://core_v2/levels/interiors/Dome_Intro.tscn")).is_true()
	manager.free()

func test_pairing_popup_hide_waits_for_confirmation():
	var dialog = RemotePairingDialogScene.instance()
	add_child(dialog)
	dialog._active = true
	dialog._on_popup_hide()
	assert_bool(dialog._active).is_true()
	dialog._finish(false)
	dialog.queue_free()

func test_remote_home_scene_loads():
	var home = RemoteControlHomeScene.instance()
	assert_object(home).is_not_null()
	home.free()

func test_anbernic_remote_inverts_stick_axes_before_sending():
	var previous: String = OS.get_environment("ODISEA_DEVICE")
	OS.set_environment("ODISEA_DEVICE", "anbernic")
	var home = RemoteControlHomeScene.instance()
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_2
	motion.axis_value = 0.75
	var corrected: InputEventJoypadMotion = home._event_for_host(motion)
	assert_float(corrected.axis_value).is_equal(-0.75)
	assert_float(motion.axis_value).is_equal(0.75)
	assert_float(RemoteProtocol.encode_event(corrected, Vector2(640, 480))["v"]).is_equal(-0.75)
	home.free()
	OS.set_environment("ODISEA_DEVICE", previous)

func test_discovered_hosts_are_large_buttons():
	var menu = RemoteControlMenuScene.instance()
	add_child(menu)
	var sessions = {
		"a": {"session_name": "ODISEA-DESKTOP", "version": "v0.4.0", "os": "Linux"},
		"b": {"session_name": "ODISEA-TABLET", "version": "v0.4.0"}
	}
	menu._on_sessions_updated(sessions)
	# Dos actualizaciones en el mismo frame no deben dejar los botones viejos colgados.
	menu._on_sessions_updated(sessions)
	assert_bool(menu.sessions_scroll.visible).is_true()
	assert_int(menu.hosts.get_child_count()).is_equal(2)
	assert_str(menu.hosts.get_child(0).text).contains("ODISEA-")
	assert_str(menu._session_title(sessions["a"])).is_equal("ODISEA-DESKTOP\nLinux · Odisea v0.4.0")
	assert_str(menu._session_title(sessions["b"])).is_equal("ODISEA-TABLET\nOdisea v0.4.0")
	menu.queue_free()

func test_discovery_lists_each_host_once():
	var discovery = RemoteDiscovery.new()
	var announce = RemoteProtocol.create_announce_payload("pc", "v0.4.0", 10443, 10444, "abc123", "Linux")
	# Mismo host oido por dos interfaces: una sola sesion, con la ultima IP.
	assert_bool(discovery._register_announce("192.168.1.10", announce)).is_true()
	assert_bool(discovery._register_announce("10.0.0.5", announce)).is_true()
	assert_int(discovery.discovered_sessions.size()).is_equal(1)
	assert_str(discovery.discovered_sessions["abc123"]["ip"]).is_equal("10.0.0.5")
	assert_str(discovery.discovered_sessions["abc123"]["os"]).is_equal("Linux")
	# Sin IP de origen no hay a donde conectar: no se lista.
	assert_bool(discovery._register_announce("", announce)).is_false()
	discovery.free()

var _pair_results: Array = []

func _on_pair_result(ok: bool, reason: String) -> void:
	_pair_results.append([ok, reason])

func _make_pairing_client() -> Node:
	var client = RemoteControlClient.new()
	add_child(client)
	_pair_results.clear()
	client.connect("pair_result_received", self, "_on_pair_result")
	return client

func test_pairing_fails_with_reason_when_host_silent():
	var client = _make_pairing_client()
	# Sin conexion: queda pendiente (se enviaria al conectar) en vez de perderse.
	client.request_pairing()
	assert_bool(client._pairing_pending).is_true()
	client._process(client.pairing_response_timeout - 1.0)
	assert_int(_pair_results.size()).is_equal(0)
	client._process(2.0)
	assert_int(_pair_results.size()).is_equal(1)
	assert_bool(_pair_results[0][0]).is_false()
	assert_str(_pair_results[0][1]).contains("no responde")
	assert_bool(client._pairing_pending).is_false()
	client.queue_free()

func test_pairing_waits_for_host_decision_after_pin():
	var client = _make_pairing_client()
	client.request_pairing()
	client._handle_message({"type": "pair_pin", "pin": "123456"})
	# Con el PIN en pantalla del host rige el plazo largo, no el de respuesta.
	client._process(client.pairing_response_timeout + 1.0)
	assert_int(_pair_results.size()).is_equal(0)
	client._process(client.pairing_decision_timeout)
	assert_int(_pair_results.size()).is_equal(1)
	assert_str(_pair_results[0][1]).contains("dejó de responder")
	client.queue_free()

func test_pairing_result_from_host_ends_attempt():
	var client = _make_pairing_client()
	client.request_pairing()
	client._handle_message({"type": "pair_pin", "pin": "123456"})
	client._handle_message({"type": "pair_result", "ok": true, "token": "tok"})
	assert_bool(client._pairing_pending).is_false()
	assert_bool(client._is_paired).is_true()
	assert_bool(_pair_results[0][0]).is_true()
	client._process(client.pairing_decision_timeout + 1.0)
	assert_int(_pair_results.size()).is_equal(1)
	client.queue_free()

var _session_end_reasons: Array = []
var _lost: int = 0
var _restored: int = 0

func _on_session_ended(reason: String) -> void:
	_session_end_reasons.append(reason)

func _on_lost() -> void:
	_lost += 1

func _on_restored() -> void:
	_restored += 1

func _make_paired_client() -> Node:
	var client = _make_pairing_client()
	_session_end_reasons.clear()
	_lost = 0
	_restored = 0
	client.connect("session_ended", self, "_on_session_ended")
	client.connect("connection_lost", self, "_on_lost")
	client.connect("connection_restored", self, "_on_restored")
	client._auto_reconnect = true
	client.request_pairing()
	client._handle_message({"type": "pair_result", "ok": true, "token": "tok"})
	return client

func test_host_session_end_closes_control_at_once():
	var client = _make_paired_client()
	client._handle_message({"type": "session_end"})
	assert_array(_session_end_reasons).has_size(1)
	assert_str(_session_end_reasons[0]).contains("cerró la partida")
	assert_bool(client._is_reconnecting).is_false()
	assert_int(_lost).is_equal(0)
	client.queue_free()

func test_drop_without_notice_retries_and_resumes():
	var client = _make_paired_client()
	# Corte sin session_end (wifi): no termina, reintenta con el token.
	client._on_ws_closed(false)
	assert_int(_lost).is_equal(1)
	assert_array(_session_end_reasons).is_empty()
	assert_bool(client._is_reconnecting).is_true()
	assert_bool(client.is_resuming()).is_true()
	# Otro cierre durante el reintento no vuelve a avisar.
	client._on_ws_error()
	assert_int(_lost).is_equal(1)
	# El host acepta el token: la sesion sigue.
	client._handle_message({"type": "pair_result", "ok": true, "token": "tok"})
	assert_int(_restored).is_equal(1)
	assert_bool(client._is_paired).is_true()
	assert_bool(client.is_resuming()).is_false()
	client.queue_free()

func test_drop_without_notice_gives_up_after_resume_timeout():
	var client = _make_paired_client()
	client._on_ws_closed(false)
	client._process(client.session_resume_timeout - 1.0)
	assert_array(_session_end_reasons).is_empty()
	assert_float(client.get_resume_time_left()).is_less_equal(1.0)
	client._process(2.0)
	assert_array(_session_end_reasons).has_size(1)
	assert_str(_session_end_reasons[0]).contains("No se pudo recuperar")
	assert_bool(client._is_reconnecting).is_false()
	client.queue_free()

func test_session_lost_by_timeout_resumes_when_host_returns():
	var client = _make_paired_client()
	client._host_id = "h1"
	client._on_ws_closed(false)
	client._process(client.session_resume_timeout + 1.0)
	assert_array(_session_end_reasons).has_size(1)
	# Nadie cerro la sesion: el mismo host (y solo ese) la puede retomar.
	assert_bool(client.can_resume({"key": "h1"})).is_true()
	assert_bool(client.can_resume({"key": "otro"})).is_false()
	# Cerrar el panel del control remoto no la olvida.
	client.cancel_pairing()
	assert_bool(client.can_resume({"key": "h1"})).is_true()
	client.resume_session({"key": "h1", "ip": "127.0.0.1", "ws_port": 1, "sensor_port": 2})
	assert_bool(client.is_resuming()).is_true()
	assert_str(client._session_token).is_equal("tok")
	client._handle_resume_result(true)
	assert_int(_restored).is_equal(1)
	assert_bool(client._is_paired).is_true()
	client.disconnect_from_host()
	client.queue_free()

func test_closed_or_abandoned_sessions_are_not_resumed():
	var client = _make_paired_client()
	client._host_id = "h1"
	client._handle_message({"type": "session_end"})
	assert_bool(client.can_resume({"key": "h1"})).is_false()
	var other = _make_paired_client()
	other._host_id = "h1"
	other._on_ws_closed(false)
	other._process(other.session_resume_timeout + 1.0)
	# El jugador sale a proposito del control: no vuelve solo despues.
	other.disconnect_from_host()
	assert_bool(other.can_resume({"key": "h1"})).is_false()
	client.queue_free()
	other.queue_free()

func test_menu_resumes_lost_session_when_host_reappears():
	var rcm = get_node_or_null("/root/RemoteControlManager")
	if rcm == null:
		return
	var menu = load("res://scenes/Menu.tscn").instance()
	add_child(menu)
	rcm.client._resumable_token = "tok"
	rcm.client._host_id = "h1"
	menu._on_remote_sessions_updated({"h1": {"key": "h1", "ip": "127.0.0.1", "ws_port": 1, "sensor_port": 2}})
	assert_bool(rcm.client.is_resuming()).is_true()
	rcm.client.disconnect_from_host()
	menu.queue_free()

func test_host_pause_is_remembered_by_client():
	var client = _make_paired_client()
	client._handle_message({"type": "ui", "op": "host_paused", "payload": {"paused": true}})
	assert_bool(client.host_paused).is_true()
	client._handle_message({"type": "ui", "op": "host_paused", "payload": {"paused": false}})
	assert_bool(client.host_paused).is_false()
	client.queue_free()

func test_silent_host_is_detected_by_heartbeat():
	var client = _make_paired_client()
	client._is_connected = true
	client._last_rx_msec = OS.get_ticks_msec() - int(client.heartbeat_timeout * 1000.0) - 1000
	client._process(0.01)
	assert_int(_lost).is_equal(1)
	assert_bool(client.is_resuming()).is_true()
	client.queue_free()

var _stalled: int = 0

func _on_stalled(_device_name: String) -> void:
	_stalled += 1

func test_server_flags_silent_control_once():
	var server = RemoteControlServer.new()
	add_child(server)
	_stalled = 0
	server.connect("client_stalled", self, "_on_stalled")
	var old: int = OS.get_ticks_msec() - int(server.client_stall_timeout * 1000.0) - 1000
	server._peers[1] = {"device_name": "pc", "paired": true, "token": "tok", "last_rx": old, "stalled": false}
	server._peers[2] = {"device_name": "sin emparejar", "paired": false, "token": "", "last_rx": old, "stalled": false}
	server._check_stalled_peers()
	server._check_stalled_peers()
	# Solo el emparejado, y una sola vez hasta que vuelva a hablar.
	assert_int(_stalled).is_equal(1)
	server.queue_free()

func test_server_knows_when_a_client_is_paired():
	var server = RemoteControlServer.new()
	server._peers[1] = {"paired": false}
	assert_bool(server.has_paired_client()).is_false()
	server._peers[2] = {"paired": true}
	assert_bool(server.has_paired_client()).is_true()
	server.free()

func test_server_throttles_idle_polling_but_not_a_connected_peer():
	var server = RemoteControlServer.new()
	server.idle_poll_interval = 0.05
	assert_bool(server._should_poll(0.04)).is_false()
	assert_bool(server._should_poll(0.01)).is_true()
	assert_bool(server._should_poll(0.0)).is_false()
	server._peers[1] = {"paired": false}
	assert_bool(server._should_poll(0.0)).is_true()
	server.free()

func test_server_resumes_only_the_active_token():
	var server = RemoteControlServer.new()
	add_child(server)
	server._active_token = "tok"
	server._peers[1] = {"device_name": "old", "paired": true, "token": "tok"}
	server._peers[2] = {"device_name": "pc", "paired": false, "token": ""}
	server._peers[3] = {"device_name": "otro", "paired": false, "token": ""}
	server._handle_resume(2, {"token": "tok"})
	assert_bool(server._peers[2]["paired"]).is_true()
	# La conexion vieja del mismo token se descarta.
	assert_bool(server._peers.has(1)).is_false()
	server._handle_resume(3, {"token": "otro-token"})
	assert_bool(server._peers[3]["paired"]).is_false()
	server.queue_free()

func test_menu_remote_button_lights_up_with_a_host():
	var menu = load("res://scenes/Menu.tscn").instance()
	add_child(menu)
	var button: Button = menu.remote_control_button
	var gold: StyleBoxFlat = menu._remote_styles["normal"][0]
	var gray: StyleBoxFlat = menu._remote_styles["normal"][1]
	assert_float(gray.bg_color.r).is_equal(gray.bg_color.g)
	assert_float(gray.bg_color.g).is_equal(gray.bg_color.b)

	menu._on_remote_sessions_updated({})
	assert_object(button.get_stylebox("normal")).is_same(gray)
	assert_bool(button.disabled).is_false()

	menu._on_remote_sessions_updated({"h": {"session_name": "pc"}})
	assert_object(button.get_stylebox("normal")).is_same(gold)

	menu._on_remote_sessions_updated({})
	assert_object(button.get_stylebox("normal")).is_same(gray)
	menu.queue_free()

func test_device_label_names_os():
	assert_str(RemoteProtocol.device_label()).contains(RemoteProtocol.os_label())

func test_single_session_pairs_without_selection():
	var menu = RemoteControlMenuScene.instance()
	add_child(menu)
	# Sin "ip" _on_pair_pressed corta antes de tocar la red.
	menu._on_sessions_updated({"host": {"session_name": "ODISEA-DESKTOP", "version": "v0.4.0"}})
	assert_bool(menu.sessions_scroll.visible).is_false()
	assert_int(menu.hosts.get_child_count()).is_equal(0)
	assert_str(menu._attempted_key).is_equal("host")
	# Antes de conectar, confirmacion en el cliente.
	assert_bool(menu.connect_confirm.visible).is_true()
	assert_str(menu.connect_confirm.dialog_text).contains("ODISEA-DESKTOP")
	assert_float(menu.connect_confirm.get_ok().rect_min_size.y).is_greater_equal(44.0)
	# Otro anuncio de la misma partida no vuelve a preguntar.
	menu.connect_confirm.hide()
	menu._awaiting_confirm = true
	menu._on_sessions_updated({"host": {"session_name": "ODISEA-DESKTOP", "version": "v0.4.0"}})
	menu._on_connect_confirmed()
	assert_bool(menu.connect_confirm.visible).is_false()
	assert_str(menu.status_label.text).contains("Conectando con ODISEA-DESKTOP")
	menu.queue_free()

func test_no_sessions_explains_same_wifi():
	var menu = RemoteControlMenuScene.instance()
	add_child(menu)
	menu._on_sessions_updated({})
	assert_bool(menu.sessions_scroll.visible).is_false()
	assert_str(menu.status_label.text).contains("misma red wifi")
	menu.queue_free()

func test_raw_event_roundtrip_keeps_modifiers():
	var key := InputEventKey.new()
	key.physical_scancode = KEY_SHIFT
	key.pressed = true
	key.shift = true
	var wire = RemoteProtocol.decode_json(RemoteProtocol.encode_json(RemoteProtocol.encode_event(key, Vector2(800, 600))))
	var back = RemoteProtocol.decode_event(wire, Vector2(1600, 900))
	assert_bool(back is InputEventKey).is_true()
	assert_int(back.physical_scancode).is_equal(KEY_SHIFT)
	assert_bool(back.pressed).is_true()
	assert_bool(back.shift).is_true()
	assert_bool(back.is_action_pressed("run")).is_true()

	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(400, 300)
	var mb = RemoteProtocol.decode_event(RemoteProtocol.encode_event(click, Vector2(800, 600)), Vector2(1600, 900))
	assert_vector2(mb.position).is_equal(Vector2(800, 450))
	assert_bool(mb.is_action_pressed("ui_cancel")).is_true()

	assert_object(RemoteProtocol.decode_event({"k": "Object(Node)"}, Vector2(800, 600))).is_null()
	assert_bool(RemoteProtocol.encode_event(InputEventMouseMotion.new(), Vector2(800, 600)).empty()).is_true()

# --- Un solo protocolo: acciones como eventos ---

func test_action_event_roundtrip_keeps_strength():
	var ev := InputEventAction.new()
	ev.action = "move_forward"
	ev.pressed = true
	ev.strength = 0.62
	var wire = RemoteProtocol.decode_json(RemoteProtocol.encode_json(RemoteProtocol.encode_event(ev, Vector2(800, 600))))
	var back = RemoteProtocol.decode_event(wire, Vector2(1600, 900))
	assert_bool(back is InputEventAction).is_true()
	assert_str(back.action).is_equal("move_forward")
	assert_bool(back.pressed).is_true()
	assert_float(back.strength).is_equal_approx(0.62, 0.001)

func test_hud_mode_and_unknown_actions_never_travel():
	# El HUD es de cada dispositivo; y un peer no inventa acciones que no estan en el InputMap.
	for action in ["hud_mode", "no_existe"]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		assert_bool(RemoteProtocol.encode_event(ev, Vector2(800, 600)).empty()).is_true()
		assert_object(RemoteProtocol.decode_event({"k": "act", "a": action, "p": true}, Vector2(800, 600))).is_null()

func test_host_keeps_a_remote_action_held_until_its_release():
	# El corazon del arreglo: el estado vive en el Input del host. Antes el tactil mandaba
	# una foto por tick y un tick sin foto soltaba crouch/sprint (flancos falsos y caida de
	# velocidad); ahora queda sostenido hasta que llega el contrario, como una tecla.
	var mgr = auto_free(RemoteControlManager.new())
	mgr._apply_remote_event({"k": "act", "a": "crouch", "p": true, "s": 1.0})
	# parse_input_event va a un buffer que el motor vacia una vez por frame.
	Input.flush_buffered_events()
	assert_bool(Input.is_action_pressed("crouch")).is_true()
	# Frames sin mensajes nuevos: sigue apretado (no hay "tick sin muestra" que lo suelte).
	for _i in range(3):
		Input.flush_buffered_events()
		assert_bool(Input.is_action_pressed("crouch")).is_true()

	mgr._apply_remote_event({"k": "act", "a": "crouch", "p": false, "s": 0.0})
	Input.flush_buffered_events()
	assert_bool(Input.is_action_pressed("crouch")).is_false()

func test_host_releases_every_held_remote_action_on_disconnect():
	# Sin add_child a proposito: en el arbol, _ready levanta el servidor en el proceso de test.
	var mgr = auto_free(RemoteControlManager.new())
	mgr._apply_remote_event({"k": "act", "a": "crouch", "p": true, "s": 1.0})
	mgr._apply_remote_event({"k": "act", "a": "run", "p": true, "s": 1.0})
	Input.flush_buffered_events()
	# Control: de verdad quedaron apretadas (si no, soltar no probaria nada).
	assert_bool(Input.is_action_pressed("crouch")).is_true()
	assert_bool(Input.is_action_pressed("run")).is_true()
	# Cada accion con su propio id: con int() compartian "act:0:0" y soltar una borraba otra.
	assert_int(mgr._remote_held.size()).is_equal(2)

	mgr._release_remote_inputs()
	Input.flush_buffered_events()
	assert_bool(Input.is_action_pressed("crouch")).is_false()
	assert_bool(Input.is_action_pressed("run")).is_false()
	assert_int(mgr._remote_held.size()).is_equal(0)

# --- El aviso de emparejamiento tiene prioridad sobre la pausa ---

func _noop_pairing(_accepted: bool) -> void:
	pass

func test_pairing_prompt_sits_above_the_pause_menu_and_pause_yields():
	# Si la ventana perdio el foco mientras llegaba la solicitud, al volver el menu de pausa
	# (CanvasLayer 50) tapaba el aviso y se comia el primer clic: no se podia aceptar.
	# El autoload por ruta: en este archivo "RemoteControlManager" es el script cargado arriba.
	var rcm = get_node("/root/RemoteControlManager")
	var was_host_active: bool = rcm.is_host_active
	rcm.is_host_active = true
	rcm._on_server_pair_requested("Telefono", "123456", funcref(self, "_noop_pairing"))

	var dialog = rcm._pairing_dialog
	assert_object(dialog).is_not_null()
	var layer = dialog.get_parent()
	assert_bool(layer is CanvasLayer).is_true()
	assert_int(layer.layer).is_greater(50) # por encima de PauseMenuLayer
	assert_bool(rcm.is_pairing_prompt_open()).is_true()
	assert_bool(PauseManager._pairing_prompt_open()).is_true()

	dialog._finish(false)
	assert_bool(rcm.is_pairing_prompt_open()).is_false()
	assert_bool(PauseManager._pairing_prompt_open()).is_false()

	# La solicitud pausa el arbol; que el test no lo deje pausado aunque falle algo arriba.
	get_tree().paused = false
	rcm.is_host_active = was_host_active

# --- Jugar desde el control saca al host de la pausa ---

func test_what_counts_as_remote_activity():
	var mgr = auto_free(RemoteControlManager.new())
	assert_bool(mgr._is_remote_activity("event", {"k": "act", "a": "jump", "p": true})).is_true()
	assert_bool(mgr._is_remote_activity("event", {"k": "key", "sc": KEY_W, "p": true})).is_true()
	assert_bool(mgr._is_remote_activity("touch_camera", {"x": 3.0, "y": 0.0, "zoom": 0.0})).is_true()
	# Un release no: el release_all al perder el foco reanudaria el host.
	assert_bool(mgr._is_remote_activity("event", {"k": "act", "a": "jump", "p": false})).is_false()
	assert_bool(mgr._is_remote_activity("release_all", {})).is_false()
	# Un stick en reposo con deriva tampoco.
	assert_bool(mgr._is_remote_activity("event", {"k": "jm", "a": 0, "v": 0.2})).is_false()
	assert_bool(mgr._is_remote_activity("event", {"k": "jm", "a": 0, "v": 0.8})).is_true()

func test_remote_activity_resumes_the_pause_menu_but_not_hud_mode():
	var rcm = get_node("/root/RemoteControlManager")
	var previous_menu = PauseManager.pause_menu_instance
	var menu := Control.new()
	PauseManager.pause_menu_instance = menu
	var press := {"k": "act", "a": "interact", "p": true, "s": 1.0}
	var release := {"k": "act", "a": "interact", "p": false, "s": 0.0}

	# Pausa del modo HUD del host: es de quien lo usa, no se toca.
	get_tree().paused = true
	PauseManager._hud_mode_paused = true
	rcm._on_server_input_received("event", press)
	assert_bool(get_tree().paused).is_true()
	PauseManager._hud_mode_paused = false

	# Un release con el menu abierto no despierta.
	menu.show()
	rcm._on_server_input_received("event", release)
	assert_bool(get_tree().paused).is_true()

	# Apretar algo desde el control, con el menu de pausa abierto: reanuda.
	rcm._on_server_input_received("event", press)
	assert_bool(get_tree().paused).is_false()
	assert_bool(menu.visible).is_false()

	rcm._on_server_input_received("event", release)
	Input.flush_buffered_events()
	get_tree().paused = false
	PauseManager.pause_menu_instance = previous_menu
	menu.free()
