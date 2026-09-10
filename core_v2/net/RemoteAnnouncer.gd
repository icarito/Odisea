extends Node

# RemoteAnnouncer.gd - Sends UDP broadcast packets every ~2 seconds advertising the active session.

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var broadcast_port: int = 10442
export var broadcast_interval: float = 2.0
export var session_name: String = "Odisea Session"

var _udp = PacketPeerUDP.new()
var _timer: float = 0.0
var _active: bool = false
var _ws_port: int = 10443
var _sensor_port: int = 10444

func _ready():
	_udp.set_broadcast_enabled(true)

func start_announcing(p_session_name: String = "", p_ws_port: int = 10443, p_sensor_port: int = 10444) -> void:
	if p_session_name != "":
		session_name = p_session_name
	_ws_port = p_ws_port
	_sensor_port = p_sensor_port
	_active = true
	_timer = broadcast_interval # send immediately

func stop_announcing() -> void:
	_active = false

func _process(delta: float) -> void:
	if not _active:
		return
	_timer += delta
	if _timer >= broadcast_interval:
		_timer = 0.0
		_send_broadcast()

func _send_broadcast() -> void:
	var version = ProjectSettings.get_setting("application/config/version") if ProjectSettings.has_setting("application/config/version") else "v0.4.0"
	var payload = RemoteProtocol.create_announce_payload(session_name, str(version), _ws_port, _sensor_port)
	var json_str = RemoteProtocol.encode_json(payload)
	var bytes = json_str.to_utf8()
	_udp.set_dest_address("255.255.255.255", broadcast_port)
	_udp.put_packet(bytes)
