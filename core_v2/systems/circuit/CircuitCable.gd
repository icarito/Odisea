extends PropBaseV2
class_name CircuitCable

const TubeBuilder = preload("res://core_v2/systems/pipe/TubeBuilder.gd")
# FD-290: trimesh cacheado por Mesh en vez de un BVH nuevo por cable (mismo helper que el
# streamer de ductos y ScaffoldHubRing).
const ShapeBounds = preload("res://core_v2/systems/collision/ShapeBounds.gd")
# Frames mínimos de simulación al arrancar para que la cuerda forme su catenaria
# bajo gravedad antes de entrar en reposo (3 s a 60 Hz).
const INITIAL_SETTLE_FRAMES := 180

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

# --- Catenaria: cuerda física (Verlet/PBD determinista) ---
# El motor Box3D aporta la detección de contacto (Area hurtbox) y el estado vivo de
# los cuerpos; la deformación de la cuerda es pura simulación determinista integrada
# en _physics_process (sin randf/Tween/tiempo de pared), compatible con replay.
export(bool) var sway_enabled := true
# Capas que disparan el balanceo: jugador (2) + props/rigid bodies (4, 64).
export(int) var body_collision_mask := 2 | 4 | 64
export(float) var hurtbox_radius := 0.22          # radio de proximidad (m)
export(float) var sway_stiffness := 0.9           # rigidez PBD (0..1): corrección por iteración
export(float) var sway_damping := 3.0             # arrastre de velocidad (1/s)
export(float) var sway_max_offset := 0.6          # desviación máxima por partícula (m)
export(float) var sway_impulse_scale := 0.10      # velocidad ganada por (m/s) del cuerpo
export(float) var sway_push_force := 1.8          # aceleración de empuje sostenido (m/s^2)
export(float) var sway_settle_epsilon := 0.002    # umbral de reposo (m)
export(float) var rope_gravity := 2.5             # gravedad del cable (m/s^2)
export(float) var rope_segment_spacing := 0.35    # espaciado entre partículas (m)
export(int) var rope_constraint_iterations := 8   # iteraciones del solver PBD

var _hurtbox: Area
var _base_points := PoolVector3Array()
var _points := PoolVector3Array()      # posición actual de cada partícula (cuerda)
var _prev_points := PoolVector3Array() # posición anterior (velocidad implícita Verlet)
var _kick_v := PoolVector3Array()      # impulso pendiente por partícula (m/s)
var _anchored := []                    # bool por partícula: extremos fijos
var _seg_rest := 0.0                   # longitud de descanso de cada tramo
var _inside_bodies: Array = []
var _settle_frames := 0
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

	# Inicializar la cuerda sobre la curva horneada (extremos anclados, sin
	# reconstruir la colisión estática).
	_init_rope()
	_inside_bodies.clear()

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

# --- Catenaria: cuerda física determinista ---
#
# La catenaria se modela como una cadena de partículas (Verlet) unidas por
# restricciones de distancia (Position-Based Dynamics). Los extremos quedan
# anclados al circuito; la gravedad la hace colgar como catenaria real, y el
# contacto con el jugador/props (detectado por el Area de Box3D) la deforma
# localmente, propagando ondas a lo largo del cable. Todo se integra en
# _physics_process con paso fijo, sin randf/Tween/tiempo de pared: dos corridas
# con la misma secuencia de entrada dan el mismo resultado. La COLISIÓN del
# cable nunca se reconstruye; sólo se regenera la malla visual (TubeBuilder)
# mientras hay movimiento.

func _wants_continuous_step() -> bool:
	return sway_enabled and _sway_is_active()

func _sway_is_active() -> bool:
	if not _inside_bodies.empty() or _spark > 0.0:
		return true
	if _points.size() < 2:
		return false
	# Asentamiento inicial bajo gravedad: correr al menos INITIAL_SETTLE_FRAMES
	# frames aunque el cable arranque en reposo, para que forme su catenaria.
	if _settle_frames < INITIAL_SETTLE_FRAMES:
		return true
	var sq: float = 0.0
	for i in range(1, _points.size() - 1):
		sq += (_points[i] - _prev_points[i]).length_squared()
	return sq > sway_settle_epsilon * sway_settle_epsilon

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
	_kick_body(body, lateral)

func _on_hurtbox_body_exited(body: Node) -> void:
	_inside_bodies.erase(body)

func _kick_body(body: Node, lateral: Vector3) -> void:
	if _points.size() < 3:
		return
	var body_pos: Vector3 = global_transform.affine_inverse().xform(body.global_transform.origin)
	var influence: float = max(hurtbox_radius * 3.0, 1.0)
	var n: int = _points.size()
	for i in range(1, n - 1):
		var dist: float = _points[i].distance_to(body_pos)
		var w: float = 1.0 - clamp(dist / influence, 0.0, 1.0)
		if w > 0.01:
			_kick_v[i] += lateral * (sway_impulse_scale * w)
	if is_active:
		_spark = max(_spark, clamp(lateral.length() * 0.25, 0.0, 1.0))
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if sway_enabled and not Engine.editor_hint:
		_step_rope(delta)
	._physics_process(delta)

func _init_rope() -> void:
	var raw := path_curve.get_baked_points() if path_curve != null else PoolVector3Array()
	if raw.size() < 2:
		_points = PoolVector3Array()
		_prev_points = PoolVector3Array()
		_kick_v = PoolVector3Array()
		_anchored = []
		_seg_rest = 0.0
		return
	var n: int = _particle_count(raw)
	# Base remuestreada uniformemente por arco: así las partículas (y sus índices)
	# coinciden 1:1 con la base (los puntos horneados del Curve3D vienen en otra
	# parametrización y rompen el mapeo índice a índice).
	_base_points = _resample_uniform(raw, n)
	_points.resize(n)
	_prev_points.resize(n)
	_kick_v.resize(n)
	_anchored.resize(n)
	var total: float = _curve_length(_base_points)
	var seg: float = total / float(n - 1)
	for i in range(n):
		var p: Vector3 = _base_points[i]
		_points[i] = p
		_prev_points[i] = p
		_kick_v[i] = Vector3.ZERO
		_anchored[i] = (i == 0 or i == n - 1)
	_seg_rest = seg
	_settle_frames = 0
	# Correr la simulación desde el arranque para que la cuerda forme su catenaria.
	set_physics_process(true)

func _particle_count(raw: PoolVector3Array) -> int:
	var total: float = _curve_length(raw)
	var n: int = int(ceil(total / max(rope_segment_spacing, 0.05))) + 1
	if n < 2:
		n = 2
	elif n > 256:
		n = 256
	return n

static func _resample_uniform(points: PoolVector3Array, count: int) -> PoolVector3Array:
	var out := PoolVector3Array()
	if count < 2:
		return out
	for i in range(count):
		out.append(_point_at_parameter(points, float(i) / float(count - 1)))
	return out

static func _curve_length(points: PoolVector3Array) -> float:
	var len_val := 0.0
	for i in range(1, points.size()):
		len_val += points[i - 1].distance_to(points[i])
	return len_val

static func _point_at_parameter(points: PoolVector3Array, t: float) -> Vector3:
	var n: int = points.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1 or t <= 0.0:
		return points[0]
	if t >= 1.0:
		return points[n - 1]
	var total: float = _curve_length(points)
	var target := total * t
	var acc := 0.0
	for i in range(1, n):
		var seg: float = points[i - 1].distance_to(points[i])
		if acc + seg >= target:
			var u: float = 0.0 if seg < 0.000001 else (target - acc) / seg
			return points[i - 1].linear_interpolate(points[i], u)
		acc += seg
	return points[n - 1]

func _step_rope(dt: float) -> void:
	if _points.size() < 3:
		return
	_visual_clock += dt
	var down: Vector3 = global_transform.basis.inverse().xform(Vector3(0, -1, 0))
	var drag: float = clamp(1.0 - sway_damping * dt, 0.0, 1.0)
	var g: Vector3 = down * rope_gravity * dt * dt
	var n: int = _points.size()

	# Verlet: integrar posición con gravedad + arrastre + impulso pendiente.
	for i in range(1, n - 1):
		var cur: Vector3 = _points[i]
		var prev: Vector3 = _prev_points[i]
		var next: Vector3 = cur + (cur - prev) * drag + g + _kick_v[i] * dt
		_prev_points[i] = cur
		_points[i] = next
		_kick_v[i] = Vector3.ZERO

	# Contacto geométrico con cuerpos (jugador/props) + empuje por velocidad.
	_apply_body_contacts(dt)

	# Solver PBD: mantener las longitudes de cada tramo (cuerda inextensible).
	var stiff: float = clamp(sway_stiffness, 0.0, 1.0)
	for _it in range(rope_constraint_iterations):
		for i in range(n - 1):
			var a: Vector3 = _points[i]
			var b: Vector3 = _points[i + 1]
			var delta: Vector3 = b - a
			var d: float = delta.length()
			if d < 0.000001:
				continue
			var diff: float = (d - _seg_rest) / d
			var fix_a: bool = _anchored[i]
			var fix_b: bool = _anchored[i + 1]
			if fix_a and fix_b:
				continue
			elif fix_a:
				_points[i + 1] = b - delta * (diff * stiff)
			elif fix_b:
				_points[i] = a + delta * (diff * stiff)
			else:
				_points[i] = a + delta * (diff * stiff * 0.5)
				_points[i + 1] = b - delta * (diff * stiff * 0.5)

	# Techo de desviación por partícula respecto al reposo (evita explosiones).
	if sway_max_offset > 0.0:
		for i in range(1, n - 1):
			var off: Vector3 = _points[i] - _base_points[i]
			if off.length_squared() > sway_max_offset * sway_max_offset:
				_points[i] = _base_points[i] + off.normalized() * sway_max_offset

	if _spark > 0.0:
		_spark = max(_spark - dt * 4.0, 0.0)

	_settle_frames += 1

	if _rope_changed():
		_rebuild_rope_mesh()

func _apply_body_contacts(dt: float) -> void:
	if _inside_bodies.empty():
		return
	var radius: float = max(hurtbox_radius, cable_radius * 2.0)
	var influence: float = radius * 3.0
	var down: Vector3 = global_transform.basis.inverse().xform(Vector3(0, -1, 0))
	var n: int = _points.size()
	var index: int = _inside_bodies.size() - 1
	while index >= 0:
		var b = _inside_bodies[index]
		if not is_instance_valid(b):
			_inside_bodies.remove(index)
			index -= 1
			continue
		var body_pos: Vector3 = global_transform.affine_inverse().xform(b.global_transform.origin)
		var lat: Vector3 = _lateral_local(_body_velocity_local(b))
		for i in range(1, n - 1):
			var rel: Vector3 = _points[i] - body_pos
			var dist: float = rel.length()
			# Empuje geométrico: no dejar que el cuerpo atraviese la cuerda.
			if dist < radius:
				if dist < 0.000001:
					_points[i] = body_pos + down * radius * 0.5
				else:
					var push_scale: float = clamp(sway_push_force * dt * 4.0, 0.0, 1.0)
					_points[i] += rel / dist * ((radius - dist) * push_scale)
			# Empuje por velocidad: contribuye sólo la componente lateral.
			var w: float = 1.0 - clamp(dist / influence, 0.0, 1.0)
			if w > 0.01:
				_kick_v[i] += lat * (sway_push_force * w) * dt
		index -= 1

func _rope_changed() -> bool:
	if _base_points.size() != _points.size():
		return true
	var thresh: float = max(sway_settle_epsilon * 0.5, 0.0001)
	for i in range(_points.size()):
		if _points[i].distance_squared_to(_base_points[i]) > thresh * thresh:
			return true
	return false

func _rebuild_rope_mesh() -> void:
	var mesh_inst = get_node_or_null("CableVis")
	if not (mesh_inst is MeshInstance):
		return
	if _points.size() < 2:
		return
	var deformed := Curve3D.new()
	if path_curve != null:
		deformed.bake_interval = path_curve.bake_interval
	for p in _points:
		deformed.add_point(p)
	var new_mesh: ArrayMesh = TubeBuilder.generate_tube_mesh(deformed, cable_radius, cable_sides)
	if new_mesh != null and new_mesh.get_surface_count() > 0:
		(mesh_inst as MeshInstance).mesh = new_mesh

func get_snapshot() -> Dictionary:
	var d: Dictionary = .get_snapshot()
	d["rope"] = _points_to_list(_points)
	d["rope_prev"] = _points_to_list(_prev_points)
	d["rope_kick"] = _points_to_list(_kick_v)
	d["spark"] = _spark
	return d

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	var rope = data.get("rope", null)
	if rope is Array:
		_points = _list_to_points(rope)
	var prev = data.get("rope_prev", null)
	if prev is Array:
		_prev_points = _list_to_points(prev)
	var kick = data.get("rope_kick", null)
	if kick is Array:
		_kick_v = _list_to_points(kick)
	_spark = float(data.get("spark", 0.0))
	if _points.size() >= 2:
		_rebuild_rope_mesh()
	set_physics_process(_sway_is_active())
	_update_visuals()

static func _points_to_list(points: PoolVector3Array) -> Array:
	var out := []
	for p in points:
		out.append([p.x, p.y, p.z])
	return out

static func _list_to_points(list) -> PoolVector3Array:
	var arr := PoolVector3Array()
	for item in list:
		arr.append(Vector3(item[0], item[1], item[2]))
	return arr

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
