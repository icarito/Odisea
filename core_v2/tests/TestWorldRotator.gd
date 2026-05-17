extends Spatial

export(int, 0, 3) var selected_spiral := 0
export(int, 0, 10000) var selected_plate := 0
export(bool) var snap_on_selection := true

onready var _rotator: Spatial = $WorldRotator
onready var _player: Spatial = $Pilot
onready var _camera: Camera = $Pilot/CameraRig/Yaw/Pitch/SpringArm/Camera

var _spirals: Array = []
var _selected_plate_canonical := Transform.IDENTITY

func _ready() -> void:
	_collect_spirals()
	_configure_test_rotator()
	if has_node("/root/GravityWorld"):
		GravityWorld.set_ship_axis(Vector3.ZERO, Vector3.UP)
	call_deferred("apply_selection")
	print("[TestWorldRotator] Controls: 1-4 spiral, A/D plate, Z/C +/-10 plates, Q/E spiral, F centrifugal, V axial")

func _process(delta: float) -> void:
	_sync_selection_from_rotator()
	_reset_camera_roll()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_1:
				_set_spiral(0)
			KEY_2:
				_set_spiral(1)
			KEY_3:
				_set_spiral(2)
			KEY_4:
				_set_spiral(3)
			KEY_Q:
				_set_spiral(selected_spiral - 1)
			KEY_E:
				_set_spiral(selected_spiral + 1)
			KEY_A:
				_set_plate(selected_plate - 1)
			KEY_D:
				_set_plate(selected_plate + 1)
			KEY_Z:
				_set_plate(selected_plate - 10)
			KEY_C:
				_set_plate(selected_plate + 10)
			KEY_F:
				_set_blend(1.0)
			KEY_V:
				_set_blend(0.0)
			KEY_R:
				_respawn_player()

func apply_selection() -> void:
	_collect_spirals()
	if _spirals.empty():
		printerr("[TestWorldRotator] No TerraceSpiral nodes found under WorldRotator")
		return
	selected_spiral = _wrap_index(selected_spiral, _spirals.size())
	_force_spiral_update()

	var spiral: Spatial = _spirals[selected_spiral]
	var plate_count: int = _get_plate_count(spiral)
	if plate_count <= 0:
		printerr("[TestWorldRotator] Selected TerraceSpiral has no plates: ", spiral.name)
		return

	selected_plate = clamp(selected_plate, 0, plate_count - 1)
	if not _rotator.select_terrace_plate(selected_spiral, selected_plate, null, snap_on_selection):
		printerr("[TestWorldRotator] Could not select generated terrace collision")
		return
	var plate_canonical: Transform = _rotator.get_selected_plate_canonical_transform()
	_selected_plate_canonical = plate_canonical
	_configure_gravity_for_selected_plate(plate_canonical)
	_rotator.auto_track_target_plate = true
	print("[TestWorldRotator] Spiral %d/%d plate %d/%d -> physical terrace" % [
		selected_spiral + 1,
		_spirals.size(),
		selected_plate,
		plate_count - 1
	])

func get_selected_plate_global_transform() -> Transform:
	return _rotator.get_selected_plate_global_transform()

func get_physical_terrace_transform() -> Transform:
	return _rotator.get_active_collision_transform()

func get_active_collision_body() -> StaticBody:
	return _rotator.get_active_collision_body()

func get_generated_collision_count() -> int:
	return _rotator.get_generated_collision_count()

func _set_spiral(value: int) -> void:
	selected_spiral = _wrap_index(value, max(1, _spirals.size()))
	apply_selection()

func _set_plate(value: int) -> void:
	selected_plate = value
	apply_selection()

func _set_blend(value: float) -> void:
	_rotator.spiral_blend = value
	apply_selection()

func _configure_test_rotator() -> void:
	if not _rotator:
		return
	_rotator.spiral_blend = 1.0
	_rotator.auto_select_first_platform = false
	_rotator.auto_track_target_plate = false
	_rotator.auto_track_requires_floor_contact = true
	_rotator.tracking_target_path = NodePath("../Pilot")
	_rotator.collision_pool_size = max(_rotator.collision_pool_size, 32)
	_rotator.collision_update_interval = 3

func _sync_selection_from_rotator() -> void:
	if not _rotator:
		return
	if not _rotator.has_method("get_selected_spiral_index") or not _rotator.has_method("get_selected_plate_index"):
		return
	var rotator_spiral: int = _rotator.get_selected_spiral_index()
	var rotator_plate: int = _rotator.get_selected_plate_index()
	if rotator_spiral < 0 or rotator_plate < 0:
		return
	if rotator_spiral == selected_spiral and rotator_plate == selected_plate:
		_selected_plate_canonical = _rotator.get_selected_plate_canonical_transform()
		return
	selected_spiral = rotator_spiral
	selected_plate = rotator_plate
	_selected_plate_canonical = _rotator.get_selected_plate_canonical_transform()
	_configure_gravity_for_selected_plate(_selected_plate_canonical)

func _collect_spirals() -> void:
	_spirals.clear()
	for name in ["TerraceSpiral", "TerraceSpiral2", "TerraceSpiral3", "TerraceSpiral4"]:
		var spiral: Node = _rotator.get_node_or_null(name)
		if spiral:
			_spirals.append(spiral)

func _force_spiral_update() -> void:
	for spiral in _spirals:
		if spiral.has_method("_rebuild_multimesh_if_needed"):
			spiral.call("_rebuild_multimesh_if_needed")
		if spiral.has_method("_update_spiral_animation"):
			spiral.call("_update_spiral_animation")

func _get_plate_count(spiral: Spatial) -> int:
	return _rotator.get_plate_count(spiral)

func _get_plate_canonical_transform(spiral: Spatial, plate_index: int) -> Transform:
	return _rotator.get_plate_canonical_transform(spiral, plate_index)

func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	var wrapped: int = value % size
	if wrapped < 0:
		wrapped += size
	return wrapped

func _respawn_player() -> void:
	var player: Node = get_node_or_null("Pilot")
	if player is Spatial:
		player.global_transform.origin = _rotator.get_active_collision_transform().origin + Vector3(0, 3, 3)
		if player.has_method("set_external_velocity"):
			player.set_external_velocity(Vector3.ZERO)

func _configure_gravity_for_selected_plate(plate_canonical: Transform) -> void:
	if not has_node("/root/GravityWorld"):
		return
	var radius: float = GravityWorld.get_axis_radius(plate_canonical.origin)
	GravityWorld.set_centrifugal_reference_radius(radius)
	GravityWorld.set_ship_angular_velocity(GravityWorld.get_default_angular_velocity_for_one_g(radius))

func _reset_camera_roll() -> void:
	if not _camera:
		return
	_camera.rotation.z = 0.0
