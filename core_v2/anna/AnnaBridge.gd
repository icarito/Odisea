extends Node

const PORT = 5000
var _server: TCP_Server
var _peers := []
var _interface: Node
var _peer_buffers := {} # { peer_instance_id: String }

func _ready():
	_interface = preload("res://core_v2/anna/AnnaInterface.gd").new()
	add_child(_interface)

	_server = TCP_Server.new()
	var port_str = OS.get_environment("ANNA_PORT")
	var port = PORT
	if port_str.is_valid_integer():
		port = int(port_str)

	var err = _server.listen(port)
	if err != OK:
		print("[ANNA] Failed to listen on port %d" % port)
	else:
		print("[ANNA] Listening on port %d" % port)

func _physics_process(_delta):
	if _server.is_connection_available():
		var peer = _server.take_connection()
		_peers.append(peer)
		print("[ANNA] Client connected: %s" % peer.get_connected_host())

	# Process peers
	var active_peers = []
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_handle_peer(peer)
			active_peers.append(peer)
		else:
			print("[ANNA] Client disconnected")
			var pid = peer.get_instance_id()
			if _peer_buffers.has(pid):
				_peer_buffers.erase(pid)
	_peers = active_peers

func _handle_peer(peer: StreamPeerTCP):
	# Send Observation
	var obs = _interface.get_observation()
	var json_str = JSON.print(obs)
	# Append newline for delimiter
	peer.put_utf8_string(json_str + "\n")

	# Receive Action (Buffering)
	var bytes = peer.get_available_bytes()
	if bytes > 0:
		var chunk = peer.get_utf8_string(bytes)
		var pid = peer.get_instance_id()

		if not _peer_buffers.has(pid):
			_peer_buffers[pid] = ""
		_peer_buffers[pid] += chunk

		# Process complete lines
		while "\n" in _peer_buffers[pid]:
			var parts = _peer_buffers[pid].split("\n", true, 1) # Split at first newline
			var line = parts[0]
			_peer_buffers[pid] = parts[1] # Remainder

			if line.strip_edges() != "":
				var parse = JSON.parse(line)
				if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
					_interface.apply_action(parse.result)
				else:
					print("[ANNA] Malformed JSON action received: ", line.substr(0, 50))
