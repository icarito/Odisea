extends Spatial
class_name RingHubWakeup

export(NodePath) var pilot_path := NodePath("Pilot")
export(NodePath) var criopod_path := NodePath("Criopod_Vert")
export(NodePath) var slots_path := NodePath("Hub/Criopods")
export(Vector3) var pilot_inside_offset := Vector3(0.000200272, 0.721707, -0.123402)

var _base_blocked_ranges: Array = []
var _selected_slot := -1
var _wakeup_collision_released := false

func _ready() -> void:
	add_to_group("replay_sync")
	var slots := _get_slots()
	if slots == null:
		return
	_base_blocked_ranges = slots.blocked_angle_ranges_deg.duplicate(true)
	if _selected_slot < 0:
		_selected_slot = _pick_slot(slots)
	_apply_wakeup_slot()
	_set_wakeup_collision_enabled(false)
	var wakeup_zone := get_node_or_null("Criopod_Vert/CinematicSequence") as Area
	if wakeup_zone and not wakeup_zone.is_connected("body_exited", self, "_on_wakeup_zone_exited"):
		wakeup_zone.connect("body_exited", self, "_on_wakeup_zone_exited")

func _get_slots() -> RadialScatter:
	return get_node_or_null(slots_path) as RadialScatter

func _pick_slot(slots: RadialScatter) -> int:
	var valid_slots := []
	for slot in range(slots.item_count):
		var data := _slot_data(slots, slot)
		if not slots._is_angle_blocked(data.angle_deg):
			valid_slots.append(slot)
	if valid_slots.empty():
		return -1
	var rng := RandomNumberGenerator.new()
	var session = get_node_or_null("/root/SessionManager")
	rng.seed = int(session.run_seed) if session and "run_seed" in session else 0
	return int(valid_slots[int(rng.randi() % valid_slots.size())])

func _apply_wakeup_slot() -> void:
	var slots := _get_slots()
	var pod := get_node_or_null(criopod_path) as Spatial
	var pilot := get_node_or_null(pilot_path) as Spatial
	if slots == null or pod == null or pilot == null or _selected_slot < 0:
		return
	if _base_blocked_ranges.empty():
		_base_blocked_ranges = slots.blocked_angle_ranges_deg.duplicate(true)
	var data := _slot_data(slots, _selected_slot)
	# Do not build a parallax pod under the functional wake-up pod.
	slots.blocked_angle_ranges_deg.clear()
	slots.blocked_angle_ranges_deg.append_array(_base_blocked_ranges.duplicate(true))
	slots.blocked_angle_ranges_deg.append(Vector2(data.angle_deg - 0.01, data.angle_deg + 0.01))
	var pod_scale := pod.scale
	pod.global_transform.origin = slots.to_global(data.position)
	if slots.inward:
		pod.look_at(slots.to_global(Vector3(0.0, data.height, 0.0)), Vector3.UP)
	slots._apply_rotation_offsets(pod, slots.rotation_x, slots.rotation_y, slots.rotation_z)
	pod.scale = pod_scale
	var pilot_transform := pod.global_transform
	pilot_transform.basis = pilot_transform.basis.orthonormalized()
	pilot_transform.origin = pod.to_global(pilot_inside_offset)
	pilot.global_transform = pilot_transform

func _on_wakeup_zone_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_set_wakeup_collision_enabled(true)

func _set_wakeup_collision_enabled(enabled: bool) -> void:
	_set_collision_shapes_enabled(get_node_or_null("Criopod_Vert/StaticBody2"), enabled)
	_set_collision_shapes_enabled(get_node_or_null("Criopod_Vert/RotatingObjectV2"), enabled)
	var wakeup_floor := get_node_or_null("Criopod_Vert/WakeupFloor/CollisionShape") as CollisionShape
	if wakeup_floor:
		wakeup_floor.set_deferred("disabled", enabled)
	_wakeup_collision_released = enabled

func _set_collision_shapes_enabled(node: Node, enabled: bool) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is CollisionShape:
			child.set_deferred("disabled", not enabled)
		_set_collision_shapes_enabled(child, enabled)

func _slot_data(slots: RadialScatter, slot: int) -> Dictionary:
	var progress := slots._get_progress(slot, slots.item_count)
	var angle := slots._get_angle(progress) + deg2rad(slots._get_item_angle_offset_deg(slot))
	var completed_turns := progress * slots.arc_angle_deg / 360.0
	var radius_turns := slots.radius_turn_offset + completed_turns
	var radius := slots._get_radius_at_turn(radius_turns)
	var height := slots.height_offset + slots.height_per_turn * completed_turns
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var tangent := Vector3(-sin(angle), 0.0, cos(angle))
	var offset := slots.item_offset + slots.item_offset_step * float(slot)
	var position := radial * radius + radial * offset.x
	position += Vector3.UP * (height + offset.y) + tangent * offset.z
	return {"angle_deg": rad2deg(angle), "height": height, "position": position}

func get_snapshot() -> Dictionary:
	return {"selected_slot": _selected_slot, "wakeup_collision_released": _wakeup_collision_released}

func restore_snapshot(data: Dictionary) -> void:
	_selected_slot = int(data.get("selected_slot", _selected_slot))
	_wakeup_collision_released = bool(data.get("wakeup_collision_released", false))
	_apply_wakeup_slot()
	_set_wakeup_collision_enabled(_wakeup_collision_released)
