extends Node

# Network state
var is_server := false
var is_client := false
var players = {}

# Scene references
export var network_player_scene = preload("res://scenes/multiplayer/NetworkPlayer.tscn")
export var spawn_node_name: String = "CoopLevel" # Nodo donde se agregan los jugadores

# Nivel actual cargado
var current_level_path: String = ""
var level_ready: bool = false

# Multiplayer state
var lan_ip: String = ""
var server_port: int = 0

# LAN discovery
const LAN_DISCOVERY_PORT = 54545
const LAN_DISCOVERY_GROUP = "239.255.42.99"
const LAN_DISCOVERY_MSG = "HOST:%s:%d"
var udp_socket := PacketPeerUDP.new()
var broadcast_timer := Timer.new()
var discovered_servers := {}

signal server_discovered(ip)
signal game_started

func _ready():
	# Connect network signals
	get_tree().connect("network_peer_connected", self, "_on_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_on_player_disconnected")
	get_tree().connect("connected_to_server", self, "_on_connected_to_server")
	get_tree().connect("connection_failed", self, "_on_connection_failed")
	get_tree().connect("server_disconnected", self, "_on_server_disconnected")

	# LAN discovery timer
	broadcast_timer.wait_time = 1.0
	broadcast_timer.connect("timeout", self, "_broadcast_lan_presence")
	add_child(broadcast_timer)

# --- Network Management ---

func create_server(port: int = 7777):
	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port)
	if result != OK:
		print("[MultiplayerManager] ERROR: No se pudo crear el servidor ENet en el puerto %d (código %d)" % [port, result])
		return
	get_tree().network_peer = peer
	is_server = true
	is_client = false
	self.server_port = port

	start_lan_discovery()
	_start_lan_broadcast(port)

func join_server(ip: String, port: int = 7777):
	var peer = NetworkedMultiplayerENet.new()
	peer.create_client(ip, port)
	get_tree().network_peer = peer
	is_server = false
	is_client = true

# --- Game Management ---

func start_game(level_path: String = "res://scenes/levels/act1/Criogenia.tscn"):
	emit_signal("game_started")
	current_level_path = level_path
	level_ready = false
	get_tree().connect("node_added", self, "_on_node_added")
	get_tree().change_scene(level_path)

remotesync func _spawn_player(id):
	if not level_ready:
		print("[MultiplayerManager] Esperando a que el nivel esté listo para instanciar jugador...")
		call_deferred("_spawn_player", id)
		return
	var player = network_player_scene.instance()
	player.name = str(id)
	player.set_network_master(1) # Server es master
	var spawn_node = get_tree().get_root().get_node(spawn_node_name)
	if spawn_node:
		spawn_node.add_child(player)
		players[id] = player
	else:
		print("[MultiplayerManager] ERROR: Nodo de spawn '" + spawn_node_name + "' no encontrado en la escena.")
# Detecta cuando el nodo de spawn aparece en el árbol
func _on_node_added(node):
	if node.name == spawn_node_name:
		print("[MultiplayerManager] Nodo de spawn '" + spawn_node_name + "' listo.")
		level_ready = true
		get_tree().disconnect("node_added", self, "_on_node_added")

# --- Signal Handlers ---

func _on_player_connected(id):
	print("Player connected: ", id)

	# Tell the new player about all existing players
	for player_id in players:
		rpc_id(id, "_spawn_player", player_id)

	# Spawn the new player on the server and all clients
	_spawn_player(id)

func _on_player_disconnected(id):
	print("Player disconnected: ", id)
	rpc("_remove_player", id)

remotesync func _remove_player(id):
	if players.has(id):
		players[id].queue_free()
		players.erase(id)

func _on_connected_to_server():
	print("Successfully connected to server")
	emit_signal("game_started")

func _on_connection_failed():
	print("Failed to connect to server")
	get_tree().network_peer = null

func _on_server_disconnected():
	print("Disconnected from server")
	get_tree().network_peer = null

# --- LAN Discovery ---

func start_lan_discovery():
	if udp_socket.listen(LAN_DISCOVERY_PORT) != OK:
		print("[MultiplayerManager] Error listening on port %d" % LAN_DISCOVERY_PORT)
		return

	var interfaces = IP.get_local_interfaces()
	var success = false

	for iface in interfaces:
		var suitable_ip = ""
		for ip in iface["addresses"]:
			# Find the first suitable private IPv4 address on this interface to use for broadcasting
			var is_private_ipv4 = false
			if ip.find(":") == -1: # Ensure it's not IPv6
				if ip.begins_with("192.168.") or ip.begins_with("10."):
					is_private_ipv4 = true
				elif ip.begins_with("172."):
					var parts = ip.split(".")
					if parts.size() > 1:
						var second_octet = parts[1].to_int()
						if second_octet >= 16 and second_octet <= 31:
							is_private_ipv4 = true
			if is_private_ipv4:
				suitable_ip = ip
				break # Found a good IP for this interface
		
		if suitable_ip != "":
			print("[MultiplayerManager] Probando interfaz: '%s' (usando IP %s para broadcast)" % [iface["name"], suitable_ip])
			if udp_socket.join_multicast_group(LAN_DISCOVERY_GROUP, iface["name"]) == OK:
				print("[MultiplayerManager] ¡Éxito! Unido al grupo multicast con interfaz '%s'" % iface["name"])
				self.lan_ip = suitable_ip # Save the IP for broadcasting
				success = true
				break # Exit the main loop, we are connected
	
	if not success:
		print("[MultiplayerManager] ERROR FATAL: No se pudo unir al grupo multicast en ninguna interfaz de red válida.")
		udp_socket.close()
		return

	set_process(true)
func stop_lan_discovery():
	set_process(false)
	# On stop, we should leave the group, but closing the socket does this implicitly.
	udp_socket.close()

func _process(delta):
	if udp_socket.get_available_packet_count() > 0:
		var packet = udp_socket.get_packet()
		var msg = packet.get_string_from_utf8()
		if msg.begins_with("HOST:"):
			var parts = msg.split(":")
			if parts.size() == 3:
				var ip = parts[1]
				if not discovered_servers.has(ip):
					discovered_servers[ip] = true
					emit_signal("server_discovered", ip)

func _start_lan_broadcast(port: int):
	broadcast_timer.start()

func _broadcast_lan_presence():
	if lan_ip == "":
		print("[MultiplayerManager] ERROR: No hay IP de LAN para broadcast. ¿Falló el descubrimiento?")
		return
	
	var msg = LAN_DISCOVERY_MSG % [lan_ip, self.server_port]
	udp_socket.set_dest_address(LAN_DISCOVERY_GROUP, LAN_DISCOVERY_PORT)
	udp_socket.put_packet(msg.to_utf8())

func stop_lan_broadcast():
	broadcast_timer.stop()

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		stop_lan_discovery()
