extends Reference

# RemoteProtocol.gd - Message formatting, serialization, and validation for ODISEA Remote Control v1.

const APP_ID = "odisea"
const PROTO_VERSION = 1
const DEFAULT_UDP_ANNOUNCE_PORT = 10442
const DEFAULT_WS_PORT = 10443
const DEFAULT_SENSOR_UDP_PORT = 10444

static func encode_json(dict: Dictionary) -> String:
	return JSON.print(dict)

static func decode_json(json_str: String) -> Dictionary:
	var parse_result = JSON.parse(json_str)
	if parse_result.error == OK and parse_result.result is Dictionary:
		return parse_result.result
	return {}

static func create_announce_payload(session_name: String, version: String, ws_port: int = DEFAULT_WS_PORT, sensor_port: int = DEFAULT_SENSOR_UDP_PORT) -> Dictionary:
	return {
		"app": APP_ID,
		"proto": PROTO_VERSION,
		"session_name": session_name,
		"version": version,
		"ws_port": ws_port,
		"sensor_port": sensor_port,
		"timestamp": OS.get_system_time_msecs()
	}

static func is_valid_announce(dict: Dictionary) -> bool:
	return dict.get("app", "") == APP_ID and int(dict.get("proto", 0)) == PROTO_VERSION and dict.has("ws_port") and dict.has("session_name")

static func create_pair_request(device_name: String, pin: String) -> Dictionary:
	return {
		"type": "pair_request",
		"device_name": device_name,
		"pin": pin
	}

static func create_pair_result(ok: bool, token: String = "", reason: String = "") -> Dictionary:
	return {
		"type": "pair_result",
		"ok": ok,
		"token": token,
		"reason": reason
	}

static func create_ui_message(op: String, payload: Dictionary) -> Dictionary:
	# op: "message", "prompt", "clear"
	return {
		"type": "ui",
		"op": op,
		"payload": payload
	}

static func create_input_message(input_type: String, payload: Dictionary, token: String = "") -> Dictionary:
	# input_type: "touch", "accel", "gyro"
	return {
		"type": "input",
		"input_type": input_type,
		"payload": payload,
		"token": token
	}

static func create_ping() -> Dictionary:
	return {"type": "ping"}

static func create_pong() -> Dictionary:
	return {"type": "pong"}
