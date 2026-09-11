extends Node

# RemoteDiscovery.gd - Listens for UDP broadcasts from ODISEA host sessions on LAN.

signal sessions_updated(sessions)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var listen_port: int = 10442
export var stasis_timeout: float = 6.0 # Sessions not heard from in 6 seconds expire

var _udp = PacketPeerUDP.new()
var _is_listening: bool = false
# Dictionary: session_key (ip_wsport) -> { ip, session_name, version, ws_port, sensor_port, last_seen }
var discovered_sessions: Dictionary = {}

func start_discovery() -> bool:
	if _is_listening:
		return true
	var err = _udp.listen(listen_port)
	if err != OK:
		printerr("[RemoteDiscovery] Could not listen on port ", listen_port, " err=", err)
		return false
	_is_listening = true
	print("[RemoteDiscovery] Listening for session broadcasts on port ", listen_port)
	return true

func stop_discovery() -> void:
	if not _is_listening:
		return
	_udp.close()
	_is_listening = false
	discovered_sessions.clear()
	emit_signal("sessions_updated", discovered_sessions)

func _process(delta: float) -> void:
	if not _is_listening:
		return

	_read_packets()
	_cleanup_stale_sessions(delta)

func _read_packets() -> void:
	var updated = false
	while _udp.get_available_packet_count() > 0:
		# get_packet() PRIMERO: es quien carga la IP de origen. Leerla antes daba la del
		# paquete anterior (vacia en el primero): el mismo host aparecia como ":10443" y
		# como "ip:10443", y con dos hosts las IP se cruzaban.
		var packet = _udp.get_packet()
		var ip = _udp.get_packet_ip()
		var dict = RemoteProtocol.decode_json(packet.get_string_from_utf8())
		if _register_announce(ip, dict):
			updated = true

	if updated:
		emit_signal("sessions_updated", discovered_sessions)

func _register_announce(ip: String, dict: Dictionary) -> bool:
	if ip == "" or not RemoteProtocol.is_valid_announce(dict):
		return false
	var ws_port = int(dict.get("ws_port", 10443))
	# Un host que llega por varias IP (cable + wifi) es uno solo. Se queda la ultima IP
	# oida: cualquiera que haya traido el broadcast es alcanzable. ip:puerto queda solo
	# para hosts viejos que no mandan host_id.
	var key = String(dict.get("host_id", ""))
	if key == "":
		key = "%s:%d" % [ip, ws_port]
	discovered_sessions[key] = {
		"key": key,
		"ip": ip,
		"session_name": dict.get("session_name", "Odisea Session"),
		"version": dict.get("version", ""),
		"os": String(dict.get("os", "")),
		"ws_port": ws_port,
		"sensor_port": int(dict.get("sensor_port", 10444)),
		"last_seen": OS.get_system_time_msecs()
	}
	return true

func _cleanup_stale_sessions(_delta: float) -> void:
	var now = OS.get_system_time_msecs()
	var to_remove = []
	for key in discovered_sessions:
		var s = discovered_sessions[key]
		if (now - s["last_seen"]) > (stasis_timeout * 1000.0):
			to_remove.append(key)

	if to_remove.size() > 0:
		for key in to_remove:
			discovered_sessions.erase(key)
		emit_signal("sessions_updated", discovered_sessions)
