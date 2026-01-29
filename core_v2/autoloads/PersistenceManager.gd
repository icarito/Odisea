extends Node

# Guarda y carga CheckpointResource por escena
var checkpoint_resource: Resource = null

func _ready():
	pass # Autoload, inicialización si es necesario

func get_checkpoint_resource(scene_path: String) -> Resource:
	# Carga o crea el recurso de checkpoint para la escena
	var our_hash = hash_scene_path(scene_path)
	var save_path = "user://checkpoints/%s.tres" % our_hash
	if ResourceLoader.exists(save_path):
		checkpoint_resource = ResourceLoader.load(save_path)
	else:
		checkpoint_resource = CheckpointResource.new()
	return checkpoint_resource

func save_checkpoint_resource(scene_path: String):
	if checkpoint_resource:
		var our_hash = hash_scene_path(scene_path)
		var dir = Directory.new()
		if not dir.dir_exists("user://checkpoints"):
			dir.make_dir_recursive("user://checkpoints")
		var save_path = "user://checkpoints/%s.tres" % our_hash
		var err = ResourceSaver.save(save_path, checkpoint_resource)
		if err != OK:
			print("[PersistenceManager] Error al guardar checkpoint en ", save_path, ": ", err)

func hash_scene_path(scene_path: String) -> String:
	# Simple hash, puede mejorarse
	return String(scene_path.md5_text())
