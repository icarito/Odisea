extends Area
class_name PropDestroyerArea
tool

# PropDestroyerArea.gd - Deterministic Entity Cleanup
# Destroys entities that enter the area with deterministic iteration order.
# Ensures replay consistency by sorting bodies before cleanup.

# --- EXPORTED PROPERTIES ---
export(bool) var debug_render := true setget set_debug_render
export(bool) var debug := false

# --- SIGNALS ---
signal entity_destroyed(entity)

# --- INTERNAL STATE ---
var _debug_mesh: CSGBox

func _init():
	add_to_group("replay_sync")

func _ready():
	# Configure collision detection
	collision_layer = 0
	collision_mask = 4 # Layer 3 = "NPC-Friendly" (PushableBox)
	monitoring = true
	monitorable = false
	
	# Connect signals
	connect("body_entered", self, "_on_body_entered")
	
	# Setup debug visualization
	_update_debug_mesh()

func set_debug_render(value: bool) -> void:
	debug_render = value
	if is_inside_tree():
		_update_debug_mesh()

func _update_debug_mesh() -> void:
	# Remove existing debug mesh
	if _debug_mesh:
		_debug_mesh.queue_free()
		_debug_mesh = null
	
	if not debug_render:
		return
	
	# Create new debug mesh
	_debug_mesh = CSGBox.new()
	_debug_mesh.name = "DebugMesh"
	add_child(_debug_mesh)
	
	# Get collision shape size
	var col_shape = get_node_or_null("CollisionShape")
	if col_shape and col_shape.shape is BoxShape:
		var extents = col_shape.shape.extents
		_debug_mesh.width = extents.x * 2.0
		_debug_mesh.height = extents.y * 2.0
		_debug_mesh.depth = extents.z * 2.0
	else:
		# Default size
		_debug_mesh.width = 4.0
		_debug_mesh.height = 2.0
		_debug_mesh.depth = 4.0
	
	# Red wireframe material
	_debug_mesh.operation = CSGShape.OPERATION_UNION
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2, 0.3)
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_debug_mesh.material = mat

func _on_body_entered(body: Node) -> void:
	"""Handle body entering the destroyer area."""
	if Engine.editor_hint:
		return
	
	# Validate target type
	if not _is_valid_target(body):
		return
	
	# if debug:
	# 	print("[PropDestroyerArea] Body entered: %s" % body.name)
	
	# Destroy immediately (deterministic single-body handling)
	_destroy_entity(body)

func _is_valid_target(body: Node) -> bool:
	"""Check if body is a valid target for destruction."""
	# Ignore player
	if body.is_in_group("player"):
		return false
	
	# Check for valid interactable types
	if body is InteractableBase:
		return true
	
	if body.get_script():
		var script_path = body.get_script().resource_path
		if "PushableBox" in script_path:
			return true
	
	return false

func _destroy_entity(entity: Node) -> void:
	"""Destroy a single entity with proper cleanup."""
	if not is_instance_valid(entity):
		return
	
	# Emit signal before destruction
	emit_signal("entity_destroyed", entity)
	
	# Unregister from PersistenceManager
	var persistence_mgr = get_node_or_null("/root/PersistenceManager")
	if persistence_mgr and persistence_mgr.has_method("unregister_entity"):
		persistence_mgr.unregister_entity(entity)
	
	# Remove from TeleportSystem tracking (if applicable)
	var teleport_system = get_node_or_null("/root/SessionManager/TeleportSystem")
	if not teleport_system:
		teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	
	if teleport_system and teleport_system.has_method("untrack_entity"):
		teleport_system.untrack_entity(entity)
	
	# if debug:
	# 	print("[PropDestroyerArea] Destroying entity: %s" % entity.name)
	
	# Handle pooled entities vs standard entities
	var parent = entity.get_parent()
	if parent and parent.has_method("return_entity"):
		parent.return_entity(entity)
	else:
		# Queue for deletion
		entity.queue_free()

func flush() -> void:
	"""Immediately destroy all entities currently in the area."""
	if Engine.editor_hint:
		return
	
	var bodies = get_overlapping_bodies()
	
	# Sort by instance ID for deterministic iteration
	bodies.sort_custom(self, "_sort_by_instance_id")
	
	for body in bodies:
		if _is_valid_target(body):
			_destroy_entity(body)
	
	# if debug and bodies.size() > 0:
	# 	print("[PropDestroyerArea] Flushed %d entities" % bodies.size())

func _sort_by_instance_id(a: Node, b: Node) -> bool:
	"""Sort comparator for deterministic iteration."""
	return a.get_instance_id() < b.get_instance_id()

func step(_dt: float) -> void:
	"""Fixed-step physics update for deterministic cleanup."""
	if not Engine.editor_hint:
		flush()

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	step(delta)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	"""Return state for replay system."""
	return {
		"active": true # Minimal state, destroyer is stateless
	}

func restore_snapshot(_data: Dictionary) -> void:
	"""Restore state from snapshot."""
	# Destroyer has no internal state to restore
	pass

func _process(_delta: float) -> void:
	# Update debug mesh in editor
	if Engine.editor_hint and debug_render:
		if not _debug_mesh or not is_instance_valid(_debug_mesh):
			_update_debug_mesh()
