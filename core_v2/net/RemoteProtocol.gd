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

# host_id identifica al proceso anunciante: un host con varias interfaces (cable + wifi)
# llega desde mas de una IP, y listar por ip:puerto lo mostraba repetido.
static func create_announce_payload(session_name: String, version: String, ws_port: int = DEFAULT_WS_PORT, sensor_port: int = DEFAULT_SENSOR_UDP_PORT, host_id: String = "", os_name: String = "") -> Dictionary:
	return {
		"app": APP_ID,
		"proto": PROTO_VERSION,
		"session_name": session_name,
		"version": version,
		"ws_port": ws_port,
		"sensor_port": sensor_port,
		"host_id": host_id,
		"os": os_name,
		"timestamp": OS.get_system_time_msecs()
	}

static func os_label() -> String:
	match OS.get_name():
		"X11":
			return "Linux"
		"OSX":
			return "macOS"
		"UWP":
			return "Windows"
	return OS.get_name()

# Godot 3 no expone el hostname. En movil no existe: el modelo del equipo cumple ese papel.
static func device_hostname() -> String:
	if OS.get_name() in ["Android", "iOS"]:
		return OS.get_model_name().strip_edges()
	var name: String = OS.get_environment("COMPUTERNAME") # Windows
	if name == "":
		var f := File.new()
		if f.open("/etc/hostname", File.READ) == OK: # Linux
			name = f.get_line()
			f.close()
	if name == "":
		var out: Array = []
		if OS.execute("hostname", [], true, out) == 0 and not out.empty(): # macOS
			name = String(out[0])
	return name.strip_edges()

# "hostname (SO)", o solo el SO si no hay hostname.
static func device_label() -> String:
	var host := device_hostname()
	return "%s (%s)" % [host, os_label()] if host != "" else os_label()

static func is_valid_announce(dict: Dictionary) -> bool:
	return dict.get("app", "") == APP_ID and int(dict.get("proto", 0)) == PROTO_VERSION and dict.has("ws_port") and dict.has("session_name")

static func create_pair_request(device_name: String, pin: String = "") -> Dictionary:
	return {
		"type": "pair_request",
		"device_name": device_name,
		"pin": pin
	}

static func create_pair_pin(pin: String) -> Dictionary:
	return {
		"type": "pair_pin",
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
	# op: "message", "prompt", "clear", "host_paused" ({paused: bool})
	return {
		"type": "ui",
		"op": op,
		"payload": payload
	}

static func create_input_message(input_type: String, payload: Dictionary, token: String = "") -> Dictionary:
	# input_type: "input_data" (InputDataV2 de un control tactil), "event" (evento crudo,
	# ver encode_event), "mouse_delta" ({x, y} acumulado por tick), "release_all",
	# "touch", "accel", "gyro"
	return {
		"type": "input",
		"input_type": input_type,
		"payload": payload,
		"token": token
	}

# Passthrough de teclado, botones de mouse y joypad tal cual, modificadores incluidos.
# Campos en lista blanca a proposito: str2var/bytes2var con objetos le dejarian a un peer
# instanciar cualquier clase en el host. La posicion del mouse viaja normalizada (0..1)
# porque las pantallas de los dos lados no miden lo mismo.
static func encode_event(ev: InputEvent, viewport_size: Vector2) -> Dictionary:
	var d: Dictionary = {}
	if ev is InputEventKey:
		var k := ev as InputEventKey
		d = {"k": "key", "sc": k.scancode, "psc": k.physical_scancode, "u": k.unicode, "p": k.pressed, "e": k.echo}
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var pos: Vector2 = mb.position / viewport_size if viewport_size.x > 0.0 and viewport_size.y > 0.0 else Vector2(0.5, 0.5)
		d = {"k": "mb", "b": mb.button_index, "p": mb.pressed, "f": mb.factor, "x": pos.x, "y": pos.y}
	elif ev is InputEventJoypadButton:
		var jb := ev as InputEventJoypadButton
		return {"k": "jb", "b": jb.button_index, "p": jb.pressed, "pr": jb.pressure}
	elif ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		return {"k": "jm", "a": jm.axis, "v": jm.axis_value}
	else:
		return {}
	var m := ev as InputEventWithModifiers
	d["sh"] = m.shift
	d["ct"] = m.control
	d["al"] = m.alt
	d["me"] = m.meta
	d["cm"] = m.command
	return d

static func decode_event(d: Dictionary, viewport_size: Vector2) -> InputEvent:
	var ev: InputEventWithModifiers = null
	match String(d.get("k", "")):
		"key":
			var k := InputEventKey.new()
			k.scancode = int(d.get("sc", 0))
			k.physical_scancode = int(d.get("psc", 0))
			k.unicode = int(d.get("u", 0))
			k.pressed = bool(d.get("p", false))
			k.echo = bool(d.get("e", false))
			ev = k
		"mb":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("b", 0))
			mb.pressed = bool(d.get("p", false))
			mb.factor = float(d.get("f", 1.0))
			mb.position = Vector2(clamp(float(d.get("x", 0.5)), 0.0, 1.0), clamp(float(d.get("y", 0.5)), 0.0, 1.0)) * viewport_size
			mb.global_position = mb.position
			ev = mb
		"jb":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("b", 0))
			jb.pressed = bool(d.get("p", false))
			jb.pressure = float(d.get("pr", 0.0))
			return jb
		"jm":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("a", 0))
			jm.axis_value = clamp(float(d.get("v", 0.0)), -1.0, 1.0)
			return jm
		_:
			return null
	ev.shift = bool(d.get("sh", false))
	ev.control = bool(d.get("ct", false))
	ev.alt = bool(d.get("al", false))
	ev.meta = bool(d.get("me", false))
	ev.command = bool(d.get("cm", false))
	return ev

# Ultimo mensaje del host al cerrar la partida a proposito: el control se va sin reintentar.
static func create_session_end() -> Dictionary:
	return {"type": "session_end"}

# El control vuelve tras un corte sin aviso con el token de la sesion; el host contesta
# con pair_result (ok si el token sigue vigente).
static func create_resume(token: String) -> Dictionary:
	return {"type": "resume", "token": token}

static func create_ping() -> Dictionary:
	return {"type": "ping"}

static func create_pong() -> Dictionary:
	return {"type": "pong"}
