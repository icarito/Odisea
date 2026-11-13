extends PropBaseV2
class_name CircuitCable

const TubeBuilder = preload("res://core_v2/systems/pipe/TubeBuilder.gd")
# FD-290: trimesh cacheado por Mesh en vez de un BVH nuevo por cable (mismo helper que el
# streamer de ductos y ScaffoldHubRing).
const ShapeBounds = preload("res://core_v2/systems/collision/ShapeBounds.gd")

# CircuitCable.gd
# Procedurally generated cable that connects circuit nodes.
# Supports both CSG and direct Mesh generation.

signal connection_broken

export(Curve3D) var path_curve: Curve3D
export(bool) var use_csg := false
export(Material) var cable_material: Material
export(float) var health := 10.0
export(float) var cable_radius := 0.05
export(int) var cable_sides := 8

# --- Catenaria: interacción física con cuerpos (determinista) ---
export(bool) var sway_enabled := true
# Capas que disparan el balanceo: jugador (2) + props/rigid bodies (4, 64).
export(int) var body_collision_mask := 2 | 4 | 64
export(float) var hurtbox_radius := 0.22          # radio de proximidad (m)
export(float) var sway_stiffness := 26.0          # rigidez del oscilador (1/s^2)
export(float) var sway_damping := 4.2             # amortiguación (1/s)
export(float) var sway_max_offset := 0.6          # deflexión máxima (m)
export(float) var sway_impulse_scale := 0.10      # velocidad por (m/s) del cuerpo
export(float) var sway_push_force := 1.8          # empuje sostenido de un cuerpo en movimiento
export(float) var sway_settle_epsilon := 0.002    # umbral de reposo (m)

var _hurtbox: Area
var _base_points := PoolVector3Array()
var _sway_offset := Vector3.ZERO
var _sway_velocity := Vector3.ZERO
var _inside_bodies: Array = []
var _mesh_deformed := false
var _energy_material: SpatialMaterial = null
var _last_visual_t := -1.0
var _visual_clock := 0.0
var _spark := 0.0

func _ready():
	# FIRST call parent class _ready() to ensure set_active and other methods are available
	# This sets is_active, anim_progress, target_progress, and calls _update_visuals()
	._ready()

	# If no Curve3D is assigned (common in props/tests), create a tiny default
	# curve so that build() can produce visible geometry for validation.
	if not path_curve:
		var default_curve = Curve3D.new()
		# Make the default cable along X axis (horizontal) for typical circuit layout
		# In this project +Z is backward (camera direction), so X is horizontal left-right
		default_curve.add_point(Vector3(0, 0, 0))
		default_curve.add_point(Vector3(3, 0, 0))
		path_curve = default_curve

	if path_curve:
		# Build synchronously so _update_visuals() can access the mesh
		build()

func build():
	# Clear previous children
	for child in get_children():
		child.queue_free()

	if not path_curve or path_curve.get_point_count() < 2:
		return

	if use_csg:
		_build_csg()
	else:
		_build_mesh()

	_setup_hurtbox()

	# Cache de la forma base para deformar la catenaria sin reconstruir la colisión.
	_base_points = path_curve.get_baked_points()
	_sway_offset = Vector3.ZERO
	_sway_velocity = Vector3.ZERO
	_inside_bodies.clear()
	_mesh_deformed = false

func _build_csg():
	var path_node = Path.new()
	path_node.curve = path_curve
	path_node.name = "Path"
	add_child(path_node)
	var csg = CSGPolygon.new()
	csg.mode = CSGPolygon.MODE_PATH
	csg.path_node = path_node.get_path()
	csg.polygon = _generate_circle_polygon(cable_radius, cable_sides)
	csg.material = cable_material
	csg.use_collision = true
	csg.name = "CableVis"
	add_child(csg)


func _build_mesh():
	var mesh_inst = MeshInstance.new()
	mesh_inst.mesh = _generate_tube_mesh(path_curve, cable_radius, cable_sides)
	
	# Create a unique material per instance (duplicate the assigned material or create new)
	var unique_material = null
	if cable_material:
		unique_material = cable_material.duplicate()
	else:
		unique_material = SpatialMaterial.new()
	mesh_inst.material_override = unique_material
	
	# If no material was assigned, create a visible fallback
	if not cable_material:
		unique_material.emission_enabled = true
		unique_material.emission = Color(1, 1, 0)
		unique_material.albedo_color = Color(1, 1, 0.2)
	
	mesh_inst.name = "CableVis"
	add_child(mesh_inst)
	# Con una curva muy corta (p. ej. la de 2 puntos por defecto, o la placeholder que build()
	# arma en _ready() antes de que init_from_curve() aplique la real) generate_tube_mesh()
	# puede devolver una malla sin superficies validas. create_trimesh_collision() no tolera
	# eso: falla con "Condition '!static_body' is true" porque nunca llega a crear el cuerpo.
	# El helper del FD-290 valida lo mismo y ademas reutiliza el ConcavePolygonShape cuando
	# dos cables comparten malla.
	if mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0:
		var shape := ShapeBounds.trimesh_shape_of(mesh_inst.mesh)
		if shape != null:
			var body := StaticBody.new()
			body.name = "CableVis_col"
			var col := CollisionShape.new()
			col.shape = shape
			body.add_child(col)
			mesh_inst.add_child(body)
			body.owner = mesh_inst.owner


func _setup_hurtbox():
	# Create an Area named Hurtbox and populate it with capsule CollisionShapes
	if _hurtbox and is_instance_valid(_hurtbox):
		_hurtbox.queue_free()

	_hurtbox = Area.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 1
	# Detectar cuerpos (jugador/props) para el balanceo. No detecta geometría estática
	# (capa 1), así que el área de proximidad no reacciona al nivel.
	_hurtbox.collision_mask = body_collision_mask
	add_child(_hurtbox)

	if not _hurtbox.is_connected("body_entered", self, "_on_hurtbox_body_entered"):
		_hurtbox.connect("body_entered", self, "_on_hurtbox_body_entered")
	if not _hurtbox.is_connected("body_exited", self, "_on_hurtbox_body_exited"):
		_hurtbox.connect("body_exited", self, "_on_hurtbox_body_exited")

	if not path_curve:
		return

	var points = path_curve.get_baked_points()
	if points.size() < 2:
		return

	var prev = points[0]
	var interval = 0.5 # Generate collision every 0.5 units to reduce count
	var dist_acc = 0.0

	for i in range(1, points.size()):
		var curr = points[i]
		var seg_len = prev.distance_to(curr)
		dist_acc += seg_len

		if dist_acc >= interval or i == points.size() - 1:
			var col = CollisionShape.new()
			var capsule = CapsuleShape.new()
			capsule.radius = max(cable_radius * 2.0, hurtbox_radius)
			capsule.height = dist_acc
			col.shape = capsule

			var center = (prev + curr) / 2.0

			_hurtbox.add_child(col)

			var local_center = _hurtbox.to_local(center)
			col.transform.origin = local_center

			var dir = (curr - prev).normalized()
			var right = dir.cross(Vector3.UP)
			if right.length_squared() < 0.0001:
				right = dir.cross(Vector3.RIGHT)
			right = right.normalized()
			var up_vec = right.cross(dir).normalized()
			var basis = Basis(right, up_vec, -dir)
			col.transform.basis = basis

			prev = curr
			dist_acc = 0.0


func _generate_circle_polygon(radius: float, sides: int) -> PoolVector2Array:
	return TubeBuilder.generate_circle_polygon(radius, sides)

func _generate_tube_mesh(curve: Curve3D, radius: float, sides: int) -> ArrayMesh:
	return TubeBuilder.generate_tube_mesh(curve, radius, sides)

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0:
		emit_signal("connection_broken")
		queue_free()

# Compatibility for other damage systems
func damage(amount: float) -> void:
	take_damage(amount)

func hit(amount: float) -> void:
	take_damage(amount)

func is_broken() -> bool:
	return health <= 0

func init_from_curve(curve: Curve3D) -> void:
	# Initialize the cable from a Curve3D and build geometry
	path_curve = curve
	build()

# --- Catenaria: balanceo determinista por contacto de cuerpos ---
#
# El estado del balanceo (offset + velocidad) es simulación pura y se integra en
# _physics_process con un oscilador armónico amortiguado semi-implícito. Nada de
# randf/Tween/tiempo de pared: dos corridas con la misma secuencia de entrada dan
# el mismo resultado. La COLISIÓN del cable no se reconstruye nunca; sólo se
# regenera la malla visual (TubeBuilder) mientras hay deflexión.

func _wants_continuous_step() -> bool:
	return sway_enabled and _sway_is_active()

func _sway_is_active() -> bool:
	return _sway_offset.length_squared() > sway_settle_epsilon * sway_settle_epsilon \
		or _sway_velocity.length_squared() > 0.000001 \
		or _spark > 0.0

func _cable_axis_local() -> Vector3:
	if _base_points.size() < 2:
		return Vector3.RIGHT
	var axis: Vector3 = _base_points[_base_points.size() - 1] - _base_points[0]
	if axis.length_squared() < 0.000001:
		return Vector3.RIGHT
	return axis.normalized()

func _lateral_local(v_local: Vector3) -> Vector3:
	var axis: Vector3 = _cable_axis_local()
	return v_local - axis * v_local.dot(axis)

func _body_velocity_local(body: Node) -> Vector3:
	var v := Vector3.ZERO
	if body is RigidBody:
		v = (body as RigidBody).linear_velocity
	elif "velocity" in body:
		v = body.get("velocity")
	return global_transform.basis.inverse().xform(v)

func _on_hurtbox_body_entered(body: Node) -> void:
	if not sway_enabled or Engine.editor_hint:
		return
	if not _inside_bodies.has(body):
		_inside_bodies.append(body)
	var lateral: Vector3 = _lateral_local(_body_velocity_local(body))
	if lateral.length_squared() < 0.0001:
		# Toque sin velocidad: deflectar en la dirección cuerpo->cable.
		var rel: Vector3 = global_transform.affine_inverse().xform(body.global_transform.origin)
		var dir: Vector3 = _lateral_local(-rel)
		if dir.length_squared() > 0.000001:
			lateral = dir.normalized() * 0.6
	_apply_impulse(lateral)

func _on_hurtbox_body_exited(body: Node) -> void:
	_inside_bodies.erase(body)

func _apply_impulse(lateral: Vector3) -> void:
	_sway_velocity += lateral * sway_impulse_scale
	# Techo de velocidad: evita que un cuerpo muy rápido dispare la deformación.
	var max_v: float = sway_max_offset * sway_stiffness
	if _sway_velocity.length() > max_v:
		_sway_velocity = _sway_velocity.normalized() * max_v
	if is_active:
		_spark = max(_spark, clamp(lateral.length() * 0.25, 0.0, 1.0))
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if sway_enabled and not Engine.editor_hint:
		_step_sway(delta)
	._physics_process(delta)

func _step_sway(dt: float) -> void:
	# Empuje sostenido de los cuerpos que siguen dentro y se mueven.
	if not _inside_bodies.empty():
		var push := Vector3.ZERO
		var i: int = _inside_bodies.size() - 1
		while i >= 0:
			var b = _inside_bodies[i]
			if not is_instance_valid(b):
				_inside_bodies.remove(i)
			else:
				push += _lateral_local(_body_velocity_local(b))
			i -= 1
		if push.length_squared() > 0.0001:
			_sway_velocity += push * sway_push_force * dt

	# Oscilador armónico amortiguado (integración semi-implícita, determinista).
	var accel: Vector3 = -sway_stiffness * _sway_offset - sway_damping * _sway_velocity
	_sway_velocity += accel * dt
	_sway_offset += _sway_velocity * dt

	if _sway_offset.length() > sway_max_offset:
		_sway_offset = _sway_offset.normalized() * sway_max_offset
		if _sway_velocity.dot(_sway_offset) > 0.0:
			_sway_velocity = Vector3.ZERO

	_visual_clock += dt
	if _spark > 0.0:
		_spark = max(_spark - dt * 4.0, 0.0)

	if _sway_offset.length_squared() <= sway_settle_epsilon * sway_settle_epsilon \
			and _sway_velocity.length_squared() <= 0.000001 and _inside_bodies.empty() \
			and _spark <= 0.0:
		_sway_offset = Vector3.ZERO
		_sway_velocity = Vector3.ZERO

	# Deformar la malla visual (nunca la colisión). Al volver al reposo, restaurar la base.
	if _sway_offset.length_squared() > 0.000001:
		_rebuild_sway_mesh()
		_mesh_deformed = true
	elif _mesh_deformed:
		_rebuild_sway_mesh()
		_mesh_deformed = false

func _rebuild_sway_mesh() -> void:
	var mesh_inst = get_node_or_null("CableVis")
	if not (mesh_inst is MeshInstance):
		return
	if _base_points.size() < 2:
		return
	var deformed := Curve3D.new()
	if path_curve != null:
		deformed.bake_interval = path_curve.bake_interval
	var n: int = _base_points.size()
	for i in range(n):
		var t: float = float(i) / float(max(n - 1, 1))
		var weight: float = sin(PI * t)  # extremos fijos (anclados al circuito)
		deformed.add_point(_base_points[i] + _sway_offset * weight)
	var new_mesh: ArrayMesh = TubeBuilder.generate_tube_mesh(deformed, cable_radius, cable_sides)
	if new_mesh != null and new_mesh.get_surface_count() > 0:
		(mesh_inst as MeshInstance).mesh = new_mesh

func get_snapshot() -> Dictionary:
	var d: Dictionary = .get_snapshot()
	d["sway"] = [_sway_offset.x, _sway_offset.y, _sway_offset.z]
	d["sway_vel"] = [_sway_velocity.x, _sway_velocity.y, _sway_velocity.z]
	d["spark"] = _spark
	return d

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	var so = data.get("sway", null)
	if so is Array and so.size() == 3:
		_sway_offset = Vector3(float(so[0]), float(so[1]), float(so[2]))
	var sv = data.get("sway_vel", null)
	if sv is Array and sv.size() == 3:
		_sway_velocity = Vector3(float(sv[0]), float(sv[1]), float(sv[2]))
	_spark = float(data.get("spark", 0.0))
	if _sway_offset.length_squared() > 0.000001:
		_rebuild_sway_mesh()
		_mesh_deformed = true
	set_physics_process(_sway_is_active())
	_update_visuals()

# --- Energy Reactivity ---

func _update_visuals() -> void:
	"""Override from PropBaseV2 to react to energy (is_active state)."""
	var t = target_progress if anim_progress < 0.01 else anim_progress

	# Update legacy state for test compatibility
	if t < 0.3:
		circuit_state = "idle"
	elif t < 0.7:
		circuit_state = "mid"
	else:
		circuit_state = "active"

	# Get the cable visual mesh
	var mesh_inst = get_node_or_null("CableVis")
	if not mesh_inst:
		return

	# Reciclar el material y no re-colorear en cada frame: durante el balanceo el base
	# llama _update_visuals() seguido, y un cable apagado no debe re-tintarse cada tick.
	if abs(t - _last_visual_t) < 0.0001 and _spark <= 0.0:
		return
	_last_visual_t = t

	if _energy_material == null:
		_energy_material = SpatialMaterial.new()
	mesh_inst.material_override = _energy_material

	# Energy states: inactive (dim gray), active (glowing cyan/electric blue)
	var inactive_color = Color(0.1, 0.1, 0.1)  # Very dark gray (almost black)
	var active_color = Color(0.0, 1.0, 0.8)     # Bright electric cyan

	# Pulso determinista basado en el reloj de simulación (no en tiempo de pared).
	var pulse = 1.0
	if t > 0.5:
		pulse = 1.0 + 0.3 * sin(_visual_clock * 10.0)

	var current_color = inactive_color.linear_interpolate(active_color, t)

	_energy_material.albedo_color = current_color
	_energy_material.emission_enabled = true
	_energy_material.emission = current_color
	_energy_material.emission_energy = t * 5.0 * pulse + _spark * 2.5

	# Make it really obvious when off - no glow at all
	if t < 0.1:
		_energy_material.emission_energy = _spark * 2.5
		_energy_material.albedo_color = Color(0.05, 0.05, 0.05)  # Very dark

# --- Interaction (for manual testing) ---

func set_active(value: bool, immediate: bool = false) -> void:
	"""Override set_active to update state property when called by Lever."""
	.set_active(value, immediate)
	_update_visuals()

func interact(_from = null) -> void:
	"""Toggle energy state. Called by player interaction or pipeline."""
	.set_active(not is_active)

# Legacy state handling for backward compatibility with tests
var circuit_state: String = "idle" # idle, mid, active

# Alias for test compatibility
func get_state() -> String:
	return circuit_state

func set_state(value: String) -> void:
	circuit_state = value

var state: String = "idle" setget set_state, get_state

# Legacy method - now calls set_active
func set_cable_visuals(emission: float, color: Color):
	if not cable_material:
		cable_material = SpatialMaterial.new()
		var mesh_inst = get_node_or_null("CableVis")
		if mesh_inst:
			mesh_inst.material_override = cable_material
	cable_material.emission_enabled = true
	cable_material.emission = color * emission
	cable_material.albedo_color = color
