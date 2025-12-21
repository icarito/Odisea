extends SceneTree

# CLI Replay Loader/Player: scripts/replay/ReplayCliPlayer.gd
# Uso:
# Playback: godot3-bin --path . --script scripts/replay/ReplayCliPlayer.gd --replay path/to/replay.json
# Record: godot3-bin --path . --script scripts/replay/ReplayCliPlayer.gd --record --name my_replay --duration 30

func _init():
	var args = OS.get_cmdline_args()
	var replay_path = ""
	var record = false
	var name = "cli_replay"
	var duration = 10.0  # seconds
	
	var i = 0
	while i < args.size():
		if args[i] == "--replay" and i+1 < args.size():
			replay_path = args[i+1]
			i += 2
		elif args[i] == "--record":
			record = true
			i += 1
		elif args[i] == "--name" and i+1 < args.size():
			name = args[i+1]
			i += 2
		elif args[i] == "--duration" and i+1 < args.size():
			duration = float(args[i+1])
			i += 2
		else:
			i += 1
	
	if record:
		print("[ReplayCliPlayer] Recording mode: name=", name, " duration=", duration)
		_record_replay(name, duration)
	else:
		if replay_path == "":
			printerr("[ReplayCliPlayer] Debes pasar --replay path/al/replay.json o --record")
			quit(1)
		print("[ReplayCliPlayer] Playback mode: replay=", replay_path)
		_play_replay(replay_path)

func _record_replay(name: String, duration: float):
	var scene = load("res://tests/fixtures/TestScene.tscn")
	if not scene:
		printerr("[ReplayCliPlayer] No se pudo cargar TestScene.tscn")
		quit(4)
	var root = scene.instance()
	get_root().add_child(root)
	
	# Add player
	var spawn_point = root.find_node("SpawnPoint", true, false)
	if spawn_point:
		var player_scene = load("res://players/elias/Pilot.tscn").instance()
		root.add_child(player_scene)
		player_scene.global_transform = spawn_point.global_transform
		PlayerManager.player_reference = player_scene
	
	# Add ReplayManager
	var ReplayManager = load("res://scripts/replay/ReplayManager.gd").new()
	ReplayManager.name = "ReplayManager"
	root.add_child(ReplayManager)
	
	# Set custom name and dir
	ReplayManager.recorder.REPLAYS_DIR = "res://tests/replays/"
	ReplayManager.recorder.current_replay_name = name
	
	# Start recording
	ReplayManager.start_recording()
	
	# Wait duration
	var start_time = OS.get_ticks_msec()
	while (OS.get_ticks_msec() - start_time) < duration * 1000:
		OS.delay_msec(100)
		# Simulate random input
		InputState.actions["move_forward"] = randi() % 2 == 0
		InputState.axes["move_x"] = rand_range(-1, 1)
		# Process
		ReplayManager.recorder._physics_process(1.0/60.0)
	
	# Stop
	ReplayManager.stop_recording()
	print("[ReplayCliPlayer] Recording saved to: ", ReplayManager.last_replay_path)
	quit(0)

func _play_replay(replay_path: String):
	print("[ReplayCliPlayer] Cargando replay: ", replay_path)
	var file = File.new()
	if file.open(replay_path, File.READ) != OK:
		printerr("[ReplayCliPlayer] No se pudo abrir el archivo: ", replay_path)
		quit(2)
	var data = parse_json(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("scene_path"):
		printerr("[ReplayCliPlayer] El replay no contiene 'scene_path'.")
		quit(3)
	var scene_path = data["scene_path"]
	print("[ReplayCliPlayer] Cargando escena: ", scene_path)
	var scene = load(scene_path)
	if not scene:
		printerr("[ReplayCliPlayer] No se pudo cargar la escena: ", scene_path)
		quit(4)
	var root = scene.instance()
	get_root().add_child(root)

	# Instanciar Player en el SpawnPoint
	var spawn_point = root.find_node("SpawnPoint", true, false)
	if spawn_point:
		var player_scene = load("res://players/elias/Pilot.tscn").instance()
		root.add_child(player_scene)
		player_scene.global_transform = spawn_point.global_transform
		PlayerManager.player_reference = player_scene
		print("[ReplayCliPlayer] Player instanciado en: ", player_scene.global_transform.origin)
	else:
		printerr("[ReplayCliPlayer] No se encontró SpawnPoint en la escena.")

	# Cargar y reproducir el replay usando ReplayManager
	var ReplayManager = load("res://scripts/replay/ReplayManager.gd").new()
	ReplayManager.name = "ReplayManager"
	root.add_child(ReplayManager)
	if ReplayManager.has_node("ReplayRecorder"):
		ReplayManager.get_node("ReplayRecorder").player = player_scene
	# Esperar a que la escena esté lista
	yield(root, "ready")
	# Llamar a start_playback con el path del replay
	if ReplayManager.has_method("start_playback"):
		ReplayManager.start_playback(replay_path)
	else:
		printerr("[ReplayCliPlayer] ReplayManager no tiene método start_playback.")
		quit(5)
	print("[ReplayCliPlayer] Reproducción iniciada. Presiona Ctrl+C para salir.")
	# Mantener el proceso vivo para que el playback corra
	while true:
		OS.delay_msec(1000)
		print("[ReplayCliPlayer] Running...")
