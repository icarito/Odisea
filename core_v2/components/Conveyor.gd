extends Area
tool

signal activated()
signal deactivated()
signal interaction_started()
signal interaction_completed()

export(float) var speed_x := 2.0 setget set_speed_x
export(bool) var starts_active := true setget set_starts_active
export(float) var acceleration := 4.0
export(bool) var require_on_floor := false
export(float) var rigid_force_multiplier := 10.0
export(bool) var debug := false

export(bool) var occupancy_detection := true setget set_occupancy_detection
export(float) var debounce_time := 0.2 setget set_debounce_time
export(float) var idle_speed_ratio := 0.1 setget set_idle_speed_ratio

export(Color) var stripe_dark_color = Color(0.14, 0.15, 0.16, 1.0) setget set_stripe_dark_color
export(Color) var stripe_light_color = Color(0.48, 0.42, 0.16, 1.0) setget set_stripe_light_color
export(float) var stripe_emission = 0.015 setget set_stripe_emission
export(float) var stripe_tiling = 4.0 setget set_stripe_tiling
export(float) var stripe_fill = 0.42 setget set_stripe_fill

export(float) var length := 8.0 setget set_length
export(float) var width := 3.0 setget set_width
export(float) var visual_speed_multiplier := 1.0 setget set_visual_speed_multiplier

# Legacy property bridge for scenes saved with old versions.
var push_velocity: Vector3 setget set_push_velocity
var _speed_x_initialized := false
var is_active := true

var _bodies := []
var _pending_snapshot = null
var _internal_speed := 0.0
var _visual_speed := 0.0
var _visual_phase := 0.0
var _occupancy_hold_timer := 0.0
var _occupied := false
var _feedback_state := "disabled"
var _running := false

const INDICATOR_BUTTON_SIZE := Vector3(0.18, 0.035, 0.2)
const INDICATOR_HOUSING_SIZE := Vector3(0.26, 0.045, 1.08)
const INDICATOR_COLLISION_EXTENTS := Vector3(0.09, 0.02, 0.1)
const INDICATOR_BUTTON_Y := 0.085
const INDICATOR_HOUSING_OFFSET := Vector3(0.0, 0.065, 0.0)
const INDICATOR_LIGHT_HEIGHT := 0.125

func _init():
	add_to_group("replay_sync")

func _ready():
	_ensure_support_nodes()
	_update_scaling()
	is_active = starts_active
	_apply_idle_runtime_defaults()
	_trigger_shader_update()
	_update_feedback_state(_should_drive_without_sampling())

	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

func _ensure_support_nodes() -> void:
	var ground = get_node_or_null("Ground")
	if ground and not ground.has_node("BaseVisual"):
		var base_visual := CSGBox.new()
		base_visual.name = "BaseVisual"
		base_visual.material = _build_metal_material(Color(0.24, 0.26, 0.29, 1.0), 0.85, 0.15)
		ground.add_child(base_visual)
		if Engine.editor_hint:
			base_visual.owner = get_tree().edited_scene_root

	for plate_name in ["EntryPlate", "ExitPlate", "SidePlateLeft", "SidePlateRight"]:
		if has_node(plate_name):
			continue
		var plate := CSGBox.new()
		plate.name = plate_name
		plate.material = _build_metal_material(Color(0.36, 0.38, 0.4, 1.0), 0.72, 0.08)
		add_child(plate)
		if Engine.editor_hint:
			plate.owner = get_tree().edited_scene_root

	if not has_node("Indicators"):
		var indicators := Spatial.new()
		indicators.name = "Indicators"
		add_child(indicators)
		if Engine.editor_hint:
			indicators.owner = get_tree().edited_scene_root

		_create_indicator_pair(indicators, "Ready", Color(0.25, 0.8, 0.35, 1.0), 0.34)
		_create_indicator_pair(indicators, "Running", Color(0.86, 0.67, 0.19, 1.0), 0.0)
		_create_indicator_pair(indicators, "Disabled", Color(0.88, 0.28, 0.22, 1.0), -0.34)

		var end_cluster := Spatial.new()
		end_cluster.name = "EndCluster"
		indicators.add_child(end_cluster)
		if Engine.editor_hint:
			end_cluster.owner = get_tree().edited_scene_root

		_create_indicator_pair(end_cluster, "Ready", Color(0.25, 0.8, 0.35, 1.0), 0.34, "EndCluster")
		_create_indicator_pair(end_cluster, "Running", Color(0.86, 0.67, 0.19, 1.0), 0.0, "EndCluster")
		_create_indicator_pair(end_cluster, "Disabled", Color(0.88, 0.28, 0.22, 1.0), -0.34, "EndCluster")

	_ensure_indicator_housing("Indicators")
	_ensure_indicator_housing("Indicators/EndCluster")
	_configure_indicator_pair("Indicators", "Ready", Color(0.25, 0.8, 0.35, 1.0), 0.34)
	_configure_indicator_pair("Indicators", "Running", Color(0.86, 0.67, 0.19, 1.0), 0.0)
	_configure_indicator_pair("Indicators", "Disabled", Color(0.88, 0.28, 0.22, 1.0), -0.34)
	_configure_indicator_pair("Indicators/EndCluster", "Ready", Color(0.25, 0.8, 0.35, 1.0), 0.34, "EndCluster")
	_configure_indicator_pair("Indicators/EndCluster", "Running", Color(0.86, 0.67, 0.19, 1.0), 0.0, "EndCluster")
	_configure_indicator_pair("Indicators/EndCluster", "Disabled", Color(0.88, 0.28, 0.22, 1.0), -0.34, "EndCluster")

	var housing = get_node_or_null("Indicators/Housing")
	if housing:
		housing.visible = true

func _create_indicator_pair(parent: Spatial, suffix: String, color: Color, z_offset: float, variant: String = "") -> void:
	var mesh := MeshInstance.new()
	mesh.name = "Indicator%sMesh%s" % [suffix, variant]
	var button := CubeMesh.new()
	button.size = INDICATOR_BUTTON_SIZE
	mesh.mesh = button
	mesh.translation = Vector3(0, INDICATOR_BUTTON_Y, z_offset)
	mesh.material_override = _build_indicator_material(color)
	parent.add_child(mesh)

	var light := OmniLight.new()
	light.name = "Indicator%sLight%s" % [suffix, variant]
	light.translation = Vector3(0, INDICATOR_LIGHT_HEIGHT, z_offset)
	light.light_color = color
	light.light_energy = 0.46
	light.omni_range = 1.6
	light.shadow_enabled = false
	parent.add_child(light)

	if Engine.editor_hint:
		mesh.owner = get_tree().edited_scene_root
		light.owner = get_tree().edited_scene_root

func _ensure_indicator_collision(parent_path: String, suffix: String, z_offset: float, variant: String = "") -> void:
	var parent = get_node_or_null(parent_path)
	if not parent:
		return
	var body_name = "Indicator%sPlate%s" % [suffix, variant]
	var body: StaticBody = parent.get_node_or_null(body_name)
	if not body:
		body = StaticBody.new()
		body.name = body_name
		body.collision_layer = 2
		body.collision_mask = 0
		parent.add_child(body)
		if Engine.editor_hint:
			body.owner = get_tree().edited_scene_root

	var collider: CollisionShape = body.get_node_or_null("CollisionShape")
	if not collider:
		collider = CollisionShape.new()
		collider.name = "CollisionShape"
		body.add_child(collider)
		if Engine.editor_hint:
			collider.owner = get_tree().edited_scene_root

	if not collider.shape or not collider.shape is BoxShape:
		collider.shape = BoxShape.new()
	if not collider.shape.resource_local_to_scene:
		collider.shape = collider.shape.duplicate()
	collider.shape.extents = INDICATOR_COLLISION_EXTENTS
	body.translation = Vector3(0, INDICATOR_BUTTON_Y - 0.004, z_offset)

func _ensure_indicator_housing(parent_path: String) -> void:
	var parent = get_node_or_null(parent_path)
	if not parent:
		return
	var housing = parent.get_node_or_null("Housing")
	if not housing:
		housing = CSGBox.new()
		housing.name = "Housing"
		parent.add_child(housing)
		if Engine.editor_hint:
			housing.owner = get_tree().edited_scene_root
	housing.width = INDICATOR_HOUSING_SIZE.x
	housing.height = INDICATOR_HOUSING_SIZE.y
	housing.depth = INDICATOR_HOUSING_SIZE.z
	housing.translation = INDICATOR_HOUSING_OFFSET
	housing.material = _build_metal_material(Color(0.12, 0.12, 0.14, 1.0), 0.72, 0.12)
	housing.visible = true

func _configure_indicator_pair(parent_path: String, suffix: String, color: Color, z_offset: float, variant: String = "") -> void:
	var mesh: MeshInstance = get_node_or_null("%s/Indicator%sMesh%s" % [parent_path, suffix, variant])
	if mesh:
		var button := CubeMesh.new()
		button.size = INDICATOR_BUTTON_SIZE
		mesh.mesh = button
		mesh.translation = Vector3(0, INDICATOR_BUTTON_Y, z_offset)
		mesh.material_override = _build_indicator_material(color)

	var light: OmniLight = get_node_or_null("%s/Indicator%sLight%s" % [parent_path, suffix, variant])
	if light:
		light.translation = Vector3(0, INDICATOR_LIGHT_HEIGHT, z_offset)
		light.light_color = color
		light.light_energy = 0.46
		light.omni_range = 1.6
		light.shadow_enabled = false

	_ensure_indicator_collision(parent_path, suffix, z_offset, variant)

func _build_metal_material(albedo: Color, roughness_value: float, metallic_value: float) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.albedo_color = albedo
	material.roughness = roughness_value
	material.metallic = metallic_value
	return material

func _build_indicator_material(color: Color) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 0.22
	material.metallic = 0.05
	material.roughness = 0.28
	return material

func _apply_idle_runtime_defaults() -> void:
	if is_active:
		_internal_speed = speed_x if _should_drive_without_sampling() else 0.0
		_visual_speed = speed_x if _should_drive_without_sampling() else speed_x * idle_speed_ratio
	else:
		_internal_speed = 0.0
		_visual_speed = 0.0

func _ensure_unique_material() -> Material:
	if not has_node("Belt"):
		return null

	var mesh_instance: MeshInstance = $Belt
	var mat = mesh_instance.material_override
	if not mat and mesh_instance.mesh:
		mat = mesh_instance.mesh.surface_get_material(0)

	if mat and not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mesh_instance.material_override = mat
	return mat

func _update_shader_params(mat: ShaderMaterial) -> void:
	if not mat:
		return

	mat.set_shader_param("dir", Vector2(0, 1))
	mat.set_shader_param("phase", _visual_phase)
	mat.set_shader_param("color_a", stripe_dark_color)
	mat.set_shader_param("color_b", stripe_light_color)
	mat.set_shader_param("emission", stripe_emission)
	mat.set_shader_param("softness", 0.08)
	mat.set_shader_param("metalness", 0.18)
	mat.set_shader_param("roughness", 0.82)
	mat.set_shader_param("tiling", stripe_tiling * (length / 8.0))
	mat.set_shader_param("fill", stripe_fill)

func set_speed_x(v: float) -> void:
	speed_x = v
	_speed_x_initialized = true
	_refresh_idle_defaults()

func set_active(v: bool, immediate: bool = false) -> void:
	if is_active == v and not immediate:
		return

	is_active = v
	if not is_active:
		_internal_speed = 0.0
		_visual_speed = 0.0
		_occupancy_hold_timer = 0.0
		_occupied = false
		_running = false
	else:
		_apply_idle_runtime_defaults()

	emit_signal("interaction_started")
	emit_signal("interaction_completed")
	_update_feedback_state(_should_drive_without_sampling())
	_trigger_shader_update()

func set_starts_active(v: bool) -> void:
	starts_active = v
	if Engine.editor_hint:
		is_active = v
		_apply_idle_runtime_defaults()
		_update_feedback_state(_should_drive_without_sampling())
		_trigger_shader_update()

func set_occupancy_detection(v: bool) -> void:
	occupancy_detection = v
	_refresh_idle_defaults()

func set_debounce_time(v: float) -> void:
	debounce_time = max(v, 0.0)

func set_idle_speed_ratio(v: float) -> void:
	idle_speed_ratio = clamp(v, 0.0, 1.0)
	_refresh_idle_defaults()

func set_stripe_dark_color(v: Color) -> void:
	stripe_dark_color = v
	_trigger_shader_update()

func set_stripe_light_color(v: Color) -> void:
	stripe_light_color = v
	_trigger_shader_update()

func set_stripe_emission(v: float) -> void:
	stripe_emission = max(v, 0.0)
	_trigger_shader_update()

func set_stripe_tiling(v: float) -> void:
	stripe_tiling = max(v, 0.01)
	_trigger_shader_update()

func set_stripe_fill(v: float) -> void:
	stripe_fill = clamp(v, 0.0, 1.0)
	_trigger_shader_update()

func set_visual_speed_multiplier(v: float) -> void:
	visual_speed_multiplier = max(v, 0.0)
	_trigger_shader_update()

func set_length(v: float) -> void:
	length = max(v, 0.1)
	_update_scaling()
	_trigger_shader_update()

func set_width(v: float) -> void:
	width = max(v, 0.1)
	_update_scaling()
	_trigger_shader_update()

func _refresh_idle_defaults() -> void:
	if not is_inside_tree():
		return
	if Engine.editor_hint or _internal_speed <= 0.001:
		_apply_idle_runtime_defaults()
	_update_feedback_state(_should_drive_without_sampling())
	_trigger_shader_update()

func _trigger_shader_update() -> void:
	if not is_inside_tree():
		return
	var mat = _ensure_unique_material()
	if mat and mat is ShaderMaterial:
		_update_shader_params(mat)

func set_push_velocity(v: Vector3) -> void:
	if not _speed_x_initialized and v.length() > 0.001:
		speed_x = v.length()
		if debug:
			print("[Conveyor] Captured legacy push_velocity: ", v, " -> speed_x: ", speed_x)
	_refresh_idle_defaults()

func _update_scaling() -> void:
	if not is_inside_tree():
		return

	var col = get_node_or_null("CollisionShape")
	if col and col.shape is BoxShape:
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
		col.shape.extents = Vector3(length / 2.0, 0.6, width / 2.0)

	var ground_col = get_node_or_null("Ground/GroundCollision")
	if ground_col and ground_col.shape is BoxShape:
		if not ground_col.shape.resource_local_to_scene:
			ground_col.shape = ground_col.shape.duplicate()
		ground_col.shape.extents = Vector3(length / 2.0, 0.3, (width / 2.0) + 0.18)

	var belt = get_node_or_null("Belt")
	if belt:
		belt.scale = Vector3(length / 8.0, 1.0, width / 2.0)

	var base_visual = get_node_or_null("Ground/BaseVisual")
	if base_visual:
		base_visual.width = length
		base_visual.height = 0.6
		base_visual.depth = width + 0.45
		base_visual.translation = Vector3(0, -0.38, 0)

	var entry_plate = get_node_or_null("EntryPlate")
	if entry_plate:
		entry_plate.width = 0.45
		entry_plate.height = 0.08
		entry_plate.depth = width + 0.32
		entry_plate.translation = Vector3(-(length / 2.0) + 0.35, 0.02, 0)

	var exit_plate = get_node_or_null("ExitPlate")
	if exit_plate:
		exit_plate.width = 0.45
		exit_plate.height = 0.08
		exit_plate.depth = width + 0.32
		exit_plate.translation = Vector3((length / 2.0) - 0.35, 0.02, 0)

	var side_left = get_node_or_null("SidePlateLeft")
	if side_left:
		side_left.width = max(length - 0.5, 0.2)
		side_left.height = 0.12
		side_left.depth = 0.14
		side_left.translation = Vector3(0, 0.04, (width / 2.0) + 0.18)

	var side_right = get_node_or_null("SidePlateRight")
	if side_right:
		side_right.width = max(length - 0.5, 0.2)
		side_right.height = 0.12
		side_right.depth = 0.14
		side_right.translation = Vector3(0, 0.04, -((width / 2.0) + 0.18))

	var gl = get_node_or_null("GuardrailSegmentLeft")
	if gl:
		gl.translation.z = (width / 2.0) + 0.35
		gl.scale.x = (length / 8.0) * 1.9755

	var gr = get_node_or_null("GuardrailSegmentRight")
	if gr:
		gr.translation.z = -((width / 2.0) + 0.15)
		gr.scale.x = (length / 8.0) * 1.976

	_update_indicator_layout()

func _update_indicator_layout() -> void:
	var indicators = get_node_or_null("Indicators")
	if indicators:
		indicators.translation = Vector3(-(length / 2.0) + 0.35, 0, 0)
		indicators.rotation = Vector3.ZERO

	var end_cluster = get_node_or_null("Indicators/EndCluster")
	if end_cluster:
		end_cluster.translation = Vector3(length - 0.7, 0, 0)
		end_cluster.rotation = Vector3.ZERO

func _get_conveyor_length() -> float:
	return length

func compute_nominal_push_velocity_for_point(_world_position: Vector3) -> Vector3:
	return global_transform.basis.x.normalized() * speed_x

func get_feedback_state() -> String:
	return _feedback_state

func is_running() -> bool:
	return _running

func preview_ready_state() -> void:
	occupancy_detection = true
	is_active = true
	_internal_speed = 0.0
	_visual_speed = speed_x * idle_speed_ratio
	_running = false
	_update_feedback_state(false)
	_trigger_shader_update()

func preview_running_state() -> void:
	occupancy_detection = false
	is_active = true
	_internal_speed = speed_x
	_visual_speed = speed_x
	_running = true
	_update_feedback_state(true)
	_trigger_shader_update()

func preview_disabled_state() -> void:
	is_active = false
	_internal_speed = 0.0
	_visual_speed = 0.0
	_running = false
	_update_feedback_state(false)
	_trigger_shader_update()

func get_snapshot() -> Dictionary:
	return {
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"speed_x": speed_x,
		"length": length,
		"width": width,
		"require_on_floor": require_on_floor,
		"rigid_force_multiplier": rigid_force_multiplier,
		"occupancy_detection": occupancy_detection,
		"debounce_time": debounce_time,
		"idle_speed_ratio": idle_speed_ratio,
		"stripe_dark_color": [stripe_dark_color.r, stripe_dark_color.g, stripe_dark_color.b, stripe_dark_color.a],
		"stripe_light_color": [stripe_light_color.r, stripe_light_color.g, stripe_light_color.b, stripe_light_color.a],
		"stripe_emission": stripe_emission,
		"stripe_tiling": stripe_tiling,
		"stripe_fill": stripe_fill,
		"is_active": is_active,
		"internal_speed": _internal_speed,
		"visual_speed": _visual_speed,
		"visual_phase": _visual_phase,
		"occupancy_hold_timer": _occupancy_hold_timer,
		"occupied": _occupied,
		"feedback_state": _feedback_state
	}

func _apply_snapshot(data: Dictionary) -> void:
	if data.has("speed_x"):
		speed_x = data["speed_x"]
	elif data.has("push_velocity"):
		var pv = data["push_velocity"]
		var mag = Vector3(pv[0], pv[1], pv[2]).length()
		if mag > 0.001:
			speed_x = mag

	if data.has("length"):
		length = data["length"]
	if data.has("width"):
		width = data["width"]
	if data.has("require_on_floor"):
		require_on_floor = data["require_on_floor"]
	if data.has("rigid_force_multiplier"):
		rigid_force_multiplier = data["rigid_force_multiplier"]
	if data.has("occupancy_detection"):
		occupancy_detection = data["occupancy_detection"]
	if data.has("debounce_time"):
		debounce_time = data["debounce_time"]
	if data.has("idle_speed_ratio"):
		idle_speed_ratio = data["idle_speed_ratio"]

	if data.has("pos"):
		var p = data["pos"]
		global_transform.origin = Vector3(p[0], p[1], p[2])

	if data.has("stripe_dark_color"):
		var sd = data["stripe_dark_color"]
		stripe_dark_color = Color(sd[0], sd[1], sd[2], sd[3])
	if data.has("stripe_light_color"):
		var sl = data["stripe_light_color"]
		stripe_light_color = Color(sl[0], sl[1], sl[2], sl[3])
	if data.has("stripe_emission"):
		stripe_emission = data["stripe_emission"]
	if data.has("stripe_tiling"):
		stripe_tiling = data["stripe_tiling"]
	if data.has("stripe_fill"):
		stripe_fill = data["stripe_fill"]
	if data.has("is_active"):
		is_active = data["is_active"]
	if data.has("internal_speed"):
		_internal_speed = data["internal_speed"]
	if data.has("visual_speed"):
		_visual_speed = data["visual_speed"]
	if data.has("visual_phase"):
		_visual_phase = data["visual_phase"]
	if data.has("occupancy_hold_timer"):
		_occupancy_hold_timer = data["occupancy_hold_timer"]
	if data.has("occupied"):
		_occupied = data["occupied"]

	_update_scaling()
	_update_feedback_state(_should_drive_without_sampling())
	_trigger_shader_update()

func restore_snapshot(data: Dictionary) -> void:
	if Engine.editor_hint:
		return
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)

func _physics_process(delta):
	if Engine.editor_hint:
		return
	step(delta)

func step(dt: float) -> void:
	var driveable_bodies = _sample_driveable_bodies()
	var should_push = _update_occupancy_state(driveable_bodies, dt)
	var was_running = _running

	var target_speed = speed_x if should_push else 0.0
	var target_visual_speed = 0.0
	if is_active:
		target_visual_speed = speed_x if should_push else speed_x * idle_speed_ratio

	_internal_speed = move_toward(_internal_speed, target_speed, acceleration * dt)
	_visual_speed = move_toward(_visual_speed, target_visual_speed, acceleration * dt)
	_running = _internal_speed > 0.001

	var visible_speed = (_visual_speed * stripe_tiling / 8.0) * visual_speed_multiplier
	_visual_phase = fmod(_visual_phase + visible_speed * dt, 100.0)
	_update_feedback_state(should_push)
	if _running != was_running:
		if _running:
			emit_signal("activated")
		else:
			emit_signal("deactivated")
	_trigger_shader_update()

	if not _running:
		return

	for body in driveable_bodies:
		var world_push = _compute_runtime_push_velocity_for_body(body)
		if world_push.length() <= 0.001:
			continue
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(world_push)
			if body.has_method("set_external_source_is_static"):
				body.set_external_source_is_static(false)
			if debug:
				print("[Conveyor] push to:", body.get_name() if body.has_method("get_name") else body, " vel:", world_push)
		elif body is RigidBody:
			body.add_central_force(world_push * rigid_force_multiplier * 5.0)

func _sample_driveable_bodies() -> Array:
	_bodies = []
	if Engine.editor_hint or not is_inside_tree():
		return _bodies

	var sampled = get_overlapping_bodies()
	for body in sampled:
		if _can_drive_body(body):
			_bodies.append(body)
	return _bodies

func _can_drive_body(body) -> bool:
	if not is_instance_valid(body):
		return false
	if body == self or is_a_parent_of(body):
		return false
	if require_on_floor and body.has_method("is_on_floor") and not body.is_on_floor():
		return false
	return body.has_method("set_external_velocity") or body is RigidBody

func _update_occupancy_state(driveable_bodies: Array, dt: float) -> bool:
	_occupied = driveable_bodies.size() > 0
	if _occupied:
		_occupancy_hold_timer = debounce_time
	else:
		_occupancy_hold_timer = max(_occupancy_hold_timer - dt, 0.0)

	if not is_active:
		return false
	if not occupancy_detection:
		return true
	return _occupied or _occupancy_hold_timer > 0.0

func _compute_runtime_push_velocity_for_body(body) -> Vector3:
	var nominal = compute_nominal_push_velocity_for_point(body.global_transform.origin)
	var nominal_len = nominal.length()
	if nominal_len <= 0.001:
		return Vector3.ZERO
	return nominal.normalized() * _internal_speed

func _update_feedback_state(should_push: bool) -> void:
	var next_state = "disabled"
	if is_active:
		next_state = "running" if should_push else "ready"

	if next_state == _feedback_state:
		_sync_belt_audio()
		return

	_feedback_state = next_state
	_set_indicator_visible("Ready", _feedback_state == "ready")
	_set_indicator_visible("Running", _feedback_state == "running")
	_set_indicator_visible("Disabled", _feedback_state == "disabled")
	_sync_belt_audio()

func _sync_belt_audio() -> void:
	var sfx = get_node_or_null("SFX Belt")
	if not sfx:
		return

	if _feedback_state == "running":
		if sfx.has_method("play_sfx"):
			sfx.play_sfx()
		elif not sfx.playing:
			sfx.play()
	else:
		if sfx.has_method("stop_sfx"):
			sfx.stop_sfx()
		elif sfx.playing:
			sfx.stop()

func _set_indicator_visible(state_name: String, visible: bool) -> void:
	var indicators = get_node_or_null("Indicators")
	if not indicators:
		return
	var mesh = indicators.get_node_or_null("Indicator%sMesh" % state_name)
	if mesh:
		mesh.visible = visible
	var light = indicators.get_node_or_null("Indicator%sLight" % state_name)
	if light:
		light.visible = visible

	var end_cluster = indicators.get_node_or_null("EndCluster")
	if end_cluster:
		var end_mesh = end_cluster.get_node_or_null("Indicator%sMeshEndCluster" % state_name)
		if end_mesh:
			end_mesh.visible = visible
		var end_light = end_cluster.get_node_or_null("Indicator%sLightEndCluster" % state_name)
		if end_light:
			end_light.visible = visible

func _should_drive_without_sampling() -> bool:
	return is_active and not occupancy_detection
