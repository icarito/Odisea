extends Spatial
class_name PlateContentStream

# Streams gameplay content for centrifuge plates outside WorldRotator.
# Slots live in global physics space, while their transforms are derived from
# WorldRotator.global_transform * plate_canonical_transform.

export(NodePath) var rotator_path := NodePath("")
export(NodePath) var tracking_target_path := NodePath("")
export(int, 1, 128) var slot_pool_size := 16
export(int, 1, 60) var slot_update_interval := 3
export(bool) var auto_register_rotator := true
export(bool) var auto_assign_from_rotator := false
export(PackedScene) var auto_content_scene: PackedScene
export(Vector3) var auto_content_spawn_offset := Vector3.ZERO
export(int, 0, 64) var auto_plate_window_before := 2
export(int, 0, 64) var auto_plate_window_after := 5
# Mantiene contenido visible/streamed, pero solo deja cuerpos fisicos activos
# en el plate seleccionado por WorldRotator cuando el nivel esta en centrifugo.
export(bool) var centrifugal_current_plate_only_physics := true

var _rotator: Spatial = null
var _assignments := {}          # key -> PackedScene
var _assignment_indices := {}   # key -> {spiral_idx, plate_idx}
var _slots: Array = []          # Array[Spatial]
var _slot_assignments: Array = [] # Array[Dictionary]
var _slot_scenes: Array = []    # Array[PackedScene]
var _slot_update_counter := 0

func _ready() -> void:
	_build_slot_pool()
	_apply_slot_configs()
	if auto_register_rotator:
		var resolved: Spatial = _resolve_rotator()
		if resolved:
			register_rotator(resolved)
	call_deferred("_refresh_active_slots")

func _physics_process(delta: float) -> void:
	if _rotator == null or not is_instance_valid(_rotator):
		_rotator = _resolve_rotator()
	if _rotator == null:
		return

	if _slot_update_counter <= 0:
		_refresh_active_slots()
		_slot_update_counter = int(max(1, slot_update_interval)) - 1
	else:
		_slot_update_counter -= 1

	_sync_slot_transforms(delta)
	_sync_physics_activation_for_slots()

# Asocia una escena empaquetada a una plate específica.
# La escena se instanciará cuando esa plate esté entre las más cercanas.
func assign_scene(spiral_idx: int, plate_idx: int, packed: PackedScene, spawn_offset: Vector3 = Vector3.ZERO, context: Dictionary = {}) -> void:
	var key: String = _make_key(spiral_idx, plate_idx)
	if packed == null:
		_assignments.erase(key)
		_assignment_indices.erase(key)
		_deactivate_slot_for_key(key)
		return

	_assignments[key] = packed
	_assignment_indices[key] = {
		"spiral_idx": spiral_idx,
		"plate_idx": plate_idx,
		"spawn_offset": spawn_offset,
		"context": context.duplicate(true)
	}
	if is_inside_tree():
		_refresh_active_slots()
		_sync_slot_transforms(0.0)
		_sync_physics_activation_for_slots()

func clear_assignments() -> void:
	_assignments.clear()
	_assignment_indices.clear()
	for i in range(_slots.size()):
		_deactivate_slot(i)

# Registra el WorldRotator que provee transforms canónicos.
func register_rotator(rotator: Spatial) -> void:
	_rotator = rotator
	if is_inside_tree():
		_refresh_active_slots()
		_sync_slot_transforms(0.0)
		_sync_physics_activation_for_slots()

# Actualiza los transforms de todos los slots activos.
func _sync_slot_transforms(delta: float = 0.0) -> void:
	if _rotator == null or not is_instance_valid(_rotator):
		return
	for i in range(_slots.size()):
		var assignment: Dictionary = _slot_assignments[i]
		if assignment.empty():
			continue
		var slot: Spatial = _slots[i]
		if not is_instance_valid(slot):
			continue
		if not assignment.has("canonical_tx"):
			continue
		var canonical_tx = assignment["canonical_tx"]
		if canonical_tx is Transform:
			var target_global: Transform = _rotator.global_transform * (canonical_tx as Transform)
			if _transforms_close(slot.global_transform, target_global):
				continue
			var previous_slot_transform: Transform = slot.global_transform
			var active_rigid_states: Dictionary = _capture_active_rigid_body_states(slot, previous_slot_transform)
			slot.global_transform = target_global
			_restore_active_rigid_body_states(active_rigid_states, previous_slot_transform, target_global, delta)

func _sync_physics_activation_for_slots() -> void:
	var should_gate: bool = _should_gate_physics_to_selected_plate()
	for i in range(_slots.size()):
		var slot: Spatial = _slots[i]
		if not is_instance_valid(slot):
			continue
		var assignment: Dictionary = _slot_assignments[i]
		var active: bool = not should_gate or _assignment_matches_selected_plate(assignment)
		_set_subtree_physics_enabled(slot, active)

func _should_gate_physics_to_selected_plate() -> bool:
	if not centrifugal_current_plate_only_physics:
		return false
	if not _is_rotator_centrifugal():
		return false
	if _rotator == null or not is_instance_valid(_rotator):
		return false
	if not _rotator.has_method("get_selected_spiral_index") or not _rotator.has_method("get_selected_plate_index"):
		return false
	return int(_rotator.get_selected_spiral_index()) >= 0 and int(_rotator.get_selected_plate_index()) >= 0

func _assignment_matches_selected_plate(assignment: Dictionary) -> bool:
	if assignment.empty() or _rotator == null or not is_instance_valid(_rotator):
		return false
	return int(assignment.get("spiral_idx", -1)) == int(_rotator.get_selected_spiral_index()) \
			and int(assignment.get("plate_idx", -1)) == int(_rotator.get_selected_plate_index())

func _set_subtree_physics_enabled(root: Node, enabled: bool) -> void:
	for child in root.get_children():
		_set_node_physics_enabled(child, enabled)
		_set_subtree_physics_enabled(child, enabled)

func _set_node_physics_enabled(node: Node, enabled: bool) -> void:
	if enabled:
		_restore_node_physics_state(node)
	else:
		_disable_node_physics_state(node)

func _disable_node_physics_state(node: Node) -> void:
	if node.has_meta("plate_content_physics_gate"):
		return
	var state := {}
	if node is CollisionObject:
		var collision_object: CollisionObject = node as CollisionObject
		state["collision_layer"] = collision_object.collision_layer
		state["collision_mask"] = collision_object.collision_mask
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is RigidBody:
		var rigid_body: RigidBody = node as RigidBody
		state["mode"] = rigid_body.mode
		state["linear_velocity"] = rigid_body.linear_velocity
		state["angular_velocity"] = rigid_body.angular_velocity
		rigid_body.mode = RigidBody.MODE_KINEMATIC
		rigid_body.linear_velocity = Vector3.ZERO
		rigid_body.angular_velocity = Vector3.ZERO
		rigid_body.sleeping = true
	state["physics_processing"] = node.is_physics_processing()
	node.set_physics_process(false)
	node.set_meta("plate_content_physics_gate", state)

func _restore_node_physics_state(node: Node) -> void:
	if not node.has_meta("plate_content_physics_gate"):
		return
	var state = node.get_meta("plate_content_physics_gate")
	if state is Dictionary:
		var state_dict: Dictionary = state
		if node is CollisionObject:
			var collision_object: CollisionObject = node as CollisionObject
			if state_dict.has("collision_layer"):
				collision_object.collision_layer = int(state_dict["collision_layer"])
			if state_dict.has("collision_mask"):
				collision_object.collision_mask = int(state_dict["collision_mask"])
		if node is RigidBody:
			var rigid_body: RigidBody = node as RigidBody
			if state_dict.has("mode"):
				rigid_body.mode = int(state_dict["mode"])
			if state_dict.has("linear_velocity") and state_dict["linear_velocity"] is Vector3:
				rigid_body.linear_velocity = state_dict["linear_velocity"]
			if state_dict.has("angular_velocity") and state_dict["angular_velocity"] is Vector3:
				rigid_body.angular_velocity = state_dict["angular_velocity"]
			if rigid_body.mode == RigidBody.MODE_RIGID:
				rigid_body.sleeping = false
		node.set_physics_process(bool(state_dict.get("physics_processing", false)))
	node.remove_meta("plate_content_physics_gate")

# Devuelve el slot activo para una plate, o null si no está materializado.
func get_slot(spiral_idx: int, plate_idx: int) -> Spatial:
	var key: String = _make_key(spiral_idx, plate_idx)
	var index: int = _find_slot_for_key(key)
	if index != -1:
		return _slots[index]
	return null

func get_active_slots() -> Array:
	var active: Array = []
	for i in range(_slots.size()):
		if not _slot_assignments[i].empty():
			active.append(_slots[i])
	return active

func get_slot_for_node(node: Node) -> Spatial:
	var current: Node = node
	while current != null and current != self:
		for slot in _slots:
			if current == slot:
				return slot
		current = current.get_parent()
	return null

func get_streamed_nodes_in_group(group_name: String) -> Array:
	var found: Array = []
	for slot in get_active_slots():
		_collect_nodes_in_group(slot, group_name, found)
	return found

func _refresh_active_slots() -> void:
	_ensure_slot_pool()
	if _rotator == null or not is_instance_valid(_rotator):
		return

	var candidates: Array = _collect_candidates()
	candidates.sort_custom(self, "_sort_by_distance")
	var candidates_by_key := {}
	var active_candidate_count: int = int(min(candidates.size(), _slots.size()))
	var active_candidates: Array = candidates.slice(0, active_candidate_count - 1) if active_candidate_count > 0 else []
	for candidate in active_candidates:
		candidates_by_key[str(candidate["key"])] = candidate

	var assigned_keys := {}
	for i in range(_slots.size()):
		var assignment: Dictionary = _slot_assignments[i]
		if assignment.empty():
			continue
		var key: String = str(assignment.get("key", ""))
		if candidates_by_key.has(key):
			_activate_slot(i, candidates_by_key[key])
			assigned_keys[key] = true
		else:
			_deactivate_slot(i)

	for candidate in active_candidates:
		var key: String = str(candidate["key"])
		if assigned_keys.has(key):
			continue
		var free_slot: int = _find_free_slot()
		if free_slot == -1:
			break
		_activate_slot(free_slot, candidate)
		assigned_keys[key] = true
	_sync_physics_activation_for_slots()

func _collect_candidates() -> Array:
	var candidates: Array = []
	if _rotator == null or not _rotator.has_method("get_platforms"):
		return candidates

	var platforms: Array = _rotator.get_platforms()
	var center: Vector3 = _get_reference_canonical_position()
	var keys_seen := {}

	if auto_assign_from_rotator and auto_content_scene != null:
		candidates.append_array(_collect_auto_candidates(platforms, center, keys_seen))

	for key in _assignment_indices.keys():
		if keys_seen.has(key):
			continue
		if not _assignments.has(key):
			continue
		var indices: Dictionary = _assignment_indices[key]
		var spiral_idx: int = int(indices.get("spiral_idx", -1))
		var plate_idx: int = int(indices.get("plate_idx", -1))
		if spiral_idx < 0 or spiral_idx >= platforms.size():
			continue
		var spiral: Spatial = platforms[spiral_idx]
		if spiral == null:
			continue
		if _rotator.has_method("get_plate_count"):
			var plate_count: int = _rotator.get_plate_count(spiral)
			if plate_idx < 0 or plate_idx >= plate_count:
				continue
		if not _rotator.has_method("get_plate_canonical_transform"):
			continue

		var canonical_tx: Transform = _rotator.get_plate_canonical_transform(spiral, plate_idx)
		candidates.append({
			"key": key,
			"spiral_idx": spiral_idx,
			"plate_idx": plate_idx,
			"scene": _assignments[key],
			"spawn_offset": _assignment_indices.get(key, {}).get("spawn_offset", Vector3.ZERO),
			"context": _assignment_indices.get(key, {}).get("context", {}),
			"canonical_tx": canonical_tx,
			"dist_sq": canonical_tx.origin.distance_squared_to(center)
		})

	return candidates

func _collect_auto_candidates(platforms: Array, center: Vector3, keys_seen: Dictionary) -> Array:
	var candidates: Array = []
	if not _is_rotator_centrifugal():
		return candidates
	if platforms.empty() or not _rotator.has_method("get_plate_count") or not _rotator.has_method("get_plate_canonical_transform"):
		return candidates

	var base_spiral_idx: int = -1
	var base_plate_idx: int = -1
	if _rotator.has_method("get_selected_spiral_index") and _rotator.has_method("get_selected_plate_index"):
		base_spiral_idx = int(_rotator.get_selected_spiral_index())
		base_plate_idx = int(_rotator.get_selected_plate_index())

	if base_spiral_idx < 0 or base_plate_idx < 0:
		var target: Spatial = _get_tracking_target()
		if target == null or not _rotator.has_method("find_nearest_terrace_plate"):
			return candidates
		var nearest: Dictionary = _rotator.find_nearest_terrace_plate(target.global_transform.origin)
		if nearest.empty():
			return candidates
		base_spiral_idx = int(nearest.get("spiral_index", -1))
		base_plate_idx = int(nearest.get("plate_index", -1))

	if base_spiral_idx < 0 or base_spiral_idx >= platforms.size():
		return candidates
	var spiral: Spatial = platforms[base_spiral_idx]
	if spiral == null:
		return candidates
	var plate_count: int = _rotator.get_plate_count(spiral)
	if plate_count <= 0:
		return candidates

	var first_offset: int = -auto_plate_window_before
	var last_offset: int = auto_plate_window_after
	for offset in range(first_offset, last_offset + 1):
		var plate_idx: int = _wrap_index(base_plate_idx + offset, plate_count)
		var key: String = _make_key(base_spiral_idx, plate_idx)
		if keys_seen.has(key):
			continue
		var canonical_tx: Transform = _rotator.get_plate_canonical_transform(spiral, plate_idx)
		candidates.append({
			"key": key,
			"spiral_idx": base_spiral_idx,
			"plate_idx": plate_idx,
			"scene": auto_content_scene,
			"spawn_offset": auto_content_spawn_offset,
			"canonical_tx": canonical_tx,
			"dist_sq": canonical_tx.origin.distance_squared_to(center)
		})
		keys_seen[key] = true

	return candidates

func _activate_slot(index: int, candidate: Dictionary) -> void:
	var slot: Spatial = _slots[index]
	var key: String = str(candidate["key"])
	var scene: PackedScene = candidate["scene"] as PackedScene
	var current_assignment: Dictionary = _slot_assignments[index]
	var same_key: bool = not current_assignment.empty() and current_assignment.get("key", "") == key
	var same_scene: bool = _slot_scenes[index] == scene

	if not same_key or not same_scene:
		_clear_slot_children(slot)
		if _rotator and candidate.has("canonical_tx") and candidate["canonical_tx"] is Transform:
			slot.global_transform = _rotator.global_transform * (candidate["canonical_tx"] as Transform)
		if scene:
			var instance: Node = scene.instance()
			if instance:
				var spawn_offset: Vector3 = candidate.get("spawn_offset", _assignment_indices.get(key, {}).get("spawn_offset", Vector3.ZERO))
				var context: Dictionary = candidate.get("context", _assignment_indices.get(key, {}).get("context", {}))
				if instance is Spatial and spawn_offset != Vector3.ZERO:
					# spawn_offset is world-space; convert to slot-local to stay world-up
					# regardless of plate tilt angle.
					(instance as Spatial).transform.origin = slot.global_transform.basis.xform_inv(spawn_offset)
				_apply_instance_context(instance, context)
				slot.add_child(instance)

	_slot_assignments[index] = {
		"key": key,
		"spiral_idx": int(candidate["spiral_idx"]),
		"plate_idx": int(candidate["plate_idx"]),
		"canonical_tx": candidate["canonical_tx"]
	}
	_slot_scenes[index] = scene

func _apply_instance_context(instance: Node, context: Dictionary) -> void:
	if not is_instance_valid(instance) or typeof(context) != TYPE_DICTIONARY or context.empty():
		return
	instance.set_meta("plate_content_context", context.duplicate(true))
	if context.has("dome_id"):
		instance.set_meta("dome_id", String(context.get("dome_id", "")).strip_edges())
	if instance.has_method("apply_plate_content_context"):
		instance.call("apply_plate_content_context", context.duplicate(true))

func _deactivate_slot_for_key(key: String) -> void:
	var index: int = _find_slot_for_key(key)
	if index != -1:
		_deactivate_slot(index)

func _deactivate_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var slot: Spatial = _slots[index]
	if is_instance_valid(slot):
		_clear_slot_children(slot)
		slot.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	_slot_assignments[index] = {}
	_slot_scenes[index] = null

func _build_slot_pool() -> void:
	for slot in _slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_slots.clear()
	_slot_assignments.clear()
	_slot_scenes.clear()

	for i in range(slot_pool_size):
		var slot := Spatial.new()
		slot.name = "PlateContentSlot_%02d" % i
		slot.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
		add_child(slot)
		_slots.append(slot)
		_slot_assignments.append({})
		_slot_scenes.append(null)

func _ensure_slot_pool() -> void:
	if _slots.size() != slot_pool_size:
		_build_slot_pool()

func _apply_slot_configs() -> void:
	for child in get_children():
		if child is PlateSlotConfig:
			var cfg := child as PlateSlotConfig
			assign_scene(cfg.spiral_idx, cfg.plate_idx, cfg.content_scene)
			var key: String = _make_key(cfg.spiral_idx, cfg.plate_idx)
			if _assignment_indices.has(key):
				_assignment_indices[key]["spawn_offset"] = cfg.content_spawn_offset

func _find_slot_for_key(key: String) -> int:
	for i in range(_slot_assignments.size()):
		var assignment: Dictionary = _slot_assignments[i]
		if not assignment.empty() and assignment.get("key", "") == key:
			return i
	return -1

func _find_free_slot() -> int:
	for i in range(_slot_assignments.size()):
		if _slot_assignments[i].empty():
			return i
	return -1

func _clear_slot_children(slot: Spatial) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()

func _capture_active_rigid_body_states(root: Node, slot_global_transform: Transform) -> Dictionary:
	var captured := {}
	_capture_active_rigid_body_states_recursive(root, captured, slot_global_transform)
	return captured

func _capture_active_rigid_body_states_recursive(root: Node, captured: Dictionary, slot_global_transform: Transform) -> void:
	for child in root.get_children():
		if child is RigidBody and (child as RigidBody).mode == RigidBody.MODE_RIGID:
			var body: RigidBody = child as RigidBody
			captured[body] = {
				"local_transform": slot_global_transform.affine_inverse() * body.global_transform,
				"linear_velocity": body.linear_velocity,
				"angular_velocity": body.angular_velocity
			}
		_capture_active_rigid_body_states_recursive(child, captured, slot_global_transform)

func _restore_active_rigid_body_states(captured: Dictionary, previous_slot_transform: Transform, new_slot_transform: Transform, _delta: float) -> void:
	var slot_delta_basis: Basis = new_slot_transform.basis * previous_slot_transform.basis.inverse()
	for body in captured.keys():
		if is_instance_valid(body) and body is RigidBody:
			var body_state: Dictionary = captured[body]
			if not body_state.has("local_transform"):
				continue
			var rigid_body: RigidBody = body as RigidBody
			var local_transform: Transform = body_state["local_transform"]
			rigid_body.global_transform = new_slot_transform * local_transform
			if body_state.get("linear_velocity", null) is Vector3:
				rigid_body.linear_velocity = slot_delta_basis.xform(body_state["linear_velocity"])
			if body_state.get("angular_velocity", null) is Vector3:
				rigid_body.angular_velocity = slot_delta_basis.xform(body_state["angular_velocity"])

func _transforms_close(a: Transform, b: Transform) -> bool:
	if a.origin.distance_to(b.origin) > 0.001:
		return false
	if a.basis.x.normalized().dot(b.basis.x.normalized()) < 0.99999:
		return false
	if a.basis.y.normalized().dot(b.basis.y.normalized()) < 0.99999:
		return false
	if a.basis.z.normalized().dot(b.basis.z.normalized()) < 0.99999:
		return false
	return true

func _resolve_rotator() -> Spatial:
	var node: Node = null
	if not rotator_path.is_empty():
		node = get_node_or_null(rotator_path)
		if node == null and get_parent():
			node = get_parent().get_node_or_null(rotator_path)
		if node is Spatial:
			return node as Spatial

	node = get_node_or_null("../WorldRotator")
	if node is Spatial:
		return node as Spatial

	if has_node("/root/GravityWorld"):
		var manager: Node = get_node("/root/GravityWorld")
		if manager.has_method("get_rotator"):
			var rotator = manager.get_rotator()
			if rotator is Spatial:
				return rotator as Spatial
	return null

func _get_tracking_target() -> Spatial:
	var node: Node = null
	if not tracking_target_path.is_empty():
		node = get_node_or_null(tracking_target_path)
		if node == null and get_parent():
			node = get_parent().get_node_or_null(tracking_target_path)
		if node is Spatial:
			return node as Spatial

	var players: Array = get_tree().get_nodes_in_group("player") if is_inside_tree() else []
	for player in players:
		if player is Spatial and is_instance_valid(player):
			return player as Spatial
	return null

func _get_reference_canonical_position() -> Vector3:
	var target: Spatial = _get_tracking_target()
	if target and _rotator and _rotator.has_method("to_canonical"):
		return _rotator.to_canonical(target.global_transform.origin)

	if _rotator and _rotator.has_method("get_selected_plate_canonical_transform"):
		var selected: Transform = _rotator.get_selected_plate_canonical_transform()
		return selected.origin

	return Vector3.ZERO

func _is_rotator_centrifugal() -> bool:
	if _rotator == null or not is_instance_valid(_rotator):
		return false
	var value = _rotator.get("spiral_blend")
	if value == null:
		return true
	return float(value) > 0.001

func _collect_nodes_in_group(root: Node, group_name: String, out: Array) -> void:
	if root == null or root.is_queued_for_deletion():
		return
	if root.is_in_group(group_name):
		out.append(root)
	for child in root.get_children():
		_collect_nodes_in_group(child, group_name, out)

func _sort_by_distance(a: Dictionary, b: Dictionary) -> bool:
	return float(a["dist_sq"]) < float(b["dist_sq"])

func _make_key(spiral_idx: int, plate_idx: int) -> String:
	return "%d:%d" % [spiral_idx, plate_idx]

func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	var wrapped: int = value % size
	if wrapped < 0:
		wrapped += size
	return wrapped
