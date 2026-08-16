tool
extends PropBaseV2
class_name PipeRun

# PipeRun.gd — Corrida generada de tubería con fusión de malla, daño y flujo visible.

signal pipe_broken()
signal health_changed(new_health)

const TubeBuilder = preload("res://core_v2/systems/pipe/TubeBuilder.gd")
const PipeRouterScript = preload("res://core_v2/systems/pipe/PipeRouter.gd")
const DEFAULT_FLOW_MATERIAL := "res://core_v2/props/pipe/PipeCoolant.tres"

# Materiales compartidos indexados por path para evitar .duplicate() innecesario
const _shared_material_cache: Dictionary = {}

export(NodePath) var from_anchor: NodePath
export(NodePath) var to_anchor: NodePath
export(Dictionary) var router_options: Dictionary = {}

export(float) var health: float = 10.0 setget set_health
export(float) var pipe_radius: float = 0.08
export(int) var pipe_sides: int = 8
export(String, FILE, "*.tres") var flow_material_path: String = DEFAULT_FLOW_MATERIAL

export(float) var flow_speed: float = 0.7
export(float) var flow_intensity: float = 1.0 setget set_flow_intensity
export(Color) var base_color: Color = Color(0.06, 0.22, 0.35, 1.0)
export(Color) var flow_color: Color = Color(0.35, 0.92, 0.98, 1.0)

var path_curve: Curve3D setget set_path_curve
var is_broken: bool = false

var _mesh_inst: MeshInstance
var _hurtbox: Area
var _leak_particles: CPUParticles
var _shared_material: ShaderMaterial


func _ready() -> void:
	add_to_group("replay_sync")
	._ready()

	if not path_curve and (from_anchor or to_anchor):
		build_from_anchors(from_anchor, to_anchor, router_options)
	elif path_curve:
		build_mesh_and_collision()


func set_health(val: float) -> void:
	health = val
	emit_signal("health_changed", health)


func set_path_curve(curve: Curve3D) -> void:
	path_curve = curve
	if is_inside_tree():
		build_mesh_and_collision()


func set_flow_intensity(val: float) -> void:
	flow_intensity = clamp(val, 0.0, 3.0)
	if _shared_material and is_instance_valid(_shared_material):
		_shared_material.set_shader_param("emission_strength", 1.4 * flow_intensity)


func build_from_anchors(from_a, to_a, options: Dictionary = {}) -> void:
	var router = PipeRouterScript.new()
	if is_inside_tree():
		add_child(router)

	var curve = router.generate_route(from_a, to_a, options)

	if is_inside_tree() and router.get_parent() == self:
		router.queue_free()
	else:
		router.free()

	build_from_curve(curve)


func build_from_curve(curve: Curve3D) -> void:
	path_curve = curve
	build_mesh_and_collision()


func build_mesh_and_collision() -> void:
	for child in get_children():
		if child.name in ["PipeMesh", "Hurtbox", "LeakParticles"]:
			child.queue_free()

	if not path_curve or path_curve.get_point_count() < 2:
		return

	# 1. Malla fusionada estática (1 draw call por corrida)
	var mesh = TubeBuilder.generate_tube_mesh(path_curve, pipe_radius, pipe_sides, true)
	if not mesh:
		return

	_mesh_inst = MeshInstance.new()
	_mesh_inst.name = "PipeMesh"
	_mesh_inst.mesh = mesh

	# Reutilizar o cargar material compartido sin duplicar recurso por corrida
	_shared_material = _get_or_load_material(flow_material_path)
	if _shared_material:
		_mesh_inst.material_override = _shared_material

	add_child(_mesh_inst)

	# 2. Hurtbox & colisión simplificada de cápsulas
	_setup_hurtbox()

	# 3. Emisor de fuga si ya está roto
	if is_broken:
		_trigger_leak()


func _get_or_load_material(mat_path: String) -> ShaderMaterial:
	if _shared_material_cache.has(mat_path) and is_instance_valid(_shared_material_cache[mat_path]):
		return _shared_material_cache[mat_path]

	var res = load(mat_path)
	if res and res is ShaderMaterial:
		_shared_material_cache[mat_path] = res
		return res
	return null


func _setup_hurtbox() -> void:
	if _hurtbox and is_instance_valid(_hurtbox):
		_hurtbox.queue_free()

	_hurtbox = Area.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 1
	_hurtbox.collision_mask = 0
	add_child(_hurtbox)

	var points = path_curve.get_baked_points()
	if points.size() < 2:
		return

	var prev = points[0]
	var interval = 1.0 # Colisión cada 1.0 metro para optimizar formas
	var dist_acc = 0.0

	for i in range(1, points.size()):
		var curr = points[i]
		var seg_len = prev.distance_to(curr)
		dist_acc += seg_len

		if dist_acc >= interval or i == points.size() - 1:
			var col = CollisionShape.new()
			var capsule = CapsuleShape.new()
			capsule.radius = pipe_radius * 1.5
			capsule.height = dist_acc
			col.shape = capsule

			var center = (prev + curr) / 2.0
			_hurtbox.add_child(col)

			if _hurtbox.is_inside_tree():
				col.transform.origin = _hurtbox.to_local(center)
			else:
				col.transform.origin = center

			var dir = (curr - prev).normalized()
			var right = dir.cross(Vector3.UP)
			if right.length_squared() < 0.0001:
				right = dir.cross(Vector3.RIGHT)
			right = right.normalized()
			var up_vec = right.cross(dir).normalized()
			col.transform.basis = Basis(right, up_vec, -dir)

			prev = curr
			dist_acc = 0.0


func take_damage(amount: float) -> void:
	if health <= 0 or is_broken:
		return

	health -= amount
	emit_signal("health_changed", health)

	if health <= 0:
		is_broken = true
		_trigger_leak()
		emit_signal("pipe_broken")


func damage(amount: float) -> void:
	take_damage(amount)


func hit(amount: float) -> void:
	take_damage(amount)


func _trigger_leak() -> void:
	if _leak_particles and is_instance_valid(_leak_particles):
		_leak_particles.emitting = true
		return

	_leak_particles = CPUParticles.new()
	_leak_particles.name = "LeakParticles"
	_leak_particles.amount = 32
	_leak_particles.lifetime = 1.2
	_leak_particles.explosiveness = 0.1
	_leak_particles.direction = Vector3.UP
	_leak_particles.spread = 45.0
	_leak_particles.gravity = Vector3(0, -2.0, 0)
	_leak_particles.initial_velocity = 2.5
	_leak_particles.color = flow_color

	# Ubicar la fuga en el punto medio de la curva
	if path_curve and path_curve.get_point_count() >= 2:
		var baked = path_curve.get_baked_points()
		var mid_idx = baked.size() / 2
		_leak_particles.transform.origin = baked[mid_idx]

	add_child(_leak_particles)
	_leak_particles.emitting = true


func is_pipe_broken() -> bool:
	return is_broken


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"health": health,
		"is_broken": is_broken,
		"is_active": is_active,
		"flow_intensity": flow_intensity
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("health"):
		health = float(data["health"])
	if data.has("is_broken"):
		var was_broken = is_broken
		is_broken = bool(data["is_broken"])
		if is_broken and not was_broken:
			_trigger_leak()
		elif not is_broken and _leak_particles and is_instance_valid(_leak_particles):
			_leak_particles.emitting = false
	if data.has("is_active"):
		set_active(bool(data["is_active"]))
	if data.has("flow_intensity"):
		set_flow_intensity(float(data["flow_intensity"]))
