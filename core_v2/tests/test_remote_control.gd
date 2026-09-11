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
