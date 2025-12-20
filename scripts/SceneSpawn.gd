
extends Spatial

func _ready():
	print("[SceneSpawn] _ready called. GameGlobals.current_mode:", GameGlobals.current_mode)
	# En modo copilot, no spawnear automáticamente; lo hace LocalMultiplayerManager
	if GameGlobals.current_mode == GameGlobals.GAME_MODE.COPILOT:
		print("[SceneSpawn] COPILOT mode, skipping spawn")
		return
	# En test de determinismo, no spawnear; lo hace el test manualmente
	if GameGlobals.determinism_test:
		print("[SceneSpawn] Determinism test, skipping spawn")
		return

	var spawn := find_node("SpawnPoint")
	print("[SceneSpawn] Found spawn:", spawn)

	if spawn:
		if typeof(PlayerManager) != TYPE_NIL:
			print("[SceneSpawn] PlayerManager ref:", PlayerManager)
			if PlayerManager.is_spawned():
				print("[SceneSpawn] Player already spawned, relocating to spawn")
				var p = PlayerManager.get_player()
				print("[SceneSpawn] PlayerManager.get_player():", p)
				if is_instance_valid(p):
					p.global_transform = spawn.global_transform
					p.rotation.y = spawn.rotation.y
					print("[SceneSpawn] Player relocated to spawn")
				else:
					print("[SceneSpawn] Player not valid, spawning new")
					PlayerManager.spawn(spawn.global_transform)
			else:
				print("[SceneSpawn] Player not spawned, spawning new")
				PlayerManager.spawn(spawn.global_transform)
	else:
		print("[SceneSpawn] No spawn found, using origin")
		# fallback: spawn at origin
		if typeof(PlayerManager) != TYPE_NIL:
			print("[SceneSpawn] PlayerManager ref:", PlayerManager)
			if PlayerManager.is_spawned():
				print("[SceneSpawn] Player already spawned, relocating to origin")
				var p = PlayerManager.get_player()
				print("[SceneSpawn] PlayerManager.get_player():", p)
				if is_instance_valid(p):
					p.global_transform = global_transform
					p.rotation.y = spawn.rotation.y
					print("[SceneSpawn] Player relocated to origin")
				else:
					print("[SceneSpawn] Player not valid, spawning new")
					PlayerManager.spawn(global_transform)
			else:
				print("[SceneSpawn] Player not spawned, spawning new")
				PlayerManager.spawn(global_transform)

	# (Conexión de señales movida a KillZone._ready)
