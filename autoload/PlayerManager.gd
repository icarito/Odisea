extends Node

var player_scene := preload("res://players/elias/Pilot.tscn")
var player: Node = null

func is_spawned() -> bool:
	return player != null and is_instance_valid(player)

func spawn(initial_transform: Transform = Transform()) -> Node:
	if is_spawned():
		return player
	player = player_scene.instance()
	# Defer child addition until scene is ready to avoid 'Parent node is busy' error
	call_deferred("_deferred_spawn", initial_transform)
	return player

func _deferred_spawn(initial_transform: Transform):
	if not is_instance_valid(player):
		player = player_scene.instance()
	var scene = get_tree().get_current_scene()
	if scene:
		scene.add_child(player)
		# No establecer owner manualmente; al estar bajo la escena, es válido.
	else:
		get_tree().get_root().add_child(player)
	player.global_transform = initial_transform

func despawn():
	if is_spawned():
		player.queue_free()
		player = null

func get_player() -> Node:
	return player
