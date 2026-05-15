extends Area
tool

signal activated()
signal deactivated()
signal interaction_started()
signal interaction_completed()

export(float) var radius := 3.0 setget set_radius
export(float) var angular_speed := 1.0 setget set_angular_speed
export(bool) var starts_active := true setget set_starts_active
export(float) var acceleration := 4.0
export(bool) var require_on_floor := false
export(float) var rigid_force_multiplier := 10.0
export(bool) var debug := false

export(bool) var occupancy_detection := true setget set_occupancy_detection
export(float) var debounce_time := 0.2 setget set_debounce_time
export(float) var idle_speed_ratio := 0.1 setget set_idle_speed_ratio

export(Color) var stripe_dark_color = Color(0.14, 0.15, 0.16, 1.0) setget set_stripe_dark_color
export(Color) var stripe_light_color = Color(0.4, 0.34, 0.16, 1.0) setget set_stripe_light_color
export(float) var stripe_emission = 0.012 setget set_stripe_emission
export(float) var stripe_count = 20.0 setget set_stripe_count
export(float) var stripe_fill = 0.4 setget set_stripe_fill

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

const BELT_HEIGHT := 0.14
const BASE_HEIGHT := 0.72
const BELT_INNER_RATIO := 0.56
const BELT_SEGMENTS := 48

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
		var base_visual := MeshInstance.new()
		base_visual.name = "BaseVisual"
		base_visual.mesh = CylinderMesh.new()
		base_visual.material_override = _build_metal_material(Color(0.24, 0.26, 0.29, 1.0), 0.85, 0.15)
		ground.add_child(base_visual)
		if Engine.editor_hint:
			base_visual.owner = get_tree().edited_scene_root

	for node_name in ["OuterRail", "InnerHub"]:
		if has_node(node_name):
			continue
		var mesh := MeshInstance.new()
		mesh.name = node_name
		mesh.mesh = CylinderMesh.new()
		mesh.material_override = _build_metal_material(Color(0.32, 0.34, 0.37, 1.0), 0.72, 0.1)
		add_child(mesh)
		if Engine.editor_hint:
			mesh.owner = get_tree().edited_scene_root

	if not has_node("InnerWell"):
		var inner_well := MeshInstance.new()
		inner_well.name = "InnerWell"
		inner_well.mesh = CylinderMesh.new()
		inner_well.material_override = _build_metal_material(Color(0.08, 0.09, 0.1, 1.0), 0.92, 0.04)
		add_child(inner_well)
		if Engine.editor_hint:
			inner_well.owner = get_tree().edited_scene_root

	var motion_band = get_node_or_null("MotionBand")
	if motion_band:
		motion_band.visible = false

	if not has_node("Indicators"):
		var indicators := Spatial.new()
		indicators.name = "Indicators"
		add_child(indicators)
		if Engine.editor_hint:
			indicators.owner = get_tree().edited_scene_root

		_create_indicator_pair(indicators, "Ready", Color(0.25, 0.8, 0.35, 1.0))
		_create_indicator_pair(indicators, "Running", Color(0.86, 0.67, 0.19, 1.0))
		_create_indicator_pair(indicators, "Disabled", Color(0.88, 0.28, 0.22, 1.0))

	var housing = get_node_or_null("Indicators/Housing")
	if housing:
		housing.visible = false

func _create_indicator_pair(parent: Spatial, suffix: String, color: Color) -> void:
	var mesh := MeshInstance.new()
	mesh.name = "Indicator%sMesh" % suffix
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.08
	cylinder.height = 0.07
	mesh.mesh = cylinder
	mesh.material_override = _build_indicator_material(color)
	parent.add_child(mesh)

	var light := OmniLight.new()
	light.name = "Indicator%sLight" % suffix
	light.light_color = color
	light.light_energy = 0.62
	light.omni_range = 2.0
	light.shadow_enabled = false
	parent.add_child(light)

	if Engine.editor_hint:
		mesh.owner = get_tree().edited_scene_root
		light.owner = get_tree().edited_scene_root

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
	material.emission = color * 0.2
	material.metallic = 0.05
	material.roughness = 0.22
	return material

func _apply_idle_runtime_defaults() -> void:
	var nominal_speed = _get_nominal_speed()
	if is_active:
		_internal_speed = nominal_speed if _should_drive_without_sampling() else 0.0
		_visual_speed = nominal_speed if _should_drive_without_sampling() else nominal_speed * idle_speed_ratio
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
	mat.set_shader_param("phase", _visual_phase)
	mat.set_shader_param("color_a", stripe_dark_color)
	mat.set_shader_param("color_b", stripe_light_color)
	mat.set_shader_param("emission", stripe_emission)
	mat.set_shader_param("stripe_count", stripe_count)
	mat.set_shader_param("fill", stripe_fill)
	mat.set_shader_param("softness", 0.08)
	mat.set_shader_param("metalness", 0.18)
	mat.set_shader_param("roughness", 0.84)
	mat.set_shader_param("outer_radius", radius)
	mat.set_shader_param("lane_inner_ratio", 0.58)
	mat.set_shader_param("lane_outer_ratio", 0.94)
	mat.set_shader_param("motion_dir", _get_motion_direction())

func set_radius(v: float) -> void:
	radius = max(v, 0.5)
	_update_scaling()
	_trigger_shader_update()

func set_angular_speed(v: float) -> void:
	angular_speed = v
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

func set_stripe_count(v: float) -> void:
	stripe_count = max(v, 2.0)
	_trigger_shader_update()

func set_stripe_fill(v: float) -> void:
	stripe_fill = clamp(v, 0.0, 1.0)
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

func _update_scaling() -> void:
	if not is_inside_tree():
		return

	var collision_shape = get_node_or_null("CollisionShape")
	if collision_shape and collision_shape.shape is CylinderShape:
		if not collision_shape.shape.resource_local_to_scene:
			collision_shape.shape = collision_shape.shape.duplicate()
		collision_shape.shape.radius = radius
		collision_shape.shape.height = 1.2

	var ground_collision = get_node_or_null("Ground/GroundCollision")
	if ground_collision and ground_collision.shape is CylinderShape:
		if not ground_collision.shape.resource_local_to_scene:
			ground_collision.shape = ground_collision.shape.duplicate()
		ground_collision.shape.radius = radius + 0.2
		ground_collision.shape.height = 0.7

	var belt = get_node_or_null("Belt")
	if belt and belt is MeshInstance:
		belt.mesh = _build_annulus_mesh(radius * BELT_INNER_RATIO, radius, BELT_HEIGHT, BELT_SEGMENTS)

	var base_visual = get_node_or_null("Ground/BaseVisual")
	if base_visual and base_visual.mesh is CylinderMesh:
		var base_mesh: CylinderMesh = base_visual.mesh
		base_mesh.top_radius = radius + 0.45
		base_mesh.bottom_radius = radius + 0.55
		base_mesh.height = BASE_HEIGHT
		base_visual.translation = Vector3(0, -0.58, 0)
		if base_visual.material_override and base_visual.material_override is SpatialMaterial:
			base_visual.material_override.albedo_color = Color(0.16, 0.17, 0.19, 1.0)

	var outer_rail = get_node_or_null("OuterRail")
	if outer_rail and outer_rail is MeshInstance:
		outer_rail.mesh = _build_annulus_mesh(radius + 0.02, radius + 0.3, 0.28, BELT_SEGMENTS)
		outer_rail.translation = Vector3(0, 0.06, 0)

	var inner_hub = get_node_or_null("InnerHub")
	if inner_hub and inner_hub.mesh is CylinderMesh:
		var hub_mesh: CylinderMesh = inner_hub.mesh
		hub_mesh.top_radius = max(radius * 0.34, 0.7)
		hub_mesh.bottom_radius = max(radius * 0.38, 0.82)
		hub_mesh.height = 0.5
		inner_hub.translation = Vector3(0, -0.24, 0)
		if inner_hub.material_override and inner_hub.material_override is SpatialMaterial:
			inner_hub.material_override.albedo_color = Color(0.12, 0.13, 0.15, 1.0)

	var inner_well = get_node_or_null("InnerWell")
	if inner_well and inner_well.mesh is CylinderMesh:
		var inner_mesh: CylinderMesh = inner_well.mesh
		inner_mesh.top_radius = max((radius * BELT_INNER_RATIO) - 0.1, 0.35)
		inner_mesh.bottom_radius = max((radius * BELT_INNER_RATIO) - 0.04, 0.4)
		inner_mesh.height = 0.28
		inner_well.translation = Vector3(0, -0.17, 0)

	_update_indicator_layout()

func _build_annulus_mesh(inner_radius: float, outer_radius: float, height: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_height = height * 0.5
	var safe_segments = max(segments, 12)

	for i in range(safe_segments):
		var t0 = float(i) / float(safe_segments)
		var t1 = float(i + 1) / float(safe_segments)
		var a0 = t0 * TAU
		var a1 = t1 * TAU

		var outer_top_0 = Vector3(cos(a0) * outer_radius, half_height, sin(a0) * outer_radius)
		var outer_top_1 = Vector3(cos(a1) * outer_radius, half_height, sin(a1) * outer_radius)
		var inner_top_0 = Vector3(cos(a0) * inner_radius, half_height, sin(a0) * inner_radius)
		var inner_top_1 = Vector3(cos(a1) * inner_radius, half_height, sin(a1) * inner_radius)

		var outer_bottom_0 = Vector3(outer_top_0.x, -half_height, outer_top_0.z)
		var outer_bottom_1 = Vector3(outer_top_1.x, -half_height, outer_top_1.z)
		var inner_bottom_0 = Vector3(inner_top_0.x, -half_height, inner_top_0.z)
		var inner_bottom_1 = Vector3(inner_top_1.x, -half_height, inner_top_1.z)

		_add_quad(st, inner_top_0, outer_top_0, outer_top_1, inner_top_1, Vector3.UP, t0, t1, inner_radius, outer_radius)
		_add_quad(st, outer_bottom_0, inner_bottom_0, inner_bottom_1, outer_bottom_1, Vector3.DOWN, t0, t1, inner_radius, outer_radius)
		_add_quad(st, outer_top_0, outer_bottom_0, outer_bottom_1, outer_top_1, Vector3(cos(a0 + (a1 - a0) * 0.5), 0.0, sin(a0 + (a1 - a0) * 0.5)).normalized(), t0, t1, 0.0, height)
		_add_quad(st, inner_bottom_0, inner_top_0, inner_top_1, inner_bottom_1, -Vector3(cos(a0 + (a1 - a0) * 0.5), 0.0, sin(a0 + (a1 - a0) * 0.5)).normalized(), t0, t1, 0.0, height)

	st.generate_normals()
	return st.commit()

func _update_indicator_layout() -> void:
	var indicator_radius = radius + 0.34
	var indicator_height = -0.16
	_place_perimeter_indicator("Ready", indicator_radius, indicator_height, deg2rad(210.0))
	_place_perimeter_indicator("Running", indicator_radius, indicator_height, deg2rad(330.0))
	_place_perimeter_indicator("Disabled", indicator_radius, indicator_height, deg2rad(90.0))

func _place_perimeter_indicator(state_name: String, indicator_radius: float, indicator_height: float, angle: float) -> void:
	var mesh = get_node_or_null("Indicators/Indicator%sMesh" % state_name)
	if mesh:
		mesh.translation = Vector3(cos(angle) * indicator_radius, indicator_height, sin(angle) * indicator_radius)
	var light = get_node_or_null("Indicators/Indicator%sLight" % state_name)
	if light:
		light.translation = Vector3(cos(angle) * indicator_radius, indicator_height + 0.1, sin(angle) * indicator_radius)

func _get_motion_direction() -> float:
	return 1.0 if angular_speed >= 0.0 else -1.0

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, u0: float, u1: float, v0: float, v1: float) -> void:
	st.add_normal(normal)
	st.add_uv(Vector2(u0, v0))
	st.add_vertex(a)
	st.add_normal(normal)
	st.add_uv(Vector2(u0, v1))
	st.add_vertex(b)
	st.add_normal(normal)
	st.add_uv(Vector2(u1, v1))
	st.add_vertex(c)

	st.add_normal(normal)
	st.add_uv(Vector2(u0, v0))
	st.add_vertex(a)
	st.add_normal(normal)
	st.add_uv(Vector2(u1, v1))
	st.add_vertex(c)
	st.add_normal(normal)
	st.add_uv(Vector2(u1, v0))
	st.add_vertex(d)

func compute_nominal_push_velocity_for_point(world_position: Vector3) -> Vector3:
	return _get_tangent_direction(world_position) * _get_nominal_speed()

func get_feedback_state() -> String:
	return _feedback_state

func is_running() -> bool:
	return _running

func preview_ready_state() -> void:
	occupancy_detection = true
	is_active = true
	_internal_speed = 0.0
	_visual_speed = _get_nominal_speed() * idle_speed_ratio
	_running = false
	_update_feedback_state(false)
	_trigger_shader_update()

func preview_running_state() -> void:
	occupancy_detection = false
	is_active = true
	_internal_speed = _get_nominal_speed()
	_visual_speed = _get_nominal_speed()
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
		"radius": radius,
		"angular_speed": angular_speed,
		"require_on_floor": require_on_floor,
		"rigid_force_multiplier": rigid_force_multiplier,
		"occupancy_detection": occupancy_detection,
		"debounce_time": debounce_time,
		"idle_speed_ratio": idle_speed_ratio,
		"stripe_dark_color": [stripe_dark_color.r, stripe_dark_color.g, stripe_dark_color.b, stripe_dark_color.a],
		"stripe_light_color": [stripe_light_color.r, stripe_light_color.g, stripe_light_color.b, stripe_light_color.a],
		"stripe_emission": stripe_emission,
		"stripe_count": stripe_count,
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
	if data.has("radius"):
		radius = data["radius"]
	if data.has("angular_speed"):
		angular_speed = data["angular_speed"]
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
	if data.has("stripe_count"):
		stripe_count = data["stripe_count"]
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

	var nominal_speed = _get_nominal_speed()
	var target_speed = nominal_speed if should_push else 0.0
	var target_visual_speed = 0.0
	if is_active:
		target_visual_speed = nominal_speed if should_push else nominal_speed * idle_speed_ratio

	_internal_speed = move_toward(_internal_speed, target_speed, acceleration * dt)
	_visual_speed = move_toward(_visual_speed, target_visual_speed, acceleration * dt)
	_running = _internal_speed > 0.001

	var circumference = max(TAU * radius, 0.001)
	var visible_cycles = _visual_speed / circumference
	_visual_phase = fmod(_visual_phase + visible_cycles * dt, 100.0)
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
	return _get_tangent_direction(body.global_transform.origin) * _internal_speed

func _get_tangent_direction(world_position: Vector3) -> Vector3:
	var center = global_transform.origin
	var up = global_transform.basis.y.normalized()
	var radial = world_position - center
	radial -= up * radial.dot(up)
	if radial.length() <= 0.001:
		return global_transform.basis.x.normalized()
	var tangent = up.cross(radial.normalized()).normalized()
	if angular_speed < 0.0:
		tangent = -tangent
	return tangent

func _get_nominal_speed() -> float:
	return abs(angular_speed) * radius

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
	var mesh = get_node_or_null("Indicators/Indicator%sMesh" % state_name)
	if mesh:
		mesh.visible = visible
	var light = get_node_or_null("Indicators/Indicator%sLight" % state_name)
	if light:
		light.visible = visible

func _should_drive_without_sampling() -> bool:
	return is_active and not occupancy_detection
