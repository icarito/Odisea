extends Spatial
class_name GasParticleManager

export(int) var pool_size := 512
export(float) var default_max_lifetime := 6.0
export(float) var default_base_scale := 2.2
export(float) var viscosity := 0.8
export(float) var buoyancy := -1.2
export(float) var decay_rate := 1.0
export(Color) var default_color := Color(0.62, 0.78, 0.74, 0.82)
export(Color) var ignition_color := Color(1.0, 0.42, 0.08, 0.82)
export(float, -1.0, 1.0) var distance_luminance_shift := -0.4
export(float, -1.0, 1.0) var distance_r_shift := 0.0
export(float, -1.0, 1.0) var distance_g_shift := 0.0
export(float, -1.0, 1.0) var distance_b_shift := 0.0

# Set by GasArea3D from shape extents — used to normalize particle distance
var volume_radius := 4.0
export(bool) var collide_with_world := true
export(int, LAYERS_3D_PHYSICS) var world_collision_mask := 1
export(float) var collision_margin := 0.08
export(float) var collision_damping := 0.28
export(float) var collision_slide := 0.68
export(float) var flipbook_frames_per_second := 16.0
export(float) var anim_speed_base := 1.0
export(float) var anim_speed_velocity_factor := 0.2
export(String, FILE, "*.shader") var shader_path := "res://core_v2/systems/gas/shaders/gas_flipbook.shader"
export(String, FILE, "*.png,*.tga,*.webp,*.jpg") var default_atlas_path := "res://assets/flipbook_particles/assets/clouds/textures/cloud_01.tga"

var particles: Array = []
var multimesh_instance: MultiMeshInstance = null
var multimesh: MultiMesh = null

var _next_spawn_index := 0
var _hidden_transform := Transform.IDENTITY
var _gas_material: ShaderMaterial = null

func _init():
	add_to_group("replay_sync")

func _ready():
	_hidden_transform.basis = _hidden_transform.basis.scaled(Vector3.ZERO)
	_ensure_multimesh_instance()
	_setup_pool()
	_sync_all_instances()

func _ensure_multimesh_instance() -> void:
	multimesh_instance = get_node_or_null("GasMultiMeshInstance")
	if multimesh_instance == null:
		multimesh_instance = MultiMeshInstance.new()
		multimesh_instance.name = "GasMultiMeshInstance"
		add_child(multimesh_instance)

	multimesh_instance.cast_shadow = 0 # GeometryInstance.SHADOW_CASTING_SETTING_OFF
	multimesh_instance.extra_cull_margin = 32.0

	multimesh = multimesh_instance.multimesh
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh_instance.multimesh = multimesh

	if multimesh.instance_count > 0:
		multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.color_format = MultiMesh.COLOR_FLOAT
	multimesh.custom_data_format = MultiMesh.CUSTOM_DATA_FLOAT
	multimesh.instance_count = max(1, pool_size)
	multimesh.visible_instance_count = multimesh.instance_count

	if multimesh.mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		multimesh.mesh = quad

	_ensure_material()

func _ensure_material() -> void:
	if multimesh_instance.material_override is ShaderMaterial:
		_gas_material = multimesh_instance.material_override
	else:
		_gas_material = ShaderMaterial.new()
		var shader = load(shader_path)
		if shader:
			_gas_material.shader = shader
		multimesh_instance.material_override = _gas_material

	if _gas_material and _gas_material.shader:
		var atlas = load(default_atlas_path)
		if atlas:
			_gas_material.set_shader_param("smoke_atlas", atlas)
		_gas_material.set_shader_param("frames_per_second", flipbook_frames_per_second)

func _setup_pool() -> void:
	pool_size = max(1, pool_size)
	particles.clear()
	for i in range(pool_size):
		particles.append({
			"active": false,
			"position": Vector3.ZERO,
			"velocity": Vector3.ZERO,
			"lifetime": 0.0,
			"max_lifetime": default_max_lifetime,
			"base_scale": default_base_scale,
			"color": default_color,
			"combustion": false,
			"anim_time": 0.0,
			"anim_offset": _get_deterministic_anim_offset(i)
		})

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	step(delta)

func step(delta: float) -> void:
	if multimesh == null:
		return

	var gravity_y := _get_local_gravity_y()
	var friction := clamp(1.0 - viscosity * delta, 0.0, 1.0)

	for i in range(particles.size()):
		var p: Dictionary = particles[i]
		if not bool(p["active"]):
			continue

		var velocity: Vector3 = p["velocity"]
		velocity.y += buoyancy * gravity_y * delta
		velocity *= friction

		var position: Vector3 = p["position"]
		var move_result: Dictionary = _move_particle_with_collision(position, velocity, delta)
		position = move_result["position"]
		velocity = move_result["velocity"]

		var lifetime := float(p["lifetime"]) + delta * max(decay_rate, 0.0)
		var max_lifetime := max(float(p["max_lifetime"]), 0.001)

		var speed := velocity.length()
		var p_anim_mod: float = float(p.get("anim_speed_mod", 1.0))
		var anim_delta: float = delta * (anim_speed_base * p_anim_mod + speed * anim_speed_velocity_factor)

		p["velocity"] = velocity
		p["position"] = position
		p["lifetime"] = lifetime
		p["anim_time"] = float(p.get("anim_time", 0.0)) + anim_delta

		if lifetime >= max_lifetime:
			p["active"] = false
			p["combustion"] = false
			p["color"] = default_color
			particles[i] = p
			_hide_instance(i)
		else:
			particles[i] = p
			_sync_instance(i)

func _get_local_gravity_y() -> float:
	var gravity_world = get_node_or_null("/root/GravityWorld")
	if gravity_world and gravity_world.has_method("get_physical_gravity"):
		var gravity_vec: Vector3 = gravity_world.get_physical_gravity(global_transform.origin)
		if gravity_vec.length_squared() > 0.000001:
			return gravity_vec.y

	var default_gravity := 9.8
	if ProjectSettings.has_setting("physics/3d/default_gravity"):
		default_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	return -abs(default_gravity)

func _move_particle_with_collision(local_position: Vector3, local_velocity: Vector3, delta: float) -> Dictionary:
	var target_position: Vector3 = local_position + local_velocity * delta
	if not collide_with_world:
		return {
			"position": target_position,
			"velocity": local_velocity
		}
	if local_position.distance_squared_to(target_position) <= 0.000001:
		return {
			"position": target_position,
			"velocity": local_velocity
		}

	var space_state = get_world().direct_space_state
	var from_world: Vector3 = global_transform.xform(local_position)
	var to_world: Vector3 = global_transform.xform(target_position)
	var result: Dictionary = space_state.intersect_ray(from_world, to_world, [], world_collision_mask, true, false)
	if result.empty():
		return {
			"position": target_position,
			"velocity": local_velocity
		}

	var normal: Vector3 = result.get("normal", Vector3.UP).normalized()
	var hit_position: Vector3 = result.get("position", from_world)
	var world_velocity: Vector3 = global_transform.basis.xform(local_velocity)
	var normal_speed: float = world_velocity.dot(normal)
	if normal_speed < 0.0:
		var normal_component: Vector3 = normal * normal_speed
		var tangent_component: Vector3 = world_velocity - normal_component
		world_velocity = (tangent_component * collision_slide) - (normal_component * collision_damping)

	var adjusted_world_position: Vector3 = hit_position + normal * max(collision_margin, 0.0)
	return {
		"position": to_local(adjusted_world_position),
		"velocity": global_transform.basis.xform_inv(world_velocity)
	}

func emit_particle(local_position: Vector3, local_velocity: Vector3 = Vector3.ZERO, max_lifetime: float = -1.0, base_scale: float = -1.0, color: Color = Color(0, 0, 0, -1)) -> int:
	var index := _next_spawn_index
	_next_spawn_index = (_next_spawn_index + 1) % particles.size()

	var p: Dictionary = particles[index]
	p["active"] = true
	p["position"] = local_position
	p["velocity"] = local_velocity
	p["lifetime"] = 0.0
	p["max_lifetime"] = default_max_lifetime if max_lifetime <= 0.0 else max_lifetime
	
	var base_s = default_base_scale if base_scale <= 0.0 else base_scale
	p["base_scale"] = base_s * (0.5 + _get_deterministic_anim_offset(index + 777) * 1.0)
	
	var c = default_color if color.a < 0.0 else color
	var dist := local_position.length()
	p["color"] = _get_varied_color(c, index, dist)
	
	p["combustion"] = false
	p["anim_time"] = 0.0
	p["anim_offset"] = _get_deterministic_anim_offset(index)
	p["anim_speed_mod"] = 0.5 + _get_deterministic_anim_offset(index + 1234) * 1.5
	particles[index] = p
	_sync_instance(index)
	return index

func _get_deterministic_anim_offset(index: int) -> float:
	var hashed := int((index * 1103515245 + 12345) & 0x7fffffff)
	return float(hashed % 1000) / 1000.0

func emit_burst(local_origin: Vector3, count: int, radius: float = 1.0, initial_speed: float = 0.0) -> void:
	var safe_count := max(0, count)
	for i in range(safe_count):
		var angle := TAU * float(i) / float(max(1, safe_count))
		var ring := radius * (0.35 + 0.65 * float((i % 7) + 1) / 7.0)
		var offset := Vector3(cos(angle) * ring, 0.0, -sin(angle) * ring)
		var velocity := offset.normalized() * initial_speed if offset.length_squared() > 0.000001 else Vector3.ZERO
		emit_particle(local_origin + offset, velocity)

func apply_velocity_impulse(global_origin: Vector3, radius: float, velocity: Vector3, strength: float, delta: float) -> void:
	var safe_radius := max(radius, 0.001)
	var local_origin := to_local(global_origin)
	var local_velocity := global_transform.basis.xform_inv(velocity)

	for i in range(particles.size()):
		var p: Dictionary = particles[i]
		if not bool(p["active"]):
			continue

		var position: Vector3 = p["position"]
		var distance := position.distance_to(local_origin)
		if distance > safe_radius:
			continue

		var falloff := 1.0 - (distance / safe_radius)
		p["velocity"] = Vector3(p["velocity"]) + local_velocity * strength * falloff * delta
		particles[i] = p

func set_particle_combustion(index: int, active: bool) -> void:
	if index < 0 or index >= particles.size():
		return
	var p: Dictionary = particles[index]
	if not bool(p["active"]):
		return
	p["combustion"] = active
	var c = ignition_color if active else default_color
	var dist := Vector3(p["position"]).length()
	p["color"] = _get_varied_color(c, index, dist)
	particles[index] = p
	_sync_instance(index)

func clear_all() -> void:
	for i in range(particles.size()):
		var p: Dictionary = particles[i]
		p["active"] = false
		p["combustion"] = false
		p["lifetime"] = 0.0
		p["velocity"] = Vector3.ZERO
		p["anim_time"] = 0.0
		particles[i] = p
		_hide_instance(i)

func get_active_particle_indices() -> Array:
	var indices := []
	for i in range(particles.size()):
		if bool(particles[i]["active"]):
			indices.append(i)
	return indices

func get_particle_world_position(index: int) -> Vector3:
	if index < 0 or index >= particles.size():
		return global_transform.origin
	return global_transform.xform(Vector3(particles[index]["position"]))

func _sync_all_instances() -> void:
	for i in range(particles.size()):
		if bool(particles[i]["active"]):
			_sync_instance(i)
		else:
			_hide_instance(i)

func _sync_instance(index: int) -> void:
	if multimesh == null:
		return
	var p: Dictionary = particles[index]
	var age := clamp(float(p["lifetime"]) / max(float(p["max_lifetime"]), 0.001), 0.0, 1.0)
	var frame_time := float(p.get("anim_time", 0.0)) + float(p.get("anim_offset", 0.0))
	var scale := max(float(p["base_scale"]), 0.001) * (0.9 + 0.6 * age)
	var xform := Transform.IDENTITY
	xform.origin = Vector3(p["position"])
	xform.basis = xform.basis.scaled(Vector3(scale, scale, scale))
	multimesh.set_instance_transform(index, xform)
	multimesh.set_instance_color(index, Color(p["color"]))
	multimesh.set_instance_custom_data(index, Color(age, 1.0 if bool(p["combustion"]) else 0.0, frame_time, 1.0))

func _hide_instance(index: int) -> void:
	if multimesh == null:
		return
	multimesh.set_instance_transform(index, _hidden_transform)
	multimesh.set_instance_color(index, Color(0, 0, 0, 0))
	multimesh.set_instance_custom_data(index, Color(0, 0, 0, 0))

func get_snapshot() -> Dictionary:
	var active_particles := []
	for i in range(particles.size()):
		var p: Dictionary = particles[i]
		if not bool(p["active"]):
			continue
		active_particles.append({
			"i": i,
			"p": Vector3(p["position"]),
			"v": Vector3(p["velocity"]),
			"t": float(p["lifetime"]),
			"m": float(p["max_lifetime"]),
			"s": float(p["base_scale"]),
			"c": Color(p["color"]),
			"b": bool(p["combustion"]),
			"a": float(p.get("anim_time", 0.0)),
			"o": float(p.get("anim_offset", 0.0))
		})

	return {
		"pool_size": particles.size(),
		"next_spawn_index": _next_spawn_index,
		"particles": active_particles
	}

func restore_snapshot(data: Dictionary) -> void:
	if particles.empty():
		_setup_pool()

	clear_all()
	_next_spawn_index = int(data.get("next_spawn_index", 0)) % int(max(1, particles.size()))

	var active_particles: Array = data.get("particles", [])
	for entry in active_particles:
		if not entry is Dictionary:
			continue
		var index := int(entry.get("i", -1))
		if index < 0 or index >= particles.size():
			continue

		var p: Dictionary = particles[index]
		p["active"] = true
		p["position"] = Vector3(entry.get("p", Vector3.ZERO))
		p["velocity"] = Vector3(entry.get("v", Vector3.ZERO))
		p["lifetime"] = float(entry.get("t", 0.0))
		p["max_lifetime"] = float(entry.get("m", default_max_lifetime))
		p["base_scale"] = float(entry.get("s", default_base_scale))
		
		var raw_color = Color(entry.get("c", default_color))
		# If it's a restored snapshot, we can just use the color directly or re-apply variance.
		# Since we save the exact color in get_snapshot(), we don't need to re-vary it here.
		p["color"] = raw_color
		
		p["combustion"] = bool(entry.get("b", false))
		p["anim_time"] = float(entry.get("a", 0.0))
		p["anim_offset"] = float(entry.get("o", _get_deterministic_anim_offset(index)))
		p["anim_speed_mod"] = 0.5 + _get_deterministic_anim_offset(index + 1234) * 1.5
		particles[index] = p
		_sync_instance(index)

func _get_varied_color(base_c: Color, index: int, distance: float = 0.0) -> Color:
	# Normalize distance (0 = center, 1 = edge of volume)
	var norm_dist := clamp(distance / max(volume_radius, 0.001), 0.0, 1.0)

	return Color(
		clamp(base_c.r + norm_dist * (distance_luminance_shift + distance_r_shift), 0.0, 1.0),
		clamp(base_c.g + norm_dist * (distance_luminance_shift + distance_g_shift), 0.0, 1.0),
		clamp(base_c.b + norm_dist * (distance_luminance_shift + distance_b_shift), 0.0, 1.0),
		base_c.a
	)
