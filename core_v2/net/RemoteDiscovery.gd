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
		var ip = _udp.get_packet_ip()
		var packet = _udp.get_packet()
		var pkt_str = packet.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		if RemoteProtocol.is_valid_announce(dict):
			var ws_port = int(dict.get("ws_port", 10443))
			var key = "%s:%d" % [ip, ws_port]
			discovered_sessions[key] = {
				"key": key,
				"ip": ip,
				"session_name": dict.get("session_name", "Odisea Session"),
				"version": dict.get("version", "v0.4.0"),
				"ws_port": ws_port,
				"sensor_port": int(dict.get("sensor_port", 10444)),
				"last_seen": OS.get_system_time_msecs()
			}
			updated = true

	if updated:
		emit_signal("sessions_updated", discovered_sessions)

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
