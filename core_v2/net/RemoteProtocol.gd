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

# FD-316 (tarea P): los paquetes de alta frecuencia (sim_snapshot, sim_input) viajan en
# binario nativo (var2bytes) en vez de JSON. Sobre un aarch64 lento, JSON.parse/print de
# GDScript era el costo mas alto del frame del Anbernic. La marca y la version van en los
# dos primeros bytes: un paquete que no las trae se decodifica como JSON, asi un peer viejo
# (o un mensaje legacy) sigue funcionando. `allow_objects = false` en bytes2var para que un
# peer no pueda instanciar clases arbitrarias con el payload.
const PACKET_MAGIC := 0x4F # 'O' de Odisea
const PACKET_VERSION := 1

static func encode_packet(dict: Dictionary) -> PoolByteArray:
	var payload: PoolByteArray = var2bytes(dict, false)
	var out := PoolByteArray()
	out.append(PACKET_MAGIC)
	out.append(PACKET_VERSION)
	out.append_array(payload)
	return out

static func decode_packet(bytes: PoolByteArray) -> Dictionary:
	if bytes.size() >= 2 and bytes[0] == PACKET_MAGIC and bytes[1] == PACKET_VERSION:
		var decoded = bytes2var(bytes.subarray(2, bytes.size() - 1), false)
		return decoded if decoded is Dictionary else {}
	# Fallback: paquete JSON de un peer viejo (o texto legacy).
	return decode_json(bytes.get_string_from_utf8())

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

static func create_ui_message(op: String, payload) -> Dictionary:
	# op: "message", "prompt", "clear", "host_paused", "screen_list", "screen_active", "screen_data", "haptic", "remote_action", "screen_select"
	return {
		"type": "ui",
		"op": op,
		"payload": payload
	}

static func create_ui_screen_list(screens: Array) -> Dictionary:
	return create_ui_message("screen_list", screens)

static func create_ui_screen_active(id: String, title: String, view: String, snapshot: Dictionary) -> Dictionary:
	return create_ui_message("screen_active", {
		"id": id,
		"title": title,
		"view": view,
		"snapshot": snapshot
	})

static func create_ui_screen_data(id: String, snapshot: Dictionary) -> Dictionary:
	return create_ui_message("screen_data", {
		"id": id,
		"snapshot": snapshot
	})

static func create_ui_haptic(kind: String, intensity: float = 1.0) -> Dictionary:
	return create_ui_message("haptic", {
		"kind": kind,
		"intensity": intensity
	})

static func create_ui_remote_action(screen_id: String, op: String, args: Dictionary = {}) -> Dictionary:
	return create_ui_message("remote_action", {
		"screen_id": screen_id,
		"op": op,
		"args": args
	})

static func create_ui_screen_select(id: String) -> Dictionary:
	return create_ui_message("screen_select", {
		"id": id
	})

# FD-316 (tarea N): acciones discretas del InputMap que NO viajan en el frame del sim_input
# (move/jump/interact/sprint/crouch/camara). El esclavo manda el flanco just_pressed por el
# WS confiable y la autoridad lo aplica al jugador simulado con el mismo efecto que su input
# local. Lista corta a proposito: crece con cada accion discreta que no tenga campo propio
# en InputDataV2.
const SIM_DISCRETE_ACTIONS := ["toggle_flashlight"]

static func create_input_message(input_type: String, payload: Dictionary, token: String = "") -> Dictionary:
	# input_type: "event" (evento: tecla, boton o accion, ver encode_event), "mouse_delta"
	# ({x, y} de un mouse capturado, acumulado por tick), "touch_camera" ({x, y, zoom} de
	# TouchCameraControls, ya en unidades de camara), "release_all", "accel", "gyro"
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
	if ev is InputEventAction:
		# Un control tactil no tiene teclas: lo que tiene son acciones (el joystick virtual
		# empuja move_* con fuerza analogica, los botones empujan jump/crouch). Viajan como
		# evento igual que una tecla, asi el host guarda el estado en su Input hasta que
		# llegue el contrario: agacharse o correr quedan sostenidos, como con teclado.
		var act := ev as InputEventAction
		if not is_forwardable_action(act.action):
			return {}
		return {"k": "act", "a": act.action, "p": act.pressed, "s": act.strength}
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
		"act":
			var action := String(d.get("a", ""))
			if not is_forwardable_action(action):
				return null
			var act := InputEventAction.new()
			act.action = action
			act.pressed = bool(d.get("p", false))
			act.strength = clamp(float(d.get("s", 1.0 if act.pressed else 0.0)), 0.0, 1.0)
			return act
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

# Solo acciones que existen en el InputMap. hud_mode nunca: el HUD es de cada dispositivo,
# y reenviarlo abria el modo HUD del host con el mismo boton.
static func is_forwardable_action(action: String) -> bool:
	return action != "" and action != "hud_mode" and InputMap.has_action(action)

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

# FD-316 Remote Simulation (Offload invertido) protocol helpers

# FD-316: sim_hello lleva TODO lo que la autoridad necesita para levantar el mismo
# nivel que tiene abierto el render-esclavo: escena, tick, token, la semilla de la
# corrida (determinismo: nunca se sortea en el sim host), el estado del jugador
# (spawn directo + snapshot completo del controlador, el mismo que viaja entre
# escenas via SessionManager.capture_scene_transition_state) y el estado persistente
# de los actores del nivel (`states`: path relativo -> get_snapshot). Sin `states` la
# autoridad arranca el nivel desde cero y su _ready vuelve a correr la intro (la
# escotilla del criopod se abria y sonaba de nuevo en el offload).
static func create_sim_hello(scene_path: String, sim_fps: int = 60, token: String = "", spawn: Dictionary = {}, run_seed: int = 0, checkpoint: Dictionary = {}, states: Dictionary = {}) -> Dictionary:
	return {
		"type": "sim_hello",
		"scene": scene_path,
		"sim_fps": sim_fps,
		"token": token,
		"spawn": spawn,
		"run_seed": run_seed,
		"checkpoint": checkpoint,
		"states": states
	}

static func create_sim_snapshot(tick: int, timestamp_msec: int, entities: Dictionary, globals: Dictionary = {}, token: String = "", ack_seq: int = 0) -> Dictionary:
	# FD-316 (tarea E): ack_seq = ultimo seq de sim_input del esclavo APLICADO al tick.
	# El esclavo guarda el instante de envio de cada seq y, con este ack, cierra el RTT
	# input->snapshot usando solo su propio reloj (no se comparan relojes entre maquinas).
	return {
		"type": "sim_snapshot",
		"tick": tick,
		"ts": timestamp_msec,
		"ack_seq": ack_seq,
		"entities": entities,
		"globals": globals,
		"token": token
	}

# FD-316: comparacion profunda de estados replicados (dicts/arrays/escalares). La usan
# el sim host al adoptar el estado del sim_hello y el render-esclavo para no re-aplicar
# un estado que el actor ya tiene (y no re-disparar sus efectos one-shot).
static func states_equal(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not states_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not states_equal(a[i], b[i]):
				return false
		return true
	if a is float and b is float:
		return is_equal_approx(a, b)
	return a == b

static func create_sim_input(axes: Dictionary, buttons: Dictionary, last_applied_tick: int, token: String = "", camera: Dictionary = {}, seq: int = 0) -> Dictionary:
	# FD-316: la camara (mouse/right stick) es lo unico del input que NO es una accion
	# del InputMap, asi que viaja aparte: sin esto el render-esclavo no podia girar la
	# camara de la autoridad (el look del control se perdia).
	# `seq` es un entero monotono por sesion del esclavo: la autoridad descarta los
	# paquetes con seq <= al ultimo visto, asi un duplicado/reordenado de WiFi no vuelve
	# a sumar el delta de camara (bug 3 del review FD-316).
	return {
		"type": "sim_input",
		"axes": axes,
		"buttons": buttons,
		"camera": camera,
		"last_tick": last_applied_tick,
		"token": token,
		"seq": seq
	}

# FD-316: cadena del rig de camara relativa al Pilot. La usan el sim host (captura) y el
# render-esclavo (aplicacion); una sola definicion evita que renombrar un nodo del rig
# rompa un lado en silencio (review FD-316, "Codigo duplicado / muerto").
const RIG_CHAIN := [
	"CameraRig",
	"CameraRig/Yaw",
	"CameraRig/Yaw/Pitch",
	"CameraRig/Yaw/Pitch/OTS_Offset",
	"CameraRig/Yaw/Pitch/OTS_Offset/SpringArm"
]

# FD-316: linterna del casco, hija directa del Pilot. No esta en replay_sync: su estado
# logico (on/off/bateria) viaja con el jugador y el render-esclavo le da la orientacion
# desde la camara replicada (ver HelmetFlashlight._process).
const FLASHLIGHT_PATH := "HelmetFlashlight"

static func encode_transform(t: Transform) -> Dictionary:
	return {
		"p": [t.origin.x, t.origin.y, t.origin.z],
		"b": [
			t.basis.x.x, t.basis.x.y, t.basis.x.z,
			t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z
		]
	}

# FD-316 (tarea P): en el camino binario las transforms viajan como Transform nativo (mas
# barato que armar/desarmar dicts de arrays), asi que el decodificador acepta las dos
# representaciones: la nativa y el dict legacy {"p": [...], "b": [...]} que todavia llega
# por el fallback JSON.
static func decode_transform(d) -> Transform:
	if d is Transform:
		return d
	var t = Transform.IDENTITY
	if d is Dictionary and d.has("p") and d["p"] is Array and d["p"].size() >= 3:
		t.origin = Vector3(d["p"][0], d["p"][1], d["p"][2])
	if d is Dictionary and d.has("b") and d["b"] is Array and d["b"].size() >= 9:
		t.basis.x = Vector3(d["b"][0], d["b"][1], d["b"][2])
		t.basis.y = Vector3(d["b"][3], d["b"][4], d["b"][5])
		t.basis.z = Vector3(d["b"][6], d["b"][7], d["b"][8])
	return t
