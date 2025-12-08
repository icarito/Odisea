
extends Spatial

func _ready():
	# En modo copilot, no spawnear automáticamente; lo hace LocalMultiplayerManager
	if GameGlobals.current_mode == GameGlobals.GAME_MODE.COPILOT:
		return
	
	var spawn := get_node_or_null("SpawnPoint")
	if spawn:
		if typeof(PlayerManager) != TYPE_NIL:
			if PlayerManager.is_spawned():
				# Reubicar jugador existente al nuevo spawn
				var p = PlayerManager.get_player()
				if is_instance_valid(p):
					p.global_transform = spawn.global_transform
					p.rotation.z = spawn.rotation.z
				else:
					PlayerManager.spawn(spawn.global_transform)
			else:
				PlayerManager.spawn(spawn.global_transform)
	else:
		# fallback: spawn at origin
		if typeof(PlayerManager) != TYPE_NIL:
			if PlayerManager.is_spawned():
				var p = PlayerManager.get_player()
				if is_instance_valid(p):
					p.global_transform = global_transform
					p.rotation.z = spawn.rotation.z
				else:
					PlayerManager.spawn(global_transform)
			else:
				PlayerManager.spawn(global_transform)

	# Conectar señales de KillZone solo en modo single player
	if GameGlobals.current_mode != GameGlobals.GAME_MODE.COPILOT:
		var kill_zone = get_node_or_null("KillZone")
		if kill_zone:
			kill_zone.connect("player_killed", PlayerManager, "kill_player_instant")
			kill_zone.connect("player_respawn_requested", PlayerManager, "respawn_player")
