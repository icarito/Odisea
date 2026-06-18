extends Area
class_name GasArea3D

const GasParticleManagerScript = preload("res://core_v2/systems/gas/GasParticleManager.gd")

signal gas_ignited(pos, rad)

enum GasType { TOXIC, FLAMMABLE, STEAM }

export(int, "Toxic", "Flammable", "Steam") var gas_type := GasType.TOXIC setget set_gas_type
export(float) var viscosity := 0.8
export(float) var buoyancy := -1.2
export(float) var decay_rate := 1.0
export(bool) var is_flammable := false
export(float) var player_push_force := 15.0
export(float) var damage_per_second := 20.0
export(int) var grid_resolution := 32 setget set_grid_resolution
export(float) var dense_damage_threshold := 1.0
export(float) var min_combustion_density := 0.6
export(float) var combustion_radius := 1.6
export(float) var combustion_damage_radius := 2.0
export(int) var initial_particle_count := 128
export(float) var initial_fill_radius := 0.85
export(float) var initial_vertical_fill := 0.45
export(float) var initial_particle_scale := 3.0
export(float) var initial_particle_lifetime := 60.0
export(bool) var gas_collide_with_world := true
export(int, LAYERS_3D_PHYSICS) var gas_world_collision_mask := 1
export(bool) var initial_respect_world_collision := true

var manager = null

var _grid: Array = []
var _cell_particles: Array = []
var _burning_cells: Dictionary = {}
var _bodies_inside: Dictionary = {}
var _collision_shape: CollisionShape = null

func _ready():
	_resolve_collision_shape()
	_ensure_manager()
	_ensure_grid()
	_connect_signals()
	_apply_manager_tuning()
	call_deferred("_populate_initial_gas")

func set_gas_type(value: int) -> void:
	gas_type = value
	if gas_type == GasType.FLAMMABLE:
		is_flammable = true

func set_grid_resolution(value: int) -> void:
	grid_resolution = int(clamp(value, 4, 128))
	if is_inside_tree():
		_ensure_grid()

func _resolve_collision_shape() -> void:
	_collision_shape = get_node_or_null("CollisionShape")
	if _collision_shape == null:
		for child in get_children():
			if child is CollisionShape:
				_collision_shape = child
				break

func _ensure_manager() -> void:
	for child in get_children():
		if child.get_script() == GasParticleManagerScript:
			manager = child
			break

	if manager == null:
		manager = GasParticleManagerScript.new()
		manager.name = "GasParticleManager"
		add_child(manager)

func _connect_signals() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	if not is_connected("body_exited", self, "_on_body_exited"):
		connect("body_exited", self, "_on_body_exited")

func _ensure_grid() -> void:
	grid_resolution = int(clamp(grid_resolution, 4, 128))
	var cell_count := grid_resolution * grid_resolution
	_grid.clear()
	_cell_particles.clear()
	for _i in range(cell_count):
		_grid.append({
			"density": 0.0,
			"temperature": 0.0,
			"en_combustion": false
		})
		_cell_particles.append([])

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	if manager == null:
		return

	_apply_manager_tuning()
	_update_body_velocities(delta)
	_rebuild_density_grid()
	_apply_body_push(delta)
	_apply_player_damage(delta)
	if is_flammable:
		_update_combustion(delta)

func _apply_manager_tuning() -> void:
	if manager == null:
		return
	manager.viscosity = viscosity
	manager.buoyancy = buoyancy
	manager.decay_rate = decay_rate
	manager.collide_with_world = gas_collide_with_world
	manager.world_collision_mask = gas_world_collision_mask
	# Pass volume radius so manager can normalize particle distances
	var extents := _get_shape_extents()
	manager.volume_radius = max(extents.x, max(extents.y, extents.z))

func _clear_grid() -> void:
	for i in range(_grid.size()):
		var cell: Dictionary = _grid[i]
		cell["density"] = 0.0
		cell["temperature"] = 0.0
		cell["en_combustion"] = _burning_cells.has(i)
		_grid[i] = cell
		_cell_particles[i].clear()

func _rebuild_density_grid() -> void:
	_clear_grid()

	for i in range(manager.particles.size()):
		var particle: Dictionary = manager.particles[i]
		if not bool(particle["active"]):
			continue

		var world_pos: Vector3 = manager.global_transform.xform(Vector3(particle["position"]))
		var cell_index := _world_position_to_cell_index(world_pos)
		if cell_index < 0:
			continue

		var cell: Dictionary = _grid[cell_index]
		cell["density"] = float(cell["density"]) + 1.0
		if bool(particle["combustion"]):
			cell["temperature"] = max(float(cell["temperature"]), 1.0)
		_grid[cell_index] = cell
		_cell_particles[cell_index].append(i)

func _world_position_to_cell_index(world_pos: Vector3) -> int:
	var shape_pos := _world_to_shape_local(world_pos)
	var extents := _get_shape_extents()
	if extents.x <= 0.001 or extents.z <= 0.001:
		return -1

	var nx := (shape_pos.x / extents.x + 1.0) * 0.5
	var nz := ((-shape_pos.z) / extents.z + 1.0) * 0.5
	if nx < 0.0 or nx > 1.0 or nz < 0.0 or nz > 1.0:
		return -1

	var gx := int(clamp(floor(nx * float(grid_resolution)), 0.0, float(grid_resolution - 1)))
	var gz := int(clamp(floor(nz * float(grid_resolution)), 0.0, float(grid_resolution - 1)))
	return _cell_index(gx, gz)

func _world_to_shape_local(world_pos: Vector3) -> Vector3:
	if _collision_shape:
		return _collision_shape.to_local(world_pos)
	return to_local(world_pos)

func _get_shape_extents() -> Vector3:
	if _collision_shape and _collision_shape.shape is BoxShape:
		return (_collision_shape.shape as BoxShape).extents
	if _collision_shape and _collision_shape.shape is CapsuleShape:
		var capsule := _collision_shape.shape as CapsuleShape
		return Vector3(capsule.radius, capsule.height * 0.5 + capsule.radius, capsule.radius)
	if _collision_shape and _collision_shape.shape is SphereShape:
		var sphere := _collision_shape.shape as SphereShape
		return Vector3(sphere.radius, sphere.radius, sphere.radius)
	return Vector3(4.0, 2.0, 4.0)

func _populate_initial_gas() -> void:
	if manager == null or initial_particle_count <= 0:
		return
	if manager.get_active_particle_indices().size() > 0:
		return

	if initial_particle_count > manager.pool_size:
		manager.pool_size = initial_particle_count
		manager._ensure_multimesh_instance()
		manager._setup_pool()

	var extents := _get_shape_extents()
	var count := int(min(initial_particle_count, manager.pool_size))
	var fill_x := clamp(initial_fill_radius, 0.05, 5.0)
	var fill_y := clamp(initial_vertical_fill, 0.05, 5.0)
	var fill_z := fill_x

	for i in range(count):
		var u_x := fmod(float(i) * 0.7548776662466927, 1.0)
		var u_y := fmod(float(i) * 0.5698402909980532, 1.0)
		var u_z := fmod(float(i) * 0.4323369283944646, 1.0)

		# Add deterministic noise (jitter) to break the grid regularity
		var jitter_x := (float((i * 1103515245 + 12345) & 0x7fffffff) / float(0x7fffffff) - 0.5) * 0.3
		var jitter_y := (float((i * 214013 + 2531011) & 0x7fffffff) / float(0x7fffffff) - 0.5) * 0.3
		var jitter_z := (float((i * 1664525 + 1013904223) & 0x7fffffff) / float(0x7fffffff) - 0.5) * 0.3

		var shape_pos := Vector3(
			(clamp(u_x + jitter_x, 0.0, 1.0) - 0.5) * 2.0 * extents.x * fill_x,
			(clamp(u_y + jitter_y, 0.0, 1.0) - 0.5) * 2.0 * extents.y * fill_y,
			(clamp(u_z + jitter_z, 0.0, 1.0) - 0.5) * 2.0 * extents.z * fill_z
		)
		var world_pos: Vector3 = _shape_local_to_world(shape_pos)
		if initial_respect_world_collision and _is_world_point_blocked(world_pos):
			continue
		var manager_pos: Vector3 = manager.to_local(world_pos)
		manager.emit_particle(manager_pos, Vector3.ZERO, initial_particle_lifetime, initial_particle_scale)

func _shape_local_to_world(local_pos: Vector3) -> Vector3:
	if _collision_shape:
		return _collision_shape.global_transform.xform(local_pos)
	return global_transform.xform(local_pos)

func _is_world_point_blocked(world_pos: Vector3) -> bool:
	var space_state = get_world().direct_space_state
	var hits: Array = space_state.intersect_point(world_pos, 1, [], gas_world_collision_mask, true, false)
	return hits.size() > 0

func _cell_index(x: int, z: int) -> int:
	return z * grid_resolution + x

func _cell_coords(index: int) -> Vector2:
	return Vector2(index % grid_resolution, int(index / grid_resolution))

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	var id: int = body.get_instance_id()
	var pos: Vector3 = body.global_transform.origin if body is Spatial else Vector3.ZERO
	_bodies_inside[id] = {
		"body": body,
		"last_position": pos,
		"velocity": Vector3.ZERO
	}

func _on_body_exited(body: Node) -> void:
	if body == null:
		return
	_bodies_inside.erase(body.get_instance_id())

func _update_body_velocities(delta: float) -> void:
	var remove_ids := []
	for id in _bodies_inside.keys():
		var info: Dictionary = _bodies_inside[id]
		var body = info.get("body", null)
		if not is_instance_valid(body):
			remove_ids.append(id)
			continue
		if not body is Spatial:
			continue

		var current_pos: Vector3 = body.global_transform.origin
		var velocity := Vector3.ZERO
		if body is RigidBody:
			velocity = body.linear_velocity
		elif delta > 0.0:
			velocity = (current_pos - Vector3(info["last_position"])) / delta

		info["velocity"] = velocity
		info["last_position"] = current_pos
		_bodies_inside[id] = info

	for id in remove_ids:
		_bodies_inside.erase(id)

func _apply_body_push(delta: float) -> void:
	var radius := max(player_push_force, 0.001)
	for id in _bodies_inside.keys():
		var info: Dictionary = _bodies_inside[id]
		var body = info.get("body", null)
		if not is_instance_valid(body) or not body is Spatial:
			continue

		var velocity: Vector3 = info.get("velocity", Vector3.ZERO)
		if velocity.length_squared() < 0.0001:
			continue

		manager.apply_velocity_impulse(body.global_transform.origin, radius, velocity, 1.0, delta)

func _apply_player_damage(delta: float) -> void:
	if damage_per_second <= 0.0:
		return

	for id in _bodies_inside.keys():
		var info: Dictionary = _bodies_inside[id]
		var body = info.get("body", null)
		if not is_instance_valid(body) or not body is Spatial:
			continue
		if not _is_player_body(body):
			continue

		var cell_index := _world_position_to_cell_index(body.global_transform.origin)
		if cell_index < 0:
			continue

		var density := float(_grid[cell_index]["density"])
		if density > dense_damage_threshold:
			_apply_damage(body, damage_per_second * delta)

func _is_player_body(body: Node) -> bool:
	if body.is_in_group("player"):
		return true
	return body.name.to_lower().find("player") >= 0

func _apply_damage(body: Node, amount: float) -> void:
	if body.has_method("take_damage"):
		body.call("take_damage", amount)
	elif body.has_method("apply_damage"):
		body.call("apply_damage", amount)
	elif body.has_method("damage"):
		body.call("damage", amount)

func ignite_at_global_position(world_pos: Vector3, radius: float = -1.0) -> void:
	if not is_flammable:
		return
	var cell_index := _world_position_to_cell_index(world_pos)
	if cell_index < 0:
		return

	_mark_cell_ignited(cell_index)
	_emit_ignition(world_pos, combustion_radius if radius <= 0.0 else radius)

func ignite_at_local_cell(x: int, z: int) -> void:
	if not is_flammable:
		return
	if x < 0 or z < 0 or x >= grid_resolution or z >= grid_resolution:
		return

	var index := _cell_index(x, z)
	_mark_cell_ignited(index)
	_emit_ignition(_cell_to_world_position(x, z), combustion_radius)

func apply_thermal_damage(world_pos: Vector3, amount: float, radius: float = -1.0) -> void:
	if amount <= 0.0:
		return
	ignite_at_global_position(world_pos, radius)

func _mark_cell_ignited(index: int) -> void:
	_burning_cells[index] = 0.0
	if index >= 0 and index < _grid.size():
		var cell: Dictionary = _grid[index]
		cell["en_combustion"] = true
		cell["temperature"] = 1.0
		_grid[index] = cell
		for particle_index in _cell_particles[index]:
			manager.set_particle_combustion(int(particle_index), true)

func _update_combustion(delta: float) -> void:
	var new_cells := []
	var dead_cells := []

	for index in _burning_cells.keys():
		var burn_time := float(_burning_cells[index]) + delta
		_burning_cells[index] = burn_time
		if burn_time > 4.0:
			dead_cells.append(index)
			continue

		if index >= 0 and index < _cell_particles.size():
			for particle_index in _cell_particles[index]:
				manager.set_particle_combustion(int(particle_index), true)

		var coords := _cell_coords(int(index))
		for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var nx := int(coords.x + offset.x)
			var nz := int(coords.y + offset.y)
			if nx < 0 or nz < 0 or nx >= grid_resolution or nz >= grid_resolution:
				continue
			var neighbor_index := _cell_index(nx, nz)
			if _burning_cells.has(neighbor_index):
				continue
			if float(_grid[neighbor_index]["density"]) >= min_combustion_density:
				new_cells.append(neighbor_index)

	for index in dead_cells:
		_burning_cells.erase(index)

	for index in new_cells:
		if not _burning_cells.has(index):
			_mark_cell_ignited(index)
			var coords := _cell_coords(index)
			_emit_ignition(_cell_to_world_position(int(coords.x), int(coords.y)), combustion_radius)

func _cell_to_world_position(x: int, z: int) -> Vector3:
	var extents := _get_shape_extents()
	var nx := (float(x) + 0.5) / float(grid_resolution)
	var nz := (float(z) + 0.5) / float(grid_resolution)
	var shape_pos := Vector3(
		lerp(-extents.x, extents.x, nx),
		0.0,
		-lerp(-extents.z, extents.z, nz)
	)
	if _collision_shape:
		return _collision_shape.global_transform.xform(shape_pos)
	return global_transform.xform(shape_pos)

func _emit_ignition(world_pos: Vector3, radius: float) -> void:
	for id in _bodies_inside.keys():
		var info: Dictionary = _bodies_inside[id]
		var body = info.get("body", null)
		if not is_instance_valid(body) or not body is Spatial:
			continue
		var distance: float = body.global_transform.origin.distance_to(world_pos)
		if distance <= combustion_damage_radius:
			_apply_damage(body, damage_per_second * 0.5)

	emit_signal("gas_ignited", world_pos, radius)

func get_grid_cell(x: int, z: int) -> Dictionary:
	if x < 0 or z < 0 or x >= grid_resolution or z >= grid_resolution:
		return {}
	return _grid[_cell_index(x, z)].duplicate()
