tool
extends Spatial
class_name RadialScatter

export(PackedScene) var target_scene setget set_target_scene
export(int, 1, 300) var item_count := 8 setget set_item_count
export(float, 0.0, 60.0, 0.1) var radius := 10.0 setget set_radius
export(float, -96.0, 96.0, 0.5) var height_offset := 0.0 setget set_height_offset
export(float, -3600.0, 3600.0, 0.1) var start_angle_deg := 0.0 setget set_start_angle_deg
export(float, -3600.0, 3600.0, 0.1) var arc_angle_deg := 360.0 setget set_arc_angle_deg
export(bool) var close_loop := true setget set_close_loop
export(float, -60.0, 60.0, 0.1) var radius_per_turn := 0.0 setget set_radius_per_turn
# Applies a non-linear radial contraction across the spiral. A value above 1
# keeps the outer path open and pulls it inward more strongly near its end.
export(float, 0.25, 4.0, 0.05) var radius_ease_power := 1.0 setget set_radius_ease_power
# Lets interleaved scatters evaluate the same global radial curve from a later
# point in the turn (for example, a walkway placed halfway after a stair).
export(float, -16.0, 16.0, 0.001) var radius_turn_offset := 0.0 setget set_radius_turn_offset
# Optional radius-derived numeric property on the target root. This keeps a
# segment depth proportional to the local spiral radius without manual tracks.
export(String) var radius_scaled_property := "" setget set_radius_scaled_property
export(float, -100.0, 100.0, 0.0001) var radius_scaled_factor := 0.0 setget set_radius_scaled_factor
# When non-zero, chunks are placed and aligned to their exact chord over this
# angular span. Interleaved scatters then share endpoints without hand rotation.
export(float, 0.0, 180.0, 0.1) var spiral_segment_angle_deg := 0.0 setget set_spiral_segment_angle_deg
export(String) var spiral_chord_length_property := "" setget set_spiral_chord_length_property
# Clips each scaffold deck against the radial join lines of its neighbouring
# chords. This removes the small seam angle left by a fixed trapezoid offset.
export(bool) var miter_spiral_joins := false setget set_miter_spiral_joins
export(float, -96.0, 96.0, 0.1) var height_per_turn := 0.0 setget set_height_per_turn
# Rotates tangent-aligned chunks by the local spiral tangent, compensating for
# radius_per_turn instead of treating the path as a perfect circle.
export(bool) var align_to_spiral_tangent := false setget set_align_to_spiral_tangent
export(Vector3) var item_offset := Vector3.ZERO setget set_item_offset
export(Vector3) var item_offset_step := Vector3.ZERO setget set_item_offset_step
# Optional per-item yaw around the scatter center. Unlike a miter, this only
# adjusts the selected chunk's angular placement; its height/radius slot stays
# stable, which makes it safe for authored interior inserts.
export(Array, float) var item_angle_offsets_deg := [] setget set_item_angle_offsets_deg
export(Vector3) var scale_start := Vector3.ONE setget set_scale_start
export(Vector3) var scale_end := Vector3.ONE setget set_scale_end
# Tracks are evaluated from 0 at the first item to 1 at the last. Each entry
# writes a float property on the instantiated scene root (for example,
# "right_height_offset" on SteelGratePlatform).
export(Array, String) var dynamic_float_properties := [] setget set_dynamic_float_properties
export(Array, float) var dynamic_float_start := [] setget set_dynamic_float_start
export(Array, float) var dynamic_float_end := [] setget set_dynamic_float_end
# Exact per-item overrides for authored/deformed chunks. Values are flattened
# by item, then property: item 0's values first, item 1's values next, etc.
export(Array, String) var per_item_float_properties := [] setget set_per_item_float_properties
export(Array, float) var per_item_float_values := [] setget set_per_item_float_values
export(bool) var inward := true setget set_inward
export(Array, Vector2) var blocked_angle_ranges_deg := [] setget set_blocked_angle_ranges_deg
export(bool) var exact_item_count := false setget set_exact_item_count
export(float, -360.0, 360.0, 0.1) var rotation_x := 0.0 setget set_rotation_x
export(float, -360.0, 360.0, 0.1) var rotation_y := 0.0 setget set_rotation_y
export(float, -360.0, 360.0, 0.1) var rotation_z := 0.0 setget set_rotation_z
export(bool) var randomize_rotation := false setget set_randomize_rotation
export(float, 0.0, 180.0, 0.1) var rand_rotation_amount := 15.0 setget set_rand_rotation_amount
export(bool) var auto_build := true setget set_auto_build
# Regenerates scene-baked children at runtime. Keep disabled for normal baked
# scatters; enable temporarily after changing generator parameters.
export(bool) var rebuild_baked_items := false

var _build_queued := false
# Deferred incremental build state. In game (not editor) the scatter registers in
# the "deferred_build" group so SceneManager spreads its instancing across frames
# after the scene loads — instancing dozens of items in the spawn frame is the
# load spike on scene arrival. Items are placed a few per call instead of all at
# once. Set deferred_build=false to build synchronously in _ready (old behavior).
export(bool) var deferred_build := true
export(int, 1, 32) var items_per_step := 4
var _defer_index := 0
var _defer_active := false
var _defer_scene_owner: Node = null
var _defer_center_global := Vector3.ZERO
var _defer_rng: RandomNumberGenerator = null

func _ready() -> void:
	if Engine.editor_hint:
		_queue_build()
		return
	if get_child_count() != 0 and not rebuild_baked_items:
		return  # items already baked into the scene; nothing to build
	if rebuild_baked_items:
		build()
		return
	if deferred_build:
		add_to_group("deferred_build")
		# Begin in a "pending" state; SceneManager drives steps. As a safety net,
		# if nothing drives it (e.g. scene opened directly), build on next frame.
		call_deferred("_deferred_build_safety_net")
	else:
		build()

func _deferred_build_safety_net() -> void:
	# If no external driver (SceneManager) started the build within a couple of
	# frames — e.g. the scene was opened directly, not via goto_scene — drive it
	# here, still incrementally (one step per idle frame) so a direct load doesn't
	# spike either.
	if _defer_active or get_child_count() != 0 or target_scene == null:
		return
	begin_deferred_build()
	while has_pending_deferred_items() and is_inside_tree():
		deferred_build_step()
		if has_pending_deferred_items():
			yield(get_tree(), "idle_frame")

func set_target_scene(value: PackedScene) -> void:
	target_scene = value
	_queue_build()

func set_item_count(value: int) -> void:
	item_count = clamp(value, 1, 64)
	_queue_build()

func set_radius(value: float) -> void:
	radius = max(value, 0.0)
	_queue_build()

func set_height_offset(value: float) -> void:
	height_offset = value
	_queue_build()

func set_start_angle_deg(value: float) -> void:
	start_angle_deg = value
	_queue_build()

func set_arc_angle_deg(value: float) -> void:
	arc_angle_deg = value
	_queue_build()

func set_close_loop(value: bool) -> void:
	close_loop = value
	_queue_build()

func set_radius_per_turn(value: float) -> void:
	radius_per_turn = value
	_queue_build()

func set_radius_ease_power(value: float) -> void:
	radius_ease_power = max(value, 0.25)
	_queue_build()

func set_radius_turn_offset(value: float) -> void:
	radius_turn_offset = value
	_queue_build()

func set_radius_scaled_property(value: String) -> void:
	radius_scaled_property = value
	_queue_build()

func set_radius_scaled_factor(value: float) -> void:
	radius_scaled_factor = value
	_queue_build()

func set_spiral_segment_angle_deg(value: float) -> void:
	spiral_segment_angle_deg = max(value, 0.0)
	_queue_build()

func set_spiral_chord_length_property(value: String) -> void:
	spiral_chord_length_property = value
	_queue_build()

func set_miter_spiral_joins(value: bool) -> void:
	miter_spiral_joins = value
	_queue_build()

func set_height_per_turn(value: float) -> void:
	height_per_turn = value
	_queue_build()

func set_align_to_spiral_tangent(value: bool) -> void:
	align_to_spiral_tangent = value
	_queue_build()

func set_item_offset(value: Vector3) -> void:
	item_offset = value
	_queue_build()

func set_item_offset_step(value: Vector3) -> void:
	item_offset_step = value
	_queue_build()

func set_item_angle_offsets_deg(value: Array) -> void:
	item_angle_offsets_deg = value
	_queue_build()

func set_scale_start(value: Vector3) -> void:
	scale_start = value
	_queue_build()

func set_scale_end(value: Vector3) -> void:
	scale_end = value
	_queue_build()

func set_dynamic_float_properties(value: Array) -> void:
	dynamic_float_properties = value
	_queue_build()

func set_dynamic_float_start(value: Array) -> void:
	dynamic_float_start = value
	_queue_build()

func set_dynamic_float_end(value: Array) -> void:
	dynamic_float_end = value
	_queue_build()

func set_per_item_float_properties(value: Array) -> void:
	per_item_float_properties = value
	_queue_build()

func set_per_item_float_values(value: Array) -> void:
	per_item_float_values = value
	_queue_build()

func set_inward(value: bool) -> void:
	inward = value
	_queue_build()

func set_blocked_angle_ranges_deg(value: Array) -> void:
	blocked_angle_ranges_deg = value
	_queue_build()

func set_exact_item_count(value: bool) -> void:
	exact_item_count = value
	_queue_build()

func set_rotation_x(value: float) -> void:
	rotation_x = value
	_queue_build()

func set_rotation_y(value: float) -> void:
	rotation_y = value
	_queue_build()

func set_rotation_z(value: float) -> void:
	rotation_z = value
	_queue_build()

func set_randomize_rotation(value: bool) -> void:
	randomize_rotation = value
	_queue_build()

func set_rand_rotation_amount(value: float) -> void:
	rand_rotation_amount = max(value, 0.0)
	_queue_build()

func set_auto_build(value: bool) -> void:
	auto_build = value
	if auto_build:
		_queue_build()

func build() -> void:
	_build_queued = false
	_clear_children()

	if not target_scene:
		push_warning("RadialScatter: target_scene is null, nothing to build.")
		return

	var scene_owner = _get_scene_owner()
	var center_global = to_global(Vector3(0.0, height_offset, 0.0))
	var rng = RandomNumberGenerator.new()
	if randomize_rotation:
		rng.randomize()

	if exact_item_count:
		_build_exact_count(scene_owner, center_global, rng)
	else:
		_build_from_fixed_slots(scene_owner, center_global, rng)

	# Phase 2: batch generated instances into a MultiMeshInstance to reduce draw calls.

# --- Deferred incremental build API (driven by SceneManager) ---

# Prepare the incremental build. Cheap: just caches what build() would compute up
# front. No items are instanced here.
func begin_deferred_build() -> void:
	if _defer_active:
		return
	_clear_children()
	if not target_scene:
		return
	_defer_scene_owner = _get_scene_owner()
	_defer_center_global = to_global(Vector3(0.0, height_offset, 0.0))
	_defer_rng = RandomNumberGenerator.new()
	if randomize_rotation:
		_defer_rng.randomize()
	_defer_index = 0
	_defer_active = true

func has_pending_deferred_items() -> bool:
	return _defer_active and _defer_index < item_count

# Instance up to items_per_step items. Call once per frame from a driver until
# has_pending_deferred_items() returns false.
func deferred_build_step() -> void:
	if not _defer_active:
		return
	var placed := 0
	while _defer_index < item_count and placed < items_per_step:
		var i := _defer_index
		_defer_index += 1
		var progress := _get_progress(i, item_count)
		var angle := _get_angle(progress)
		if _is_angle_blocked(rad2deg(angle)):
			continue
		_add_item(i, angle, progress, _defer_scene_owner, _defer_center_global, _defer_rng)
		placed += 1
	if _defer_index >= item_count:
		_defer_active = false

func _build_from_fixed_slots(scene_owner: Node, center_global: Vector3, rng: RandomNumberGenerator) -> void:
	for i in range(item_count):
		var progress := _get_progress(i, item_count)
		var angle := _get_angle(progress) + deg2rad(_get_item_angle_offset_deg(i))
		var angle_deg = rad2deg(angle)
		if _is_angle_blocked(angle_deg):
			continue
		_add_item(i, angle, progress, scene_owner, center_global, rng)

func _build_exact_count(scene_owner: Node, center_global: Vector3, rng: RandomNumberGenerator) -> void:
	var placed_count := 0
	var sample_count := max(item_count * 8, 64)

	for i in range(sample_count):
		if placed_count >= item_count:
			break
		var progress := _get_progress(i, sample_count)
		var angle := _get_angle(progress)
		var angle_deg = rad2deg(angle)
		if _is_angle_blocked(angle_deg):
			continue
		if _add_item(placed_count, angle, progress, scene_owner, center_global, rng):
			placed_count += 1

	if placed_count < item_count:
		push_warning("RadialScatter: blocked ranges leave insufficient free angle to place all exact items.")

func _queue_build() -> void:
	if not auto_build or not is_inside_tree():
		return
	if _build_queued:
		return
	_build_queued = true
	call_deferred("build")

func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

func _add_item(item_index: int, angle: float, progress: float, scene_owner: Node, center_global: Vector3, rng: RandomNumberGenerator) -> bool:
	# Angular overrides are visual/layout corrections for a slot, not extra
	# progress through the spiral: keep radius and height on the original slot.
	var completed_turns: float = progress * arc_angle_deg / 360.0
	var radius_turns: float = radius_turn_offset + completed_turns
	var current_radius: float = _get_radius_at_turn(radius_turns)
	var current_height: float = height_offset + height_per_turn * completed_turns
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var tangent := Vector3(-sin(angle), 0.0, cos(angle))
	var offset: Vector3 = item_offset + item_offset_step * float(item_index)
	var chord_start := Vector3.ZERO
	var chord_end := Vector3.ZERO
	var path_pos: Vector3 = radial * current_radius
	if spiral_segment_angle_deg > 0.001:
		chord_start = _get_spiral_chord_start(angle, radius_turns)
		chord_end = _get_spiral_chord_end(angle, radius_turns)
		path_pos = (chord_start + chord_end) * 0.5
	var pos: Vector3 = path_pos + radial * offset.x
	pos += Vector3.UP * (current_height + offset.y)
	pos += tangent * offset.z
	var instance = target_scene.instance()
	if not instance:
		push_warning("RadialScatter: failed to instance target_scene.")
		return false
	if not (instance is Spatial):
		push_warning("RadialScatter: target_scene root must extend Spatial.")
		instance.free()
		return false

	var item := instance as Spatial
	item.name = "Item_%d" % item_index
	_apply_dynamic_float_properties(item, progress)
	if not radius_scaled_property.empty():
		item.set(radius_scaled_property, current_radius * radius_scaled_factor)
	if not spiral_chord_length_property.empty() and spiral_segment_angle_deg > 0.001:
		item.set(spiral_chord_length_property, chord_start.distance_to(chord_end))
	add_child(item)
	if scene_owner:
		item.owner = scene_owner

	var item_transform = item.transform
	item_transform.origin = pos
	item.transform = item_transform

	if inward:
		item.look_at(center_global + Vector3.UP * (current_height - height_offset), Vector3.UP)

	_apply_rotation_offsets(item, rotation_x, rotation_y, rotation_z)
	if align_to_spiral_tangent:
		var tangent_correction: float = _get_spiral_tangent_correction_deg(current_radius, radius_turns)
		if spiral_segment_angle_deg > 0.001:
			tangent_correction = _get_spiral_chord_correction_deg(angle, radius_turns, radial, tangent)
		_apply_rotation_offsets(item, 0.0, tangent_correction, 0.0)
	if miter_spiral_joins and spiral_segment_angle_deg > 0.001:
		_apply_spiral_join_miter(item, chord_start, chord_end, angle)
	# Authored values intentionally win over the automatic miter calculation.
	_apply_per_item_float_properties(item, item_index)
	item.scale_object_local(Vector3(
		lerp(scale_start.x, scale_end.x, progress),
		lerp(scale_start.y, scale_end.y, progress),
		lerp(scale_start.z, scale_end.z, progress)
	))

	if randomize_rotation:
		_apply_rotation_offsets(
			item,
			rng.randf_range(-rand_rotation_amount, rand_rotation_amount),
			rng.randf_range(-rand_rotation_amount, rand_rotation_amount),
			rng.randf_range(-rand_rotation_amount, rand_rotation_amount)
		)

	return true

func _get_progress(index: int, count: int) -> float:
	var divisor: int = count if close_loop else max(count - 1, 1)
	return float(index) / float(divisor)

func _get_angle(progress: float) -> float:
	return deg2rad(start_angle_deg + arc_angle_deg * progress)

func _get_item_angle_offset_deg(index: int) -> float:
	if index < 0 or index >= item_angle_offsets_deg.size():
		return 0.0
	return float(item_angle_offsets_deg[index])

func _get_radius_at_turn(turns: float) -> float:
	return max(0.0, radius + radius_per_turn * _get_eased_turns(turns))

func _get_eased_turns(turns: float) -> float:
	if is_equal_approx(radius_ease_power, 1.0):
		return turns
	return sign(turns) * pow(abs(turns), radius_ease_power)

func _get_spiral_tangent_correction_deg(current_radius: float, turns: float = 0.0) -> float:
	if is_zero_approx(radius_per_turn) or current_radius <= 0.001:
		return 0.0
	var radius_delta_per_turn: float = radius_per_turn
	if not is_equal_approx(radius_ease_power, 1.0):
		if is_zero_approx(turns):
			radius_delta_per_turn = 0.0
		else:
			radius_delta_per_turn *= radius_ease_power * pow(abs(turns), radius_ease_power - 1.0)
	var radius_change_per_radian: float = radius_delta_per_turn / TAU
	return rad2deg(atan2(radius_change_per_radian, current_radius))

func _get_spiral_chord_start(angle: float, turns: float) -> Vector3:
	var half_angle: float = deg2rad(spiral_segment_angle_deg * 0.5)
	var half_turns: float = spiral_segment_angle_deg / 720.0
	var start_angle: float = angle - half_angle
	return Vector3(cos(start_angle), 0.0, sin(start_angle)) * _get_radius_at_turn(turns - half_turns)

func _get_spiral_chord_end(angle: float, turns: float) -> Vector3:
	var half_angle: float = deg2rad(spiral_segment_angle_deg * 0.5)
	var half_turns: float = spiral_segment_angle_deg / 720.0
	var end_angle: float = angle + half_angle
	return Vector3(cos(end_angle), 0.0, sin(end_angle)) * _get_radius_at_turn(turns + half_turns)

func _get_spiral_chord_correction_deg(angle: float, turns: float, radial: Vector3, tangent: Vector3) -> float:
	var chord: Vector3 = _get_spiral_chord_end(angle, turns) - _get_spiral_chord_start(angle, turns)
	return rad2deg(atan2(chord.dot(radial), chord.dot(tangent)))

func _apply_spiral_join_miter(item: Spatial, chord_start: Vector3, chord_end: Vector3, angle: float) -> void:
	if item.get("platform_width") == null or item.get("platform_depth") == null:
		return
	item.set("snap_mitered_joins", true)
	var half_width: float = float(item.get("platform_width")) * 0.5
	var half_turn: float = deg2rad(spiral_segment_angle_deg * 0.5)
	_apply_join_line(item, chord_start, Vector3(cos(angle - half_turn), 0.0, sin(angle - half_turn)), half_width)
	_apply_join_line(item, chord_end, Vector3(cos(angle + half_turn), 0.0, sin(angle + half_turn)), half_width)

func _apply_join_line(item: Spatial, point: Vector3, radial: Vector3, half_width: float) -> void:
	for x in [ -half_width, half_width ]:
		var local_x: float = x
		var target_global: Vector3 = to_global(point + radial * x)
		var target_local: Vector3 = item.global_transform.affine_inverse().xform(target_global)
		var z: float = target_local.z
		var base: float = _get_item_deck_z(item, x, -1.0 if z < 0.0 else 1.0)
		var property_name = "front_left_depth_offset" if z < 0.0 and x < 0.0 else "front_right_depth_offset" if z < 0.0 else "back_left_depth_offset" if x < 0.0 else "back_right_depth_offset"
		item.set(property_name, z - base)
		var width_property = "front_left_width_offset" if z < 0.0 and x < 0.0 else "front_right_width_offset" if z < 0.0 else "back_left_width_offset" if x < 0.0 else "back_right_width_offset"
		item.set(width_property, target_local.x - local_x)

func _get_item_deck_z(item: Spatial, x: float, z_sign: float) -> float:
	var width: float = float(item.get("platform_width"))
	var depth: float = float(item.get("platform_depth"))
	var x_t: float = clamp((x + width * 0.5) / max(width, 0.001), 0.0, 1.0)
	var left: float = float(item.get("left_depth_offset"))
	var right: float = float(item.get("right_depth_offset"))
	return z_sign * (depth * 0.5 + lerp(left, right, x_t))

func _apply_dynamic_float_properties(item: Spatial, progress: float) -> void:
	var track_count: int = min(dynamic_float_properties.size(), min(dynamic_float_start.size(), dynamic_float_end.size()))
	for i in range(track_count):
		var property_name: String = str(dynamic_float_properties[i])
		if property_name.empty():
			continue
		item.set(property_name, lerp(float(dynamic_float_start[i]), float(dynamic_float_end[i]), progress))

func _apply_per_item_float_properties(item: Spatial, item_index: int) -> void:
	var property_count: int = per_item_float_properties.size()
	if property_count <= 0:
		return
	for i in range(property_count):
		var value_index: int = item_index * property_count + i
		if value_index >= per_item_float_values.size():
			return
		var property_name: String = str(per_item_float_properties[i])
		if not property_name.empty():
			item.set(property_name, float(per_item_float_values[value_index]))

func _apply_rotation_offsets(item: Spatial, x_deg: float, y_deg: float, z_deg: float) -> void:
	if not is_zero_approx(x_deg):
		item.rotate_object_local(Vector3.RIGHT, deg2rad(x_deg))
	if not is_zero_approx(y_deg):
		item.rotate_object_local(Vector3.UP, deg2rad(y_deg))
	if not is_zero_approx(z_deg):
		item.rotate_object_local(Vector3.BACK, deg2rad(z_deg))

func _is_angle_blocked(angle_deg: float) -> bool:
	var normalized_angle = fposmod(angle_deg, 360.0)

	for range_deg in blocked_angle_ranges_deg:
		if not (range_deg is Vector2):
			continue

		var start_deg = fposmod(range_deg.x, 360.0)
		var end_deg = fposmod(range_deg.y, 360.0)

		if start_deg <= end_deg:
			if normalized_angle >= start_deg and normalized_angle <= end_deg:
				return true
		else:
			if normalized_angle >= start_deg or normalized_angle <= end_deg:
				return true

	return false

func _get_scene_owner() -> Node:
	if owner:
		return owner
	if Engine.editor_hint and get_tree():
		return get_tree().edited_scene_root
	return null
