extends Spatial

export(int, 0, 3) var selected_spiral := 0
export(int, 0, 10000) var selected_plate := 0
export(bool) var snap_on_selection := true
export(PackedScene) var plate_content_scene

onready var _rotator: Spatial = $WorldRotator
onready var _physical_terrace: StaticBody = $PhysicalTerrace
onready var _player: Spatial = $Pilot
onready var _camera: Camera = $Pilot/CameraRig/Yaw/Pitch/SpringArm/Camera
onready var _plate_content_stream: Spatial = get_node_or_null("PlateContentRoot") as Spatial

var _spirals: Array = []
var _selected_plate_canonical := Transform.IDENTITY

func _ready() -> void:
	_collect_spirals()
	_configure_test_rotator()
	_configure_plate_content_stream()
	if has_node("/root/GravityWorld"):
		GravityWorld.set_ship_axis(Vector3.ZERO, Vector3.UP)
	
	_resolve_spawn_state()
	call_deferred("apply_selection")

func _process(delta: float) -> void:
	_sync_selection_from_rotator()
	_reset_camera_roll()

func _resolve_spawn_state() -> void:
	if not has_node("/root/SceneManager"):
		return
	var scene_manager = get_node("/root/SceneManager")
	var params = scene_manager.get("_transition_params")
	if typeof(params) == TYPE_DICTIONARY:
		var spawn_id = params.get("target_spawn_id", params.get("spawn_id", ""))
		var dome_id = ""
		for check_id in DomeRegistry.get_all_dome_ids():
			var info = DomeRegistry.get_dome(check_id)
			if info.get("spawn_id_from_interior") == spawn_id:
				dome_id = check_id
				break
		if dome_id != "":
			var info = DomeRegistry.get_dome(dome_id)
			selected_spiral = info.get("spiral_index", 0)
			selected_plate = info.get("plate_index", 0)
			snap_on_selection = true

func apply_selection() -> void:
	_collect_spirals()
	if _spirals.empty():
		printerr("[OdiseaExterior] No TerraceSpiral nodes found under WorldRotator")
		return
	selected_spiral = _wrap_index(selected_spiral, _spirals.size())
	_force_spiral_update()

	var spiral: Spatial = _spirals[selected_spiral]
	var plate_count: int = _get_plate_count(spiral)
	if plate_count <= 0:
		printerr("[OdiseaExterior] Selected TerraceSpiral has no plates: ", spiral.name)
		return

	selected_plate = clamp(selected_plate, 0, plate_count - 1)
	if not _rotator.select_terrace_plate(selected_spiral, selected_plate, null, snap_on_selection):
		printerr("[OdiseaExterior] Could not select generated terrace collision")
		return
	_rotator.scene_anchor_spiral_index = selected_spiral
	_rotator.scene_anchor_plate_index = selected_plate
	if _rotator.has_method("_apply_scene_anchor"):
		_rotator.call("_apply_scene_anchor")
	var plate_canonical: Transform = _rotator.get_selected_plate_canonical_transform()
	_selected_plate_canonical = plate_canonical
	_configure_gravity_for_selected_plate(plate_canonical)
	_assign_plate_content()
	_rotator.auto_track_target_plate = true

func get_selected_plate_global_transform() -> Transform:
	return _rotator.get_selected_plate_global_transform()

func get_physical_terrace_transform() -> Transform:
	if _physical_terrace:
		return _physical_terrace.global_transform
	return _rotator.get_active_collision_transform()

func get_active_collision_body() -> StaticBody:
	return _rotator.get_active_collision_body()

func get_generated_collision_count() -> int:
	return _rotator.get_generated_collision_count()

func get_plate_content_stream() -> Spatial:
	return _plate_content_stream

func get_streamed_pushable_boxes() -> Array:
	if _plate_content_stream and _plate_content_stream.has_method("get_streamed_nodes_in_group"):
		var boxes: Array = _plate_content_stream.get_streamed_nodes_in_group("pushable_box")
		if boxes.empty():
			boxes = _plate_content_stream.get_streamed_nodes_in_group("pushable")
		return boxes
	return []

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
	_rotator.physical_terrace_path = NodePath("../PhysicalTerrace")
	_rotator.collision_pool_size = max(_rotator.collision_pool_size, 32)
	_rotator.collision_update_interval = 3

func _configure_plate_content_stream() -> void:
	if not _plate_content_stream:
		return
	_plate_content_stream.rotator_path = NodePath("../WorldRotator")
	_plate_content_stream.tracking_target_path = NodePath("../Pilot")
	_plate_content_stream.slot_pool_size = 16
	_plate_content_stream.slot_update_interval = 1
	if _plate_content_stream.has_method("register_rotator"):
		_plate_content_stream.register_rotator(_rotator)

func _assign_plate_content() -> void:
	if not _plate_content_stream:
		return
	if selected_spiral < 0 or selected_spiral >= _spirals.size():
		return
	var spiral: Spatial = _spirals[selected_spiral]
	var plate_count: int = _get_plate_count(spiral)
	if plate_count <= 0:
		return
	if _plate_content_stream.has_method("register_rotator"):
		_plate_content_stream.register_rotator(_rotator)
		
	# First assign standard plates
	if plate_content_scene != null:
		for offset in range(-2, 6):
			var plate_idx: int = _wrap_index(selected_plate + offset, plate_count)
			_plate_content_stream.assign_scene(selected_spiral, plate_idx, plate_content_scene)
			
	# Then assign special facade scenes based on DomeRegistry
	for dome_id in DomeRegistry.get_all_dome_ids():
		var info = DomeRegistry.get_dome(dome_id)
		if info.has("facade_scene") and info.has("spiral_index") and info.has("plate_index"):
			var facade_scene_path: String = info["facade_scene"]
			if ResourceLoader.exists(facade_scene_path):
				var facade_scene = load(facade_scene_path)
				if facade_scene is PackedScene:
					_plate_content_stream.assign_scene(int(info["spiral_index"]), int(info["plate_index"]), facade_scene)

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
	_assign_plate_content()

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
