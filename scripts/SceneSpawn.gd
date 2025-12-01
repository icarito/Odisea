extends Spatial

func _ready():
	var spawn := get_node_or_null("SpawnPoint")
	if spawn:
		if typeof(PlayerManager) != TYPE_NIL:
			if PlayerManager.is_spawned():
				# Reubicar jugador existente al nuevo spawn
				var p = PlayerManager.get_player()
				if is_instance_valid(p):
					p.global_transform = spawn.global_transform
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
				else:
					PlayerManager.spawn(global_transform)
			else:
				PlayerManager.spawn(global_transform)
