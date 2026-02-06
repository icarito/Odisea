extends Area
class_name PropEmitterArea
tool

# PropEmitterArea.gd - Deterministic Entity Spawner
# Spawns entities within a defined volume using object pooling and seeded RNG.
# Ensures replay determinism by pre-instantiating all entities at _ready().

# --- EXPORTED PROPERTIES ---
export(PackedScene) var prop_scene: PackedScene setget set_prop_scene
export(int) var spawn_limit := 10 setget set_spawn_limit
export(float) var emission_rate := 1.0 # Entities per second
export(int) var random_seed := 0 # 0 = use SessionManager seed
export(Vector3) var spawn_offset_range := Vector3(1, 0.5, 1)
export(bool) var debug_render := true setget set_debug_render
export(bool) var debug := false

# --- SIGNALS ---
signal entity_spawned(entity)

# --- INTERNAL STATE ---
var _object_pool := []
var _active_entities := []
var _spawn_timer := 0.0
var _rng: RandomNumberGenerator
var _debug_mesh: CSGBox

func _init():
	add_to_group("replay_sync")

func _ready():
	# Initialize RNG with seed
	_rng = RandomNumberGenerator.new()
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		# Get seed from SessionManager if available
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr and "random_seed" in session_mgr:
			_rng.seed = session_mgr.random_seed
		else:
			_rng.seed = 12345 # Fallback deterministic seed
	
	# Setup debug visualization
	_update_debug_mesh()
	
	# Pre-instantiate object pool (only in game mode)
	if not Engine.editor_hint and prop_scene:
		_initialize_object_pool()

func set_prop_scene(scene: PackedScene) -> void:
	prop_scene = scene
	if Engine.editor_hint:
		property_list_changed_notify()

func set_spawn_limit(limit: int) -> void:
	spawn_limit = max(1, limit)

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
	
	# Green wireframe material
	_debug_mesh.operation = CSGShape.OPERATION_UNION
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(0.2, 1.0, 0.2, 0.3)
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_debug_mesh.material = mat

func _initialize_object_pool() -> void:
	"""Pre-instantiate all entities to prevent runtime allocation."""
	if not prop_scene:
		if debug:
			printerr("[PropEmitterArea] No prop_scene assigned!")
		return
	
	for i in range(spawn_limit):
		var entity = prop_scene.instance()
		entity.name = "%s_Pooled_%d" % [name, i]
		
		# Add to pool in inactive state
		_object_pool.append(entity)
		
		# Add to tree but hide and disable
		add_child(entity)
		_deactivate_entity(entity)
	
	# if debug:
	# 	print("[PropEmitterArea] Initialized object pool with %d entities" % spawn_limit)

func _deactivate_entity(entity: Node) -> void:
	"""Deactivate entity and return to pool."""
	if entity is Spatial:
		entity.visible = false
	if entity is CollisionObject:
		entity.set_deferred("monitoring", false)
		entity.set_deferred("monitorable", false)
	if entity is PhysicsBody:
		entity.set_deferred("mode", RigidBody.MODE_STATIC if entity is RigidBody else entity.mode)
	
	# Move far away to prevent physics interactions
	if entity is Spatial:
		entity.global_transform.origin = Vector3(0, -10000, 0)

func _activate_entity(entity: Node) -> void:
	"""Activate entity from pool."""
	if entity is Spatial:
		entity.visible = true
	if entity is CollisionObject:
		entity.set_deferred("monitoring", true)
		entity.set_deferred("monitorable", true)
	if entity is RigidBody:
		entity.set_deferred("mode", RigidBody.MODE_RIGID)
		entity.sleeping = false

func spawn_entity() -> Node:
	"""Spawn an entity from the pool at a random position within the area."""
	if _object_pool.empty():
		if debug:
			print("[PropEmitterArea] Object pool exhausted, cannot spawn more entities")
		return null
	
	# Get entity from pool
	var entity = _object_pool.pop_front()
	
	# Calculate spawn position
	var spawn_pos = _get_random_spawn_position()
	
	# Position and activate entity
	if entity is Spatial:
		entity.global_transform.origin = spawn_pos
		
		# Reset rotation if RigidBody
		if entity is RigidBody:
			entity.global_transform.basis = Basis.IDENTITY
			entity.linear_velocity = Vector3.ZERO
			entity.angular_velocity = Vector3.ZERO
	
	_activate_entity(entity)
	_active_entities.append(entity)
	
	# Register with PersistenceManager
	var persistence_mgr = get_node_or_null("/root/PersistenceManager")
	if persistence_mgr and persistence_mgr.has_method("register_entity"):
		persistence_mgr.register_entity(entity)
	
	emit_signal("entity_spawned", entity)
	
	# if debug:
	# 	print("[PropEmitterArea] Spawned entity at %s" % spawn_pos)
	
	return entity

func _get_random_spawn_position() -> Vector3:
	"""Calculate random position within area bounds."""
	var offset = Vector3(
		_rng.randf_range(-spawn_offset_range.x, spawn_offset_range.x),
		_rng.randf_range(-spawn_offset_range.y, spawn_offset_range.y),
		_rng.randf_range(-spawn_offset_range.z, spawn_offset_range.z)
	)
	return global_transform.origin + offset

func reset() -> void:
	"""Clear all spawned entities and reset pool (for replay state cleanup)."""
	# Deactivate all active entities
	for entity in _active_entities:
		if is_instance_valid(entity):
			_deactivate_entity(entity)
			_object_pool.append(entity)
			
			# Unregister from PersistenceManager
			var persistence_mgr = get_node_or_null("/root/PersistenceManager")
			if persistence_mgr and persistence_mgr.has_method("unregister_entity"):
				persistence_mgr.unregister_entity(entity)
	
	_active_entities.clear()
	_spawn_timer = 0.0
	
	# if debug:
	# 	print("[PropEmitterArea] Reset complete, pool size: %d" % _object_pool.size())

func return_entity(entity: Node) -> void:
	"""Return an entity to the pool and deactivate it."""
	if not is_instance_valid(entity):
		return
		
	if entity in _active_entities:
		_active_entities.erase(entity)
		_deactivate_entity(entity)
		_object_pool.append(entity)
		
		# Unregister from PersistenceManager
		var persistence_mgr = get_node_or_null("/root/PersistenceManager")
		if persistence_mgr and persistence_mgr.has_method("unregister_entity"):
			persistence_mgr.unregister_entity(entity)
			
		# if debug:
		# 	print("[PropEmitterArea] Entity returned to pool: %s" % entity.name)
	else:
		# if debug:
		# 	print("[PropEmitterArea] Entity %s not found in active list, calling queue_free" % entity.name)
		entity.queue_free()

func step(dt: float) -> void:
	"""Fixed-step physics update for deterministic spawning."""
	if Engine.editor_hint:
		return
	
	if _active_entities.size() >= spawn_limit:
		return
	
	_spawn_timer += dt
	var spawn_interval = 1.0 / emission_rate if emission_rate > 0 else 999999.0
	
	if _spawn_timer >= spawn_interval:
		spawn_entity()
		_spawn_timer = 0.0

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	step(delta)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	"""Return state for replay system."""
	return {
		"spawn_timer": _spawn_timer,
		"active_count": _active_entities.size(),
		"rng_state": _rng.state
	}

func restore_snapshot(data: Dictionary) -> void:
	"""Restore state from snapshot."""
	if Engine.editor_hint:
		return
	
	if data.has("spawn_timer"):
		_spawn_timer = data["spawn_timer"]
	
	if data.has("rng_state"):
		_rng.state = data["rng_state"]
	
	# Note: Active entities are managed by their own snapshots
	# This just restores the emitter's internal state

func _process(_delta: float) -> void:
	# Update debug mesh in editor
	if Engine.editor_hint and debug_render:
		if not _debug_mesh or not is_instance_valid(_debug_mesh):
			_update_debug_mesh()
