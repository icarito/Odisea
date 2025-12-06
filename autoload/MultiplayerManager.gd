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
const GAME_PORT = 7777
const LAN_DISCOVERY_PORT = 7778
const LAN_DISCOVERY_GROUP = "239.255.42.99"
const LAN_DISCOVERY_MSG = "HOST:%s:%d"
var udp_socket := PacketPeerUDP.new()
var udp_broadcaster := PacketPeerUDP.new() # Socket dedicado para anunciar la partida
var broadcast_timer := Timer.new() # Timer para el anuncio
var discovered_servers := {}

signal server_discovered(ip)
signal game_started
signal level_is_ready

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

func create_server(port: int = GAME_PORT):
	# Limpia cualquier conexión de red anterior para evitar conflictos de puerto.
	if get_tree().network_peer:
		get_tree().network_peer.close_connection()
		get_tree().network_peer = null

	var peer = NetworkedMultiplayerENet.new()
	var result = peer.create_server(port)
	if result != OK:
		print("[MultiplayerManager] ERROR: No se pudo crear el servidor ENet en el puerto %d (código %d)" % [port, result])
		return
	get_tree().network_peer = peer
	is_server = true
	is_client = false
	self.server_port = port

	_start_lan_broadcast(port)

func join_server(ip: String, port: int = GAME_PORT):
	var peer = NetworkedMultiplayerENet.new()
	peer.create_client(ip, port)
	get_tree().network_peer = peer
	is_server = false
	is_client = true

# --- Game Management ---

func start_game(level_path: String = "res://scenes/levels/act1/Level1.tscn"):
	emit_signal("game_started")
	current_level_path = level_path
	level_ready = false
	if not get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().connect("node_added", self, "_on_node_added")
	get_tree().change_scene(level_path)

remotesync func _spawn_player(id):
	if not level_ready:
		print("[MultiplayerManager] Nivel no listo. Esperando para instanciar jugador %s..." % id)
		yield(self, "level_is_ready")

	print("[MultiplayerManager] Nivel listo. Instanciando jugador %s." % id)
	var player = network_player_scene.instance()
	player.name = str(id)
	player.set_network_master(id) # Cada jugador es dueño de su propio nodo.
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
		emit_signal("level_is_ready")

# --- Signal Handlers ---

func _on_player_connected(id):
	print("Player connected: ", id)

	# Don't spawn players if the game hasn't started yet (i.e. we are in the lobby).
	# They will all be spawned later when the host actually starts the game.
	if current_level_path == "":
		print("[MultiplayerManager] Player %d connected in lobby. Spawning will occur on game start." % id)
		return

	# --- The code below is for handling players who join a game that is already in progress ---

	# Tell the new player about all existing players
	for player_id in players:
		rpc_id(id, "_spawn_player", player_id)

	# Spawn the new player on the server and all clients
	rpc("_spawn_player", id)

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
	var port = LAN_DISCOVERY_PORT
	var max_port_attempts = 10
	var listen_success = false
	for i in range(max_port_attempts):
		var current_port = port + i
		var result = udp_socket.listen(current_port)
		if result == OK:
			print("[MultiplayerManager] Escuchando para discovery en el puerto %d" % current_port)
			listen_success = true
			break
		elif result == ERR_ALREADY_IN_USE:
			print("[MultiplayerManager] Puerto de discovery %d en uso, probando el siguiente." % current_port)
		else:
			print("[MultiplayerManager] Error inesperado al escuchar en el puerto %d (código %d)" % [current_port, result])
			break # Salir en caso de otros errores

	if not listen_success:
		print("[MultiplayerManager] ERROR: No se pudo encontrar un puerto libre para LAN discovery después de %d intentos." % max_port_attempts)
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
	# Usamos el socket de broadcast para enviar, no el de escucha.
	# No es necesario que el broadcaster escuche en ningún puerto.
	udp_broadcaster.set_dest_address(LAN_DISCOVERY_GROUP, LAN_DISCOVERY_PORT)
	udp_broadcaster.put_packet(msg.to_utf8())

func stop_lan_broadcast():
	broadcast_timer.stop()
	udp_broadcaster.close()

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		# Asegurarse de cerrar todos los sockets al salir
		stop_lan_discovery()
		stop_lan_broadcast()
