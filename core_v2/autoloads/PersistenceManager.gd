extends Node

# Guarda y carga CheckpointResource por escena
const CheckpointResource = preload("res://core_v2/systems/CheckpointResource.gd")
const DEFAULT_CHECKPOINT_DIRECTORY := "user://checkpoints"
var checkpoint_resource: Resource = null
var _continue_requested := false
var checkpoint_directory := DEFAULT_CHECKPOINT_DIRECTORY

# Entity registration for dynamic prop lifecycle
var registered_entities := {} # Maps instance_id to NodePath

# Cache for scene hashes to avoid repeated disk I/O
var _scene_hash_cache: Dictionary = {}

signal entity_registered(entity)
signal entity_unregistered(entity)

func _ready():
	pass # Autoload, inicialización si es necesario

func register_entity(entity: Node) -> void:
	"""Register a dynamically spawned entity for tracking."""
	if not is_instance_valid(entity):
		return
	
	var id = entity.get_instance_id()
	if not registered_entities.has(id):
		registered_entities[id] = entity.get_path()
		emit_signal("entity_registered", entity)

func unregister_entity(entity: Node) -> void:
	"""Unregister an entity when it's destroyed."""
	if not is_instance_valid(entity):
		return
	
	var id = entity.get_instance_id()
	if registered_entities.has(id):
		registered_entities.erase(id)
		emit_signal("entity_unregistered", entity)

func get_registered_entities() -> Array:
	"""Get all currently registered entities."""
	var entities = []
	for id in registered_entities.keys():
		var entity = instance_from_id(id)
		if is_instance_valid(entity):
			entities.append(entity)
		else:
			# Clean up invalid references
			registered_entities.erase(id)
	return entities

func get_checkpoint_resource(scene_path: String) -> Resource:
	# Carga o crea el recurso de checkpoint para la escena
	var our_hash = hash_scene_path(scene_path)
	var save_path := "%s/%s.tres" % [checkpoint_directory, our_hash]
	if ResourceLoader.exists(save_path):
		checkpoint_resource = ResourceLoader.load(save_path)
	else:
		checkpoint_resource = CheckpointResource.new()
		checkpoint_resource.slots = {}
	return checkpoint_resource

func save_checkpoint_resource(scene_path: String):
	if checkpoint_resource:
		var our_hash = hash_scene_path(scene_path)
		var dir = Directory.new()
		if not dir.dir_exists(checkpoint_directory):
			dir.make_dir_recursive(checkpoint_directory)
		var save_path := "%s/%s.tres" % [checkpoint_directory, our_hash]
		var err = ResourceSaver.save(save_path, checkpoint_resource)
		if err != OK:
			print("[PersistenceManager] Error al guardar checkpoint en ", save_path, ": ", err)
		elif "last" in checkpoint_resource.slots:
			_write_continue_index(scene_path, save_path)

func get_continue_scene_path() -> String:
	var config := ConfigFile.new()
	if config.load(_get_continue_index_path()) != OK:
		return ""
	var scene_path := String(config.get_value("checkpoint", "scene_path", ""))
	var save_path := String(config.get_value("checkpoint", "save_path", ""))
	if scene_path == "" or save_path == "":
		return ""
	var file := File.new()
	if not file.file_exists(scene_path) or not ResourceLoader.exists(save_path):
		return ""
	var resource = ResourceLoader.load(save_path)
	if resource == null or not ("slots" in resource) or not ("last" in resource.slots):
		return ""
	return scene_path

func request_continue() -> bool:
	_continue_requested = get_continue_scene_path() != ""
	return _continue_requested

func consume_continue_checkpoint(scene_path: String):
	if not _continue_requested or scene_path != get_continue_scene_path():
		return null
	_continue_requested = false
	var resource = get_checkpoint_resource(scene_path)
	return resource.slots.get("last", null) if resource else null

func _write_continue_index(scene_path: String, save_path: String) -> void:
	var config := ConfigFile.new()
	config.set_value("checkpoint", "scene_path", scene_path)
	config.set_value("checkpoint", "save_path", save_path)
	var err := config.save(_get_continue_index_path())
	if err != OK:
		push_warning("[PersistenceManager] No se pudo actualizar el índice de Continuar (%d)." % err)

func _get_continue_index_path() -> String:
	return "%s/continue.cfg" % checkpoint_directory

func hash_scene_path(scene_path: String) -> String:
	# Return cached hash if available
	if _scene_hash_cache.has(scene_path):
		return _scene_hash_cache[scene_path]

	# Use file content MD5 to invalidate checkpoints on level change
	var final_hash: String
	var file = File.new()
	if file.file_exists(scene_path):
		var md5 = file.get_md5(scene_path)
		if md5.empty():
			# Fallback if MD5 fails (e.g. empty file or access issue)
			final_hash = String(scene_path.md5_text())
		else:
			final_hash = md5
	else:
		# Fallback for non-existent files (e.g. dynamic/unsaved scenes)
		final_hash = String(scene_path.md5_text())

	# Cache the result
	_scene_hash_cache[scene_path] = final_hash
	return final_hash
