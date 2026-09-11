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
var _paused_for_pairing: bool = false
var _mouse_mode_before_pairing: int = Input.MOUSE_MODE_VISIBLE

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	announcer = RemoteAnnouncer.new()
	announcer.name = "RemoteAnnouncer"
	add_child(announcer)

	discovery = RemoteDiscovery.new()
	discovery.name = "RemoteDiscovery"
	add_child(discovery)

	server = RemoteControlServer.new()
	server.name = "RemoteControlServer"
	server.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(server)

	client = RemoteControlClient.new()
	client.name = "RemoteControlClient"
	add_child(client)

	server.connect("client_pair_requested", self, "_on_server_pair_requested")
	server.connect("input_received", self, "_on_server_input_received")

	_apply_settings()
	call_deferred("_sync_host_for_scene")

func _process(_delta: float) -> void:
	_sync_host_for_scene()

func _apply_settings() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "remote_control_enabled" in sm:
		remote_control_enabled = sm.remote_control_enabled

	_sync_host_for_scene()

func _sync_host_for_scene() -> void:
	var scene = get_tree().current_scene
	var scene_path: String = scene.filename if scene else ""
	var should_host: bool = remote_control_enabled and _is_gameplay_scene(scene_path)
	if should_host and not is_host_active:
		start_host_services()
	elif not should_host and is_host_active:
		stop_host_services()

func _is_gameplay_scene(scene_path: String) -> bool:
	return scene_path != "" and scene_path.find("Menu.tscn") == -1 and scene_path.find("Boot.tscn") == -1 \
		and scene_path.find("RemoteControlHome.tscn") == -1

func start_host_services(session_name: String = "") -> void:
	if not remote_control_enabled:
		return
	if is_host_active:
		return
	if session_name == "":
		session_name = OS.get_environment("HOSTNAME").strip_edges()
		if session_name == "":
			session_name = "Odisea Host"

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
	_sync_host_for_scene()

func _on_server_pair_requested(device_name: String, pin: String, callback: FuncRef) -> void:
	if not is_host_active:
		callback.call_func(false)
		return
	_paused_for_pairing = not get_tree().paused
	_mouse_mode_before_pairing = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	var dialog = load("res://core_v2/ui/RemotePairingDialog.tscn").instance()
	dialog.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(dialog)
	dialog.connect("pairing_completed", self, "_on_pairing_completed", [dialog], CONNECT_ONESHOT)
	dialog.prompt_pairing(device_name, pin, callback)

func _on_pairing_completed(_accepted: bool, dialog: Node) -> void:
	if _paused_for_pairing:
		get_tree().paused = false
		Input.set_mouse_mode(_mouse_mode_before_pairing)
		_paused_for_pairing = false
	dialog.queue_free()

func _on_server_input_received(input_type: String, payload: Dictionary) -> void:
	print("[RemoteControlManager] Input received: ", input_type, " ", payload)
	if input_type == "input_data":
		var session = get_node_or_null("/root/SessionManager")
		var player = session.player if session else null
		var input_provider = player.input_provider if player and "input_provider" in player else null
		if player and input_provider and input_provider.hardware_input_enabled and player.has_method("inject_input"):
			player.inject_input(payload)
	emit_signal("remote_input_received", input_type, payload)
