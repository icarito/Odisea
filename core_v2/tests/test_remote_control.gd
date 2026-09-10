extends GdUnitTestSuite

# test_remote_control.gd - GDScript unit test suite for ODISEA Remote Control v1 subsystem.

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var RemoteDiscovery = load("res://core_v2/net/RemoteDiscovery.gd")
var RemoteControlServer = load("res://core_v2/net/RemoteControlServer.gd")
var RemoteControlClient = load("res://core_v2/net/RemoteControlClient.gd")

func test_protocol_serialize_and_parse():
	var announce = RemoteProtocol.create_announce_payload("Test Session", "v0.4.0", 10443, 10444)
	assert_bool(RemoteProtocol.is_valid_announce(announce)).is_true()

	var encoded = RemoteProtocol.encode_json(announce)
	var decoded = RemoteProtocol.decode_json(encoded)
	assert_str(decoded.get("session_name", "")).is_equal("Test Session")
	assert_str(decoded.get("version", "")).is_equal("v0.4.0")
	assert_int(int(decoded.get("ws_port", 0))).is_equal(10443)

func test_pair_request_and_result_messages():
	var req = RemoteProtocol.create_pair_request("Phone 1", "123456")
	assert_str(req.get("type", "")).is_equal("pair_request")
	assert_str(req.get("device_name", "")).is_equal("Phone 1")
	assert_str(req.get("pin", "")).is_equal("123456")

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
