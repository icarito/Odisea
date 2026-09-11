extends Node

# RemoteAnnouncer.gd - Sends UDP broadcast packets every ~2 seconds advertising the active session.

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var VersionLabel = load("res://core_v2/ui/VersionLabel.gd")

export var broadcast_port: int = 10442
export var broadcast_interval: float = 2.0
export var session_name: String = "Odisea Session"

var _udp = PacketPeerUDP.new()
var _timer: float = 0.0
var _active: bool = false
var _ws_port: int = 10443
var _sensor_port: int = 10444
var _host_id: String = ""

func _ready():
	_udp.set_broadcast_enabled(true)
	# Por proceso, no por maquina: OS.get_unique_id() no esta implementado en Linux.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_host_id = "%08x%08x" % [rng.randi(), rng.randi()]

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
	# config/version es un placeholder fijo; la version real sale de build_meta.
	var version: String = VersionLabel.get_formatted_version()
	var payload = RemoteProtocol.create_announce_payload(session_name, version, _ws_port, _sensor_port, _host_id, RemoteProtocol.os_label())
	var json_str = RemoteProtocol.encode_json(payload)
	var bytes = json_str.to_utf8()
	_udp.set_dest_address("255.255.255.255", broadcast_port)
	_udp.put_packet(bytes)
