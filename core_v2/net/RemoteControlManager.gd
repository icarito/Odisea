extends Node

# RemoteControlManager.gd - Autoload coordinator for ODISEA Remote Control subsystem.

signal remote_input_received(input_type, payload)
signal pairing_prompt_requested(device_name, pin, callback)

var RemoteAnnouncer = load("res://core_v2/net/RemoteAnnouncer.gd")
var RemoteDiscovery = load("res://core_v2/net/RemoteDiscovery.gd")
var RemoteControlServer = load("res://core_v2/net/RemoteControlServer.gd")
var RemoteControlClient = load("res://core_v2/net/RemoteControlClient.gd")

var announcer: Node = null
var discovery: Node = null
var server: Node = null
var client: Node = null

var is_host_active: bool = false
var remote_control_enabled: bool = true

func _ready():
	announcer = RemoteAnnouncer.new()
	announcer.name = "RemoteAnnouncer"
	add_child(announcer)

	discovery = RemoteDiscovery.new()
	discovery.name = "RemoteDiscovery"
	add_child(discovery)

	server = RemoteControlServer.new()
	server.name = "RemoteControlServer"
	add_child(server)

	client = RemoteControlClient.new()
	client.name = "RemoteControlClient"
	add_child(client)

	server.connect("client_pair_requested", self, "_on_server_pair_requested")
	server.connect("input_received", self, "_on_server_input_received")

	_apply_settings()

func _apply_settings() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "remote_control_enabled" in sm:
		remote_control_enabled = sm.remote_control_enabled

	if remote_control_enabled:
		start_host_services()
	else:
		stop_host_services()

func start_host_services(session_name: String = "Odisea Session") -> void:
	if not remote_control_enabled:
		return
	if is_host_active:
		return

	if server.start_server():
		announcer.start_announcing(session_name, server.ws_port, server.sensor_udp_port)
		is_host_active = true
		print("[RemoteControlManager] Host services started successfully")

func stop_host_services() -> void:
	if not is_host_active:
		return
	announcer.stop_announcing()
	server.stop_server()
	is_host_active = false
	print("[RemoteControlManager] Host services stopped")

func set_remote_control_enabled(enabled: bool) -> void:
	remote_control_enabled = enabled
	if enabled:
		start_host_services()
	else:
		stop_host_services()

func _on_server_pair_requested(device_name: String, pin: String, callback: FuncRef) -> void:
	emit_signal("pairing_prompt_requested", device_name, pin, callback)

func _on_server_input_received(input_type: String, payload: Dictionary) -> void:
	print("[RemoteControlManager] Input received: ", input_type, " ", payload)
	emit_signal("remote_input_received", input_type, payload)
