extends Node

# RemoteControlManager.gd - Autoload coordinator for ODISEA Remote Control subsystem.

signal remote_input_received(input_type, payload)
signal pairing_prompt_requested(device_name, pin, callback)

var RemoteAnnouncer = load("res://core_v2/net/RemoteAnnouncer.gd")
var RemoteDiscovery = load("res://core_v2/net/RemoteDiscovery.gd")
var RemoteControlServer = load("res://core_v2/net/RemoteControlServer.gd")
var RemoteControlClient = load("res://core_v2/net/RemoteControlClient.gd")
var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var SuitOSRemoteBridge = load("res://core_v2/components/SuitOSRemoteBridge.gd")

var announcer: Node = null
var discovery: Node = null
var server: Node = null
var client: Node = null
var bridge: Node = null

var is_host_active: bool = false
var remote_control_enabled: bool = true
var _paused_for_pairing: bool = false
var _mouse_mode_before_pairing: int = Input.MOUSE_MODE_VISIBLE
# id -> payload de soltar, por cada tecla/boton/eje que el control remoto dejo apretado.
# Si el control se desconecta o pierde el foco sin mandar el key-up, el host se quedaria
# con la tecla pegada (el jugador corriendo solo).
var _remote_held: Dictionary = {}
# Ultimo estado de pausa avisado a los controles; -1 fuerza reenviarlo.
var _sent_paused: int = -1

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

	if SuitOSRemoteBridge != null:
		bridge = SuitOSRemoteBridge.new()
		bridge.name = "SuitOSRemoteBridge"
		bridge.pause_mode = Node.PAUSE_MODE_PROCESS
		add_child(bridge)

	server.connect("client_pair_requested", self, "_on_server_pair_requested")
	server.connect("input_received", self, "_on_server_input_received")
	server.connect("client_disconnected", self, "_on_server_client_disconnected")
	server.connect("client_stalled", self, "_on_server_client_disconnected")
	server.connect("client_connected", self, "_on_server_client_connected")

	_apply_settings()
	call_deferred("_sync_host_for_scene")

func _process(_delta: float) -> void:
	_sync_host_for_scene()
	_sync_pause_to_controls()

# El control remoto muestra cuando la partida esta en pausa aca (menu de pausa, perdida
# de foco, dialogo de emparejamiento). Solo se manda al cambiar, y de nuevo a cada
# control que se empareja o retoma (_on_server_client_connected).
func _sync_pause_to_controls() -> void:
	if not is_host_active:
		return
	var paused: int = int(get_tree().paused)
	if paused != _sent_paused:
		_sent_paused = paused
		server.send_ui_directive("host_paused", {"paused": paused == 1})

func _on_server_client_connected(_device_name: String) -> void:
	_sent_paused = -1

# Cerrar la app (Salir, quit) tambien es cerrar la partida: el control recibe session_end
# y se va en vez de reintentar 30 s. Si el sistema mata el proceso no hay aviso posible.
func _exit_tree() -> void:
	stop_host_services()

func _apply_settings() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "remote_control_enabled" in sm:
		remote_control_enabled = sm.remote_control_enabled

	_sync_host_for_scene()

func _sync_host_for_scene() -> void:
	var scene = get_tree().current_scene
	# A mitad de un cambio de escena SceneManager deja current_scene en null un frame:
	# eso no es "salir del juego". Apagar ahi cortaba al control remoto en cada cambio
	# de nivel (y el control se cierra solo cuando se le cae la sesion).
	if scene == null:
		return
	var scene_path: String = scene.filename
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
		# $HOSTNAME casi nunca llega a una app grafica (y en Android no existe): todos
		# los hosts se anunciaban como "Odisea Host".
		session_name = RemoteProtocol.device_hostname()
		if session_name == "":
			session_name = "Odisea Host"

	if server.start_server():
		announcer.start_announcing(session_name, server.ws_port, server.sensor_udp_port)
		is_host_active = true

func stop_host_services() -> void:
	if not is_host_active:
		return
	announcer.stop_announcing()
	server.stop_server()
	_release_remote_inputs()
	is_host_active = false

# Hay un control remoto emparejado desde esta misma maquina.
func has_local_remote_control() -> bool:
	return is_host_active and is_instance_valid(server) \
		and server.has_method("has_local_paired_client") and server.has_local_paired_client()

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
	var session = get_node_or_null("/root/SessionManager")
	var player = session.player if session and is_instance_valid(session.player) else null
	var input_provider = player.input_provider if player and "input_provider" in player else null
	match input_type:
		"input_data":
			if input_provider and input_provider.hardware_input_enabled and player.has_method("inject_input"):
				player.inject_input(payload)
		"event":
			_apply_remote_event(payload)
		"mouse_delta":
			# El mouse del otro lado ya esta capturado; aca se suma directo al acumulador
			# que llena PlayerControllerV2._input, que en un host tactil nunca ve el
			# mouse como capturado y descartaria el movimiento.
			if input_provider:
				input_provider.mouse_delta_accum += Vector2(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)))
		"release_all":
			_release_remote_inputs()
	emit_signal("remote_input_received", input_type, payload)

# El evento entra como si fuera hardware local: todo el InputMap (ui_*, pausa, zoom,
# modificadores) se comporta igual que con el teclado propio del host.
func _apply_remote_event(payload: Dictionary) -> void:
	var ev: InputEvent = RemoteProtocol.decode_event(payload, get_tree().root.get_visible_rect().size)
	if ev == null:
		return
	var id: String = "%s:%d:%d" % [payload.get("k", ""), int(payload.get("sc", payload.get("b", payload.get("a", 0)))), int(payload.get("psc", 0))]
	if bool(payload.get("p", false)) or abs(float(payload.get("v", 0.0))) > 0.0:
		var release: Dictionary = payload.duplicate()
		release["p"] = false
		release["e"] = false
		release["v"] = 0.0
		_remote_held[id] = release
	else:
		_remote_held.erase(id)
	Input.parse_input_event(ev)

func _release_remote_inputs() -> void:
	var viewport_size: Vector2 = get_tree().root.get_visible_rect().size
	for release in _remote_held.values():
		Input.parse_input_event(RemoteProtocol.decode_event(release, viewport_size))
	_remote_held.clear()

func _on_server_client_disconnected(_device_name: String) -> void:
	_release_remote_inputs()
