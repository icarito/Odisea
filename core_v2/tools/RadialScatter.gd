tool
extends Spatial
class_name RadialScatter

export(PackedScene) var target_scene setget set_target_scene
export(int, 1, 300) var item_count := 8 setget set_item_count
export(float, 0.0, 60.0, 0.1) var radius := 10.0 setget set_radius
export(float, -96.0, 96.0, 0.5) var height_offset := 0.0 setget set_height_offset
export(bool) var inward := true setget set_inward
export(Array, Vector2) var blocked_angle_ranges_deg := [] setget set_blocked_angle_ranges_deg
export(bool) var exact_item_count := false setget set_exact_item_count
export(float, -360.0, 360.0, 0.1) var rotation_x := 0.0 setget set_rotation_x
export(float, -360.0, 360.0, 0.1) var rotation_y := 0.0 setget set_rotation_y
export(float, -360.0, 360.0, 0.1) var rotation_z := 0.0 setget set_rotation_z
export(bool) var randomize_rotation := false setget set_randomize_rotation
export(float, 0.0, 180.0, 0.1) var rand_rotation_amount := 15.0 setget set_rand_rotation_amount
export(bool) var auto_build := true setget set_auto_build

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
	if get_child_count() != 0:
		return  # items already baked into the scene; nothing to build
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
		var angle := (float(i) / float(item_count)) * TAU
		if _is_angle_blocked(rad2deg(angle)):
			continue
		_add_item(i, angle, _defer_scene_owner, _defer_center_global, _defer_rng)
		placed += 1
	if _defer_index >= item_count:
		_defer_active = false

func _build_from_fixed_slots(scene_owner: Node, center_global: Vector3, rng: RandomNumberGenerator) -> void:
	for i in range(item_count):
		var angle = (float(i) / float(item_count)) * TAU
		var angle_deg = rad2deg(angle)
		if _is_angle_blocked(angle_deg):
			continue
		_add_item(i, angle, scene_owner, center_global, rng)

func _build_exact_count(scene_owner: Node, center_global: Vector3, rng: RandomNumberGenerator) -> void:
	var placed_count := 0
	var sample_count := max(item_count * 8, 64)

	for i in range(sample_count):
		if placed_count >= item_count:
			break
		var angle = (float(i) / float(sample_count)) * TAU
		var angle_deg = rad2deg(angle)
		if _is_angle_blocked(angle_deg):
			continue
		if _add_item(placed_count, angle, scene_owner, center_global, rng):
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

func _add_item(item_index: int, angle: float, scene_owner: Node, center_global: Vector3, rng: RandomNumberGenerator) -> bool:
	var pos = Vector3(cos(angle) * radius, height_offset, sin(angle) * radius)
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
	add_child(item)
	if scene_owner:
		item.owner = scene_owner

	var item_transform = item.transform
	item_transform.origin = pos
	item.transform = item_transform

	if inward:
		item.look_at(center_global, Vector3.UP)

	_apply_rotation_offsets(item, rotation_x, rotation_y, rotation_z)

	if randomize_rotation:
		_apply_rotation_offsets(
			item,
			rng.randf_range(-rand_rotation_amount, rand_rotation_amount),
			rng.randf_range(-rand_rotation_amount, rand_rotation_amount),
			rng.randf_range(-rand_rotation_amount, rand_rotation_amount)
		)

	return true

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
