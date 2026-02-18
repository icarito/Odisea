tool
extends PropBaseV2
class_name CircuitCable

# CircuitCable.gd
# Procedurally generated cable that connects circuit nodes.
# Supports both CSG and direct Mesh generation.
# Updated for OLCS v2: Procedural Physical Cables (Verlet Integration)

signal connection_broken

# --- Configuration ---
export(Curve3D) var path_curve: Curve3D
export(bool) var use_csg := false # Legacy mode
export(Material) var cable_material: Material # Fallback / Base material
export(float) var health := 10.0
export(float) var cable_radius := 0.05
export(int) var cable_sides := 6

# --- Physics Parameters ---
export(bool) var simulation_enabled := true
export(float) var segment_length := 0.5
export(Vector3) var gravity := Vector3(0, -9.8, 0)
export(float) var wind_scale := 0.5
export(float) var damping := 0.95
export(int) var stiffness := 4 # Solver iterations

# --- Internal ---
var _particles = []
var _constraints = [] # Array of [p1_idx, p2_idx, rest_length]
var _wind_noise = OpenSimplexNoise.new()
var _time := 0.0
var _hurtbox: Area
var _mesh_instance: MeshInstance
var _shader_mat: ShaderMaterial
var _collision_update_timer := 0

# --- Inner Class ---
class Particle:
	var pos: Vector3
	var old_pos: Vector3
	var pinned: bool = false

	func _init(p: Vector3, pin: bool = false):
		pos = p
		old_pos = p
		pinned = pin

func _ready():
	# Configure noise
	_wind_noise.seed = randi()
	_wind_noise.period = 20.0

	# Load shader
	if not Engine.editor_hint:
		var shader_res = load("res://core_v2/systems/circuit/Cable.shader")
		if shader_res:
			_shader_mat = ShaderMaterial.new()
			_shader_mat.shader = shader_res
			# Set default colors
			_shader_mat.set_shader_param("color_active", Color(0.0, 1.0, 0.8))
			_shader_mat.set_shader_param("color_inactive", Color(0.1, 0.1, 0.1))

	._ready()

	# Default curve for editor visualization
	if not path_curve and Engine.editor_hint:
		var default_curve = Curve3D.new()
		default_curve.add_point(Vector3(0, 0, 0))
		default_curve.add_point(Vector3(3, 0, 0))
		path_curve = default_curve

	if path_curve:
		build()

func build():
	# Clean up previous
	for child in get_children():
		if child.name == "CableVis" or child.name == "Hurtbox":
			child.queue_free()
	_particles.clear()
	_constraints.clear()

	if not path_curve or path_curve.get_point_count() < 2:
		return

	if use_csg:
		_build_csg() # Legacy path
		_setup_hurtbox_static()
		return

	# Build Physics Particles
	var total_len = path_curve.get_baked_length()
	var segment_count = max(2, int(total_len / segment_length))
	
	for i in range(segment_count + 1):
		var t = float(i) / float(segment_count)
		var offset = t * total_len
		var pos = path_curve.interpolate_baked(offset)

		var pinned = (i == 0 or i == segment_count) # Pin start and end
		var p = Particle.new(pos, pinned)
		_particles.append(p)

		if i > 0:
			var prev_p = _particles[i-1]
			var dist = prev_p.pos.distance_to(p.pos)
			_constraints.append([i-1, i, dist])

	# Initial Mesh
	_mesh_instance = MeshInstance.new()
	_mesh_instance.name = "CableVis"
	add_child(_mesh_instance)
	
	if _shader_mat:
		_mesh_instance.material_override = _shader_mat
	elif cable_material:
		_mesh_instance.material_override = cable_material

	_update_mesh()
	_setup_hurtbox_dynamic()

func _physics_process(delta):
	if Engine.editor_hint: return
	if not simulation_enabled or use_csg or _particles.empty():
		return

	# Optimization: Skip if not visible, but keep simulation running?
	# For correct physics when coming back into view, we should simulate.
	# But we can skip mesh update if not visible.

	_time += delta

	# 1. Verlet Integration
	for p in _particles:
		if p.pinned:
			continue

		var vel = (p.pos - p.old_pos) * damping
		p.old_pos = p.pos

		# Forces
		var force = gravity
		# Wind
		var noise_val = _wind_noise.get_noise_3d(p.pos.x, p.pos.y, _time * 10.0)
		var wind_dir = Vector3(noise_val, 0, noise_val * 0.5).normalized() # Simple wind
		force += wind_dir * wind_scale * noise_val

		p.pos += vel + force * delta * delta

	# 2. Constraints
	for i in range(stiffness):
		for c in _constraints:
			var p1 = _particles[c[0]]
			var p2 = _particles[c[1]]
			var rest = c[2]

			var delta_pos = p2.pos - p1.pos
			var dist = delta_pos.length()
			if dist < 0.0001: continue

			var diff = (dist - rest) / dist
			# var correction = delta_pos * 0.5 * diff

			if p1.pinned and not p2.pinned:
				p2.pos -= delta_pos * diff
			elif p2.pinned and not p1.pinned:
				p1.pos += delta_pos * diff
			elif not p1.pinned and not p2.pinned:
				p1.pos += delta_pos * 0.5 * diff
				p2.pos -= delta_pos * 0.5 * diff

	# 3. Update Visuals
	if is_visible_in_tree():
		_update_mesh()

	# 4. Update Collision (throttled)
	_collision_update_timer += 1
	if _collision_update_timer >= 10:
		_collision_update_timer = 0
		_update_hurtbox_dynamic()

func _update_mesh():
	if not _mesh_instance: return

	# Re-generate mesh using SurfaceTool
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Generate tube geometry
	var sides = cable_sides
	var up = Vector3.UP

	for i in range(_particles.size()):
		var p = _particles[i].pos

		# Calculate tangent
		var tangent = Vector3.FORWARD
		if i < _particles.size() - 1:
			tangent = (_particles[i+1].pos - p).normalized()
		elif i > 0:
			tangent = (p - _particles[i-1].pos).normalized()

		# Make basis
		var right = tangent.cross(up).normalized()
		if right.length_squared() < 0.001:
			right = tangent.cross(Vector3.RIGHT).normalized()
		up = right.cross(tangent).normalized()

		# Generate ring
		for j in range(sides + 1):
			var angle = (j / float(sides)) * TAU
			var local_pos = Vector2(cos(angle), sin(angle)) * cable_radius
			var pos_3d = p + (right * local_pos.x) + (up * local_pos.y)

			var uv_x = j / float(sides)
			var uv_y = i / float(_particles.size() - 1) # Normalized length

			st.add_uv(Vector2(uv_x, uv_y))
			st.add_vertex(pos_3d)

	# Indices
	var ring_v_count = sides + 1
	for i in range(_particles.size() - 1):
		for j in range(sides):
			var curr = i * ring_v_count + j
			var next = curr + 1
			var upper_curr = (i + 1) * ring_v_count + j
			var upper_next = upper_curr + 1

			st.add_index(curr)
			st.add_index(upper_curr)
			st.add_index(next)

			st.add_index(next)
			st.add_index(upper_curr)
			st.add_index(upper_next)

	st.generate_normals()
	_mesh_instance.mesh = st.commit()

func _setup_hurtbox_static():
	# Legacy static collision setup
	if _hurtbox: _hurtbox.queue_free()
	_hurtbox = Area.new()
	_hurtbox.name = "Hurtbox"
	add_child(_hurtbox)

	var points = path_curve.get_baked_points()
	if points.size() < 2: return

	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i+1]
		var mid = (p1 + p2) * 0.5
		var length = p1.distance_to(p2)

		var col = CollisionShape.new()
		var capsule = CapsuleShape.new()
		capsule.radius = cable_radius * 2.0
		capsule.height = length
		col.shape = capsule
		_hurtbox.add_child(col)
		col.transform.origin = mid
		col.look_at(p2, Vector3.UP)

func _setup_hurtbox_dynamic():
	if _hurtbox: _hurtbox.queue_free()
	_hurtbox = Area.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 1
	_hurtbox.collision_mask = 0
	add_child(_hurtbox)

	# Create pool of collision shapes
	# We use fewer shapes for physics (e.g. one every 2 segments)
	for i in range(_particles.size() - 1):
		var col = CollisionShape.new()
		var capsule = CapsuleShape.new()
		capsule.radius = cable_radius * 2.0
		capsule.height = segment_length # Initial approximation
		col.shape = capsule
		col.name = "Col_%d" % i
		_hurtbox.add_child(col)

func _update_hurtbox_dynamic():
	if not _hurtbox: return

	for i in range(_particles.size() - 1):
		var col = _hurtbox.get_child(i) as CollisionShape
		if not col: continue

		var p1 = _particles[i].pos
		var p2 = _particles[i+1].pos
		var mid = (p1 + p2) * 0.5

		col.transform.origin = mid
		# look_at requires target != origin.
		if p1.distance_squared_to(p2) > 0.0001:
			col.look_at(p2, Vector3.UP)
			# Re-adjust height if segments stretch significantly (they shouldn't due to constraints)
			# (col.shape as CapsuleShape).height = p1.distance_to(p2)
			# Updating resource (Shape) every frame is bad if shared.
			# Since we created unique shapes, it's okay, but maybe unnecessary if constraints hold.

func _build_csg():
	# Legacy implementation
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

func _generate_circle_polygon(radius: float, sides: int) -> PoolVector2Array:
	var arr = PoolVector2Array()
	for i in range(sides):
		var angle = (i / float(sides)) * TAU
		arr.append(Vector2(cos(angle), sin(angle)) * radius)
	return arr

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0:
		emit_signal("connection_broken")
		queue_free()

func damage(amount: float) -> void:
	take_damage(amount)

func hit(amount: float) -> void:
	take_damage(amount)

func is_broken() -> bool:
	return health <= 0

func init_from_curve(curve: Curve3D) -> void:
	path_curve = curve
	build()

# --- Energy Reactivity ---

func _update_visuals() -> void:
	._update_visuals() # Call parent
	
	var t = target_progress if anim_progress < 0.01 else anim_progress
	
	if _shader_mat:
		_shader_mat.set_shader_param("activation_level", t)
	elif cable_material:
		# Legacy
		var color = Color(0.1, 0.1, 0.1).linear_interpolate(Color(0.0, 1.0, 0.8), t)
		cable_material.albedo_color = color
		cable_material.emission = color * t * 5.0

func interact(_from = null) -> void:
	.set_active(not is_active)

func set_active(value: bool, immediate: bool = false) -> void:
	.set_active(value, immediate)
	_update_visuals()

# Legacy compatibility
var circuit_state: String = "idle"
func get_state() -> String: return circuit_state
func set_state(value: String) -> void: circuit_state = value
