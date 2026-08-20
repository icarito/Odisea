extends Spatial
class_name GasParticleManager

export(int) var pool_size := 128
# --- Presupuesto de pool en movil ---------------------------------------------------
# El pool completo se recorre entero cada frame de fisica y cada particula es un quad del
# MultiMesh que, en GLES2, se reenvia por cada luz que la alcanza. En movil se usa una
# fraccion del pool y se compensa agrandando las particulas que quedan: la cobertura en
# pantalla se mantiene parecida con mucho menos trabajo.
export(float, 0.05, 1.0, 0.05) var mobile_pool_scale := 0.4
export(float, 1.0, 4.0, 0.05) var mobile_scale_compensation := 1.6
# Ajuste por FPS, con la misma forma que LightPathV2: por debajo del piso encoge el pool,
# por encima del techo lo devuelve, y entre medio no toca nada (evita oscilar).
export(bool) var adaptive_pool_on_mobile := true
export(float, 5.0, 60.0, 1.0) var pool_fps_floor := 24.0
export(float, 5.0, 90.0, 1.0) var pool_fps_ceiling := 45.0
export(float, 0.05, 1.0, 0.05) var min_pool_fraction := 0.25
export(float, 0.25, 5.0, 0.25) var pool_adapt_interval := 1.5
# LOD: de lejos el gas es apenas unos pixeles borrosos, así que congelarlo (dejar de
# simular, no de dibujar) no se nota. Mismo patrón que AirlockLOD.gd — solo toca
# _physics_process, nunca colisión, para no meter drift en replays deterministas.
export(bool) var distance_lod_enabled := true
export(float, 5.0, 100.0, 1.0) var lod_distance := 12.0
export(float, 0.0, 20.0, 0.5) var lod_hysteresis := 4.0
export(int, 1, 60) var lod_frames_between_checks := 10
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
# Skip the per-particle world raycast when a particle is moving slower than this (settled
# gas can't collide with anything new). Set to 0.0 to restore exact per-frame raycasting.
export(float) var raycast_min_speed := 0.05
export(int, LAYERS_3D_PHYSICS) var world_collision_mask := 1
export(float) var collision_margin := 0.08
export(float) var collision_damping := 0.28
export(float) var collision_slide := 0.68
export(float) var flipbook_frames_per_second := 16.0
export(bool) var use_dither := true setget set_use_dither
export(float) var anim_speed_base := 1.0
export(float) var anim_speed_velocity_factor := 0.2
export(String, FILE, "*.shader") var shader_path := "res://core_v2/systems/gas/shaders/gas_flipbook.shader"
export(String, FILE, "*.png,*.tga,*.webp,*.jpg") var default_atlas_path := "res://assets/flipbook_particles/assets/clouds/textures/cloud_01.tga"

var particles: Array = []
var multimesh_instance: MultiMeshInstance = null
var multimesh: MultiMesh = null

var _next_spawn_index := 0
# Cuantas particulas del pool estan realmente en uso. step() y emit_particle() se limitan
# a este numero, asi que reducirlo ahorra CPU de verdad, no solo instancias dibujadas.
var _pool_limit := 0
var _pool_adapt_timer := 0.0
var _scale_boost := 1.0
var _gravity_world: Node = null
var _gravity_world_resolved := false
var _default_gravity_y := -9.8
# Buffer reutilizado para el volcado en bloque del MultiMesh: 20 floats por instancia
# (12 de transform, 4 de color, 4 de custom data). Layout verificado contra el motor.
const BULK_FLOATS_PER_INSTANCE := 20
var _bulk := PoolRealArray()
var _hidden_transform := Transform.IDENTITY
var _gas_material: ShaderMaterial = null
# Límite visual opcional, en coordenadas locales. INF conserva el comportamiento normal.
var vertical_ceiling_y := INF
var _lod = null

func _init():
	add_to_group("replay_sync")

func _ready():
	_hidden_transform.basis = _hidden_transform.basis.scaled(Vector3.ZERO)
	_ensure_multimesh_instance()
	_setup_pool()
	_apply_pool_limit(_initial_pool_limit())
	_sync_all_instances()
	if distance_lod_enabled:
		var lod_script = load("res://core_v2/systems/PhysicsProcessLOD.gd")
		_lod = lod_script.new(global_transform.origin, get_tree(), lod_distance, lod_hysteresis, lod_frames_between_checks)
		var budget = get_node_or_null("/root/AdaptiveVisualBudget")
		if budget != null and budget.has_method("register_consumer"):
			budget.register_consumer(self, "_on_visual_budget_level_changed")

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
		_gas_material.set_shader_param("use_dither", use_dither)

func set_use_dither(value: bool) -> void:
	use_dither = value
	if _gas_material:
		_gas_material.set_shader_param("use_dither", use_dither)

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

func _is_mobile_profile() -> bool:
	if OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE") in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


func _initial_pool_limit() -> int:
	if not _is_mobile_profile():
		return particles.size()
	return int(max(1, round(particles.size() * mobile_pool_scale)))


# Cambia cuantas particulas se simulan y se dibujan. Las que quedan fuera se ocultan una
# sola vez; no se recorren mas hasta que el limite vuelva a subir.
func _apply_pool_limit(limit: int) -> void:
	var new_limit: int = int(clamp(limit, 1, particles.size()))
	if new_limit == _pool_limit:
		return
	var previous := _pool_limit
	_pool_limit = new_limit
	if multimesh != null:
		# Dimensionar el MultiMesh al pool efectivo, no dejarlo en pool_size. set_as_bulk_array
		# exige cubrir instance_count entero, asi que con 48 instancias y 12 en uso se
		# escribian 48*20 floats por frame y por manager para nada. Con instance_count
		# ajustado, el volcado cuesta proporcional a lo que de verdad se simula.
		if multimesh.instance_count != _pool_limit:
			multimesh.instance_count = _pool_limit
		multimesh.visible_instance_count = _pool_limit
	if _pool_limit < previous:
		for i in range(_pool_limit, previous):
			# Solo se apaga la particula en la logica. Ocultarla en el MultiMesh seria
			# escribir en un indice que la linea de arriba acaba de eliminar al achicar
			# instance_count: "Index p_index = 55 is out of bounds (multimesh->size = 51)".
			particles[i]["active"] = false
	if _next_spawn_index >= _pool_limit:
		_next_spawn_index = 0
	# Agrandar lo que queda para conservar cobertura en pantalla con menos quads. Se guarda
	# como multiplicador y se aplica en _sync_instance: escribirlo sobre particles[] no
	# sirve porque emit_particle() reescribe base_scale en cada emision.
	_scale_boost = 1.0
	if _is_mobile_profile() and mobile_scale_compensation > 1.0:
		var coverage: float = float(particles.size()) / float(max(_pool_limit, 1))
		_scale_boost = min(mobile_scale_compensation, sqrt(coverage))


# AdaptiveVisualBudget arranca en 0 y sube de a poco si el dispositivo aguanta (nunca
# instancia ni destruye nada — esta instancia ya existe siempre, solo se ensancha o
# acorta el radio del LOD de distancia ya creado en _ready()). level 0 = solo lo que
# el jugador toca de cerca; level == max_level = el lod_distance configurado por nivel.
func _on_visual_budget_level_changed(level: int, max_level: int) -> void:
	if _lod == null:
		return
	var floor_distance: float = min(lod_distance, 4.0)
	var t: float = float(level) / float(max(max_level, 1))
	_lod.set_distance(lerp(floor_distance, lod_distance, t))


func _adapt_pool_to_fps(delta: float) -> void:
	if not adaptive_pool_on_mobile or not _is_mobile_profile():
		return
	_pool_adapt_timer += delta
	if _pool_adapt_timer < pool_adapt_interval:
		return
	_pool_adapt_timer = 0.0
	var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
	var floor_limit: int = int(max(1, round(particles.size() * min_pool_fraction)))
	var target_limit: int = int(max(1, round(particles.size() * mobile_pool_scale)))
	if fps < pool_fps_floor and _pool_limit > floor_limit:
		_apply_pool_limit(int(max(floor_limit, _pool_limit * 0.7)))
	elif fps > pool_fps_ceiling and _pool_limit < target_limit:
		_apply_pool_limit(int(min(target_limit, _pool_limit + max(1, target_limit / 4))))


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	_adapt_pool_to_fps(delta)
	if _lod != null and not _lod.should_process():
		return
	step(delta)

func step(delta: float) -> void:
	if multimesh == null:
		return

	var gravity_y := _get_local_gravity_y()
	var friction := clamp(1.0 - viscosity * delta, 0.0, 1.0)

	for i in range(_effective_pool()):
		var p: Dictionary = particles[i]
		if not bool(p["active"]):
			continue

		var velocity: Vector3 = p["velocity"]
		velocity.y += buoyancy * gravity_y * delta
		velocity *= friction

		var position: Vector3 = p["position"]
		# Camino rapido: cuando no hay consulta de colision posible, el movimiento es una
		# suma y no hace falta llamar a _move_particle_with_collision, que devuelve un
		# Dictionary nuevo POR PARTICULA Y POR FRAME. Con los cuatro managers de Dome_Intro
		# (todos con collide_with_world = false) eso eran ~10k asignaciones de heap por
		# segundo, con su boxing de Variant, para un resultado identico a position += v*dt.
		if _needs_collision_query(velocity):
			var move_result: Dictionary = _move_particle_with_collision(position, velocity, delta)
			position = move_result["position"]
			velocity = move_result["velocity"]
		else:
			position += velocity * delta
		if position.y > vertical_ceiling_y:
			position.y = vertical_ceiling_y
			velocity.y = min(velocity.y, 0.0)

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
		else:
			particles[i] = p

	# Un solo volcado por frame en vez de 3 llamadas al MultiMesh por particula. Con ~93
	# particulas vivas eran ~279 cruces al VisualServer por frame, cada uno con boxing de
	# Variant; ahora es una llamada con un PoolRealArray preasignado.
	_flush_bulk()

# Se llama una vez por frame y por manager. La busqueda del autoload y las dos consultas a
# ProjectSettings se resolvian cada vez; ahora quedan cacheadas. ProjectSettings.get_setting
# hace lookup por string y no es barato en un bucle de frame.
func _get_local_gravity_y() -> float:
	if not _gravity_world_resolved:
		_gravity_world_resolved = true
		_gravity_world = get_node_or_null("/root/GravityWorld")
		if _gravity_world != null and not _gravity_world.has_method("get_physical_gravity"):
			_gravity_world = null
		var default_gravity := 9.8
		if ProjectSettings.has_setting("physics/3d/default_gravity"):
			default_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
		_default_gravity_y = -abs(default_gravity)

	if is_instance_valid(_gravity_world):
		var gravity_vec: Vector3 = _gravity_world.get_physical_gravity(global_transform.origin)
		if gravity_vec.length_squared() > 0.000001:
			return gravity_vec.y
	return _default_gravity_y

# Espeja las salidas tempranas de _move_particle_with_collision: si alguna se cumple, esa
# funcion solo devuelve position + velocity * delta con la velocidad intacta, asi que se
# puede evitar la llamada entera sin cambiar el resultado.
func _needs_collision_query(local_velocity: Vector3) -> bool:
	if not collide_with_world:
		return false
	if raycast_min_speed > 0.0 and local_velocity.length_squared() < raycast_min_speed * raycast_min_speed:
		return false
	return local_velocity.length_squared() > 0.000001


func _move_particle_with_collision(local_position: Vector3, local_velocity: Vector3, delta: float) -> Dictionary:
	var target_position: Vector3 = local_position + local_velocity * delta
	if not collide_with_world:
		return {
			"position": target_position,
			"velocity": local_velocity
		}
	# Settled gas (very low speed) can't hit anything new — skip the raycast.
	if raycast_min_speed > 0.0 and local_velocity.length_squared() < raycast_min_speed * raycast_min_speed:
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
	_next_spawn_index = (_next_spawn_index + 1) % _effective_pool()

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

func set_particle_combustion(index: int, active: bool, override_color: Color = Color(0, 0, 0, -1)) -> void:
	if index < 0 or index >= particles.size():
		return
	var p: Dictionary = particles[index]
	if not bool(p["active"]):
		return
	p["combustion"] = active
	var c = ignition_color if active else default_color
	if override_color.a >= 0.0:
		c = override_color
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
	# Hasta el pool EFECTIVO, no hasta particles.size(): el MultiMesh se dimensiona al pool
	# efectivo (en movil es una fraccion del total), asi que recorrer el array entero escribe
	# fuera de rango. Las particulas por encima del limite ya quedaron inactivas en
	# _apply_pool_limit y no tienen instancia que sincronizar.
	var limite: int = _effective_pool()
	for i in range(limite):
		if bool(particles[i]["active"]):
			_sync_instance(i)
		else:
			_hide_instance(i)

func _effective_pool() -> int:
	if _pool_limit <= 0:
		_pool_limit = particles.size()
	return int(min(_pool_limit, particles.size()))


# Escribe TODAS las instancias del MultiMesh de una vez. set_as_bulk_array exige cubrir
# instance_count completo, asi que las que estan fuera del pool efectivo o inactivas se
# escriben con escala cero (equivalente a _hide_instance).
func _flush_bulk() -> void:
	if multimesh == null:
		return
	var count: int = min(multimesh.instance_count, _effective_pool())
	if count <= 0:
		return
	var needed: int = count * BULK_FLOATS_PER_INSTANCE
	if _bulk.size() != needed:
		_bulk.resize(needed)
	for i in range(count):
		var base: int = i * BULK_FLOATS_PER_INSTANCE
		if i >= particles.size() or not bool(particles[i]["active"]):
			for k in range(BULK_FLOATS_PER_INSTANCE):
				_bulk.set(base + k, 0.0)
			continue
		var p: Dictionary = particles[i]
		var age := clamp(float(p["lifetime"]) / max(float(p["max_lifetime"]), 0.001), 0.0, 1.0)
		var frame_time := float(p.get("anim_time", 0.0)) + float(p.get("anim_offset", 0.0))
		var scale := max(float(p["base_scale"]), 0.001) * (0.9 + 0.6 * age) * _scale_boost
		var origin: Vector3 = p["position"]
		# Filas de la base (escala uniforme) con la componente de origin al final de cada una.
		_bulk.set(base + 0, scale); _bulk.set(base + 1, 0.0);   _bulk.set(base + 2, 0.0);   _bulk.set(base + 3, origin.x)
		_bulk.set(base + 4, 0.0);   _bulk.set(base + 5, scale); _bulk.set(base + 6, 0.0);   _bulk.set(base + 7, origin.y)
		_bulk.set(base + 8, 0.0);   _bulk.set(base + 9, 0.0);   _bulk.set(base + 10, scale); _bulk.set(base + 11, origin.z)
		var col: Color = p["color"]
		_bulk.set(base + 12, col.r); _bulk.set(base + 13, col.g); _bulk.set(base + 14, col.b); _bulk.set(base + 15, col.a)
		_bulk.set(base + 16, age)
		_bulk.set(base + 17, 1.0 if bool(p["combustion"]) else 0.0)
		_bulk.set(base + 18, frame_time)
		_bulk.set(base + 19, 1.0)
	multimesh.set_as_bulk_array(_bulk)


func _sync_instance(index: int) -> void:
	if multimesh == null or index >= multimesh.instance_count:
		return
	var p: Dictionary = particles[index]
	var age := clamp(float(p["lifetime"]) / max(float(p["max_lifetime"]), 0.001), 0.0, 1.0)
	var frame_time := float(p.get("anim_time", 0.0)) + float(p.get("anim_offset", 0.0))
	var scale := max(float(p["base_scale"]), 0.001) * (0.9 + 0.6 * age) * _scale_boost
	var xform := Transform.IDENTITY
	xform.origin = Vector3(p["position"])
	xform.basis = xform.basis.scaled(Vector3(scale, scale, scale))
	multimesh.set_instance_transform(index, xform)
	multimesh.set_instance_color(index, Color(p["color"]))
	multimesh.set_instance_custom_data(index, Color(age, 1.0 if bool(p["combustion"]) else 0.0, frame_time, 1.0))

func _hide_instance(index: int) -> void:
	# Red de seguridad: el pool se redimensiona en vivo segun los fps, asi que cualquier
	# recorrido que se haya guardado un tamano viejo puede llegar aca fuera de rango.
	if multimesh == null or index >= multimesh.instance_count:
		return
	multimesh.set_instance_transform(index, _hidden_transform)
	multimesh.set_instance_color(index, Color(0, 0, 0, 0))
	multimesh.set_instance_custom_data(index, Color(0, 0, 0, 0))

# Godot 3 no tiene constructor de copia: Vector3(v) y Color(c) son invalidos, igual que
# Vector3(array). Al restaurar un replay guardado en JSON los vectores llegan como Array
# [x, y, z] y el codigo anterior lanzaba "Nonexistent 'Vector3' constructor" en CADA
# particula, asi que ninguna se restauraba y el estado quedaba distinto al grabado: una
# fuente directa de divergencia en la reproduccion.
func _as_vector3(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary and value.has("x"):
		return Vector3(float(value["x"]), float(value["y"]), float(value["z"]))
	return Vector3.ZERO


func _as_color(value) -> Color:
	if value is Color:
		return value
	if value is Array and value.size() >= 3:
		var a: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), a)
	if value is Dictionary and value.has("r"):
		return Color(float(value["r"]), float(value["g"]), float(value["b"]),
			float(value["a"]) if value.has("a") else 1.0)
	return default_color


func get_snapshot() -> Dictionary:
	var active_particles := []
	for i in range(particles.size()):
		var p: Dictionary = particles[i]
		if not bool(p["active"]):
			continue
		active_particles.append({
			"i": i,
			"p": _as_vector3(p["position"]),
			"v": _as_vector3(p["velocity"]),
			"t": float(p["lifetime"]),
			"m": float(p["max_lifetime"]),
			"s": float(p["base_scale"]),
			"c": _as_color(p["color"]),
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
		p["position"] = _as_vector3(entry.get("p", Vector3.ZERO))
		p["velocity"] = _as_vector3(entry.get("v", Vector3.ZERO))
		p["lifetime"] = float(entry.get("t", 0.0))
		p["max_lifetime"] = float(entry.get("m", default_max_lifetime))
		p["base_scale"] = float(entry.get("s", default_base_scale))
		
		var raw_color = _as_color(entry.get("c", default_color))
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
