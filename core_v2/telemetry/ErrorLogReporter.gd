extends Node

# Manda al central las lineas de ERROR del log del motor.
#
# Por que existe: en movil no hay consola ni comandos remotos, y los errores que solo
# pasan en un dispositivo ajeno (drivers GLES2, shaders que no linkean, assets que no
# cargan) hoy solo se ven si el jugador saca una foto de la pantalla. El overlay de log
# sirve cuando uno tiene el telefono en la mano; esto sirve cuando no.
#
# Que NO hace: no manda el log entero ni nada que el jugador escriba. Solo las lineas
# que matchean los keywords de error, recortadas, y los datos que ya viajan con la
# telemetria (player_id, session_id, plataforma, version). Se apaga con la opcion
# "Enviar reportes de error" (SettingsManager.error_reports_enabled).
#
# Reusa el transporte de HotzoneRecorder: la URL sale del hilo de red de ANNAV2 (peer de
# LAN si esta conectado, central si no) y el token es el mismo bridge token.

const ENDPOINT := "/client-log"
const LOG_PATH_FALLBACK := "user://logs/godot.log"
const DEFAULT_BASE := "wss://odisea.educa.juegos/ws"
# Cada cuanto se vacia lo acumulado. No se espera al cierre: en Android e iOS el proceso
# se mata sin avisar y ese es justo el caso que interesa reportar.
const FLUSH_SECONDS := 60.0
# Gracia inicial: los primeros segundos son carga de escena y compilacion de shaders, y
# el hilo de red de ANNAV2 todavia no resolvio la URL.
const FIRST_FLUSH_SECONDS := 30.0
const MAX_LINES_PER_FLUSH := 40
const MAX_LINE_CHARS := 400
# Tope por sesion: un error por frame llenaria el disco del central sin decir nada nuevo.
const MAX_LINES_PER_SESSION := 200

const KEYWORDS := ["ERROR", "SCRIPT ERROR", "USER ERROR", "WARNING: shader",
	"shader", "Shader", "SHADER", "Failed", "failed", "Cannot", "cannot"]
# Ruido conocido que no aporta y que aparece en cada arranque.
const IGNORE := ["ERROR: NO GRAB", "LAG SPIKE"]

var _http: HTTPRequest = null
var _read_pos := 0
var _pending := []
var _sent := 0
var _elapsed := 0.0
var _next_flush := FIRST_FLUSH_SECONDS
var _busy := false
var _log_path := ""


func _ready() -> void:
	_log_path = String(ProjectSettings.get_setting("logging/file_logging/log_path"))
	if _log_path == "":
		_log_path = LOG_PATH_FALLBACK
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)
	_http.connect("request_completed", self, "_on_completed")
	set_process(true)


func _process(delta: float) -> void:
	if _sent >= MAX_LINES_PER_SESSION:
		set_process(false)
		return
	_elapsed += delta
	if _elapsed < _next_flush:
		return
	_elapsed = 0.0
	_next_flush = FLUSH_SECONDS
	_scan()
	if not _pending.empty() and not _busy and _wants_reports():
		_flush()


func _wants_reports() -> bool:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		return false
	# La telemetria general manda: si el jugador la apago, esto tampoco sale.
	return bool(sm.error_reports_enabled) and bool(sm.telemetry_enabled)


# --- Lectura incremental del log ----------------------------------------------------

func _scan() -> void:
	var f := File.new()
	if not f.file_exists(_log_path):
		return
	if f.open(_log_path, File.READ) != OK:
		return
	var length := int(f.get_len())
	if length < _read_pos:  # el motor roto el log
		_read_pos = 0
	if length == _read_pos:
		f.close()
		return
	f.seek(_read_pos)
	while not f.eof_reached() and _pending.size() < MAX_LINES_PER_FLUSH:
		var line := f.get_line().strip_edges()
		if line == "" or _is_noise(line):
			continue
		for k in KEYWORDS:
			if line.find(k) != -1:
				_pending.append(line.substr(0, MAX_LINE_CHARS))
				break
	_read_pos = length
	f.close()


static func _is_noise_in(line: String, ignore: Array) -> bool:
	for n in ignore:
		if line.find(n) != -1:
			return true
	return false


func _is_noise(line: String) -> bool:
	return _is_noise_in(line, IGNORE)


# --- Envio ---------------------------------------------------------------------------

func _flush() -> void:
	var url := _endpoint_url()
	if url == "":
		return
	var payload := {
		"player_id": _anna_str("_player_id", "player_id", "unknown"),
		"session_id": _anna_str("_session_id", "session_id", ""),
		"platform": OS.get_name(),
		"version": String(ProjectSettings.get_setting("application/config/version")),
		"gpu": VisualServer.get_video_adapter_name(),
		"lines": _pending,
	}
	var headers := [
		"Content-Type: application/json",
		"X-Player-ID: " + String(payload["player_id"]),
		"X-Session-ID: " + String(payload["session_id"]),
	]
	var token := _token()
	if token != "":
		headers.append("Authorization: Bearer " + token)
	_busy = true
	var err := _http.request(url, headers, true, HTTPClient.METHOD_POST, JSON.print(payload))
	if err != OK:
		_busy = false


func _on_completed(_result, response_code, _headers, _body) -> void:
	_busy = false
	if response_code == 200 or response_code == 201 or response_code == 204:
		_sent += _pending.size()
		_pending = []
	# Con cualquier otro codigo se dejan en _pending y se reintenta en el proximo flush;
	# el tope por flush ya acota cuanto puede crecer.


func _endpoint_url() -> String:
	var base := DEFAULT_BASE
	var net = _net_thread()
	if net != null:
		var peer_url = net._peer_url if "_peer_url" in net else ""
		var central_url = net._central_url if "_central_url" in net else ""
		var connected = net._is_connected if "_is_connected" in net else false
		if connected and peer_url != "" and peer_url != central_url:
			base = peer_url
		elif central_url != "":
			base = central_url
	var url: String = base.replace("/ws", ENDPOINT)
	if url.begins_with("ws://"):
		url = url.replace("ws://", "http://")
	if url.begins_with("wss://"):
		url = url.replace("wss://", "https://")
	return url


func _net_thread():
	var anna = get_node_or_null("/root/ANNAV2")
	if anna != null and "_net_thread" in anna:
		return anna._net_thread
	return null


func _token() -> String:
	var net = _net_thread()
	if net != null and "_bridge_token" in net:
		return String(net._bridge_token)
	return ""


func _anna_str(private_name: String, public_name: String, fallback: String) -> String:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna != null:
		if private_name in anna:
			return String(anna.get(private_name))
		if public_name in anna:
			return String(anna.get(public_name))
	return fallback
