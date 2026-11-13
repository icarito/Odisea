extends RigidBody
# Sin class_name: registrarlo exige que el editor reescriba project.godot.

# FD-320: pieza rigida de maquina (viga, placa, contrapeso). Una caja con masa; lo que la
# vuelve "viga" o "peso" son sus dimensiones y su densidad, no una clase aparte.
#
# El jugador puede pararse encima y ser lanzado (ver PlayerControllerV2._track_rigid_platform).
# Para eso la pieza registra una excepcion de colision UNILATERAL con el jugador: el solver
# rigido deja de verlo (un KinematicBody es masa infinita y frenaria el brazo), pero el
# move_and_slide del jugador sigue viendo la pieza.

const LAYER_PROP := 68 # mismas capas que PushableBoxV2 (4 + 64)
const MASK_PROP := 71
const DiamondPlateTex = preload("res://materials/diamondplate.png")
const DiamondPlateSpec = preload("res://materials/diamondplate_spec.png")
const GrateTex = preload("res://textures/kenney_prototype_textures/dark/texture_08.png")
const HazardMat = preload("res://materials/diamondPlateAluminum/seam_hazard_stripes.tres")

signal cut

export(Vector3) var size := Vector3(2.0, 0.2, 1.0) setget set_size
export(float, 1.0, 5000.0) var density := 150.0 # kg/m3; la masa sale de size * density
export(Color) var color := Color(0.55, 0.57, 0.6)
export(String) var style := "" # "beam", "weight", "gondola", "strut", "cargo"
# Retenida: queda fija (MODE_STATIC) hasta que release()/set_active(true) la suelte.
export(bool) var held := false
# Cortable con el laser del Multi-Tool: acumula calor en _physics_process y al llegar a
# cut_heat_time se desactiva y emite la senal `cut` (reusable por reset_station y replay).
export(bool) var cuttable := false
export(float, 0.05, 5.0) var cut_heat_time := 0.35
export(float, 0.1, 5.0) var cut_cool_rate := 1.5

var _shape: CollisionShape = null
var _mesh: MeshInstance = null
var _trim: Spatial = null
var _heat := 0.0
var _laser_hit_this_tick := false
var _is_cut := false


func _ready() -> void:
	set_physics_process(false)
	collision_layer = LAYER_PROP
	collision_mask = MASK_PROP
	add_to_group("machine_part")
	add_to_group("replay_sync")
	_build()
	if held:
		mode = MODE_STATIC
	# Diferido: el jugador entra al grupo "player" en su propio _ready, que puede correr
	# despues que el de esta pieza.
	call_deferred("_ignore_players")
	get_tree().connect("node_added", self, "_on_tree_node_added")


func set_size(v: Vector3) -> void:
	size = v
	if is_inside_tree():
		_build()


func _build() -> void:
	if _shape == null:
		_shape = CollisionShape.new()
		_shape.shape = BoxShape.new()
		add_child(_shape)
		_mesh = MeshInstance.new()
		_mesh.mesh = CubeMesh.new()
		add_child(_mesh)
	(_shape.shape as BoxShape).extents = size * 0.5
	(_mesh.mesh as CubeMesh).size = size
	mass = max(1.0, size.x * size.y * size.z * density)
	var mat := SpatialMaterial.new()
	mat.albedo_color = color
	mat.metallic = 0.68
	mat.roughness = 0.42
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 8.0
	mat.uv1_scale = Vector3(0.45, 0.45, 0.45)
	if not cuttable:
		mat.albedo_texture = DiamondPlateTex
		mat.metallic_texture = DiamondPlateSpec
		mat.normal_enabled = true
		mat.normal_texture = DiamondPlateTex
		mat.normal_scale = 0.65
	else:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy = 0.55
	_mesh.material_override = mat
	_rebuild_trim()


func _rebuild_trim() -> void:
	if _trim != null and is_instance_valid(_trim):
		_trim.queue_free()
	_trim = Spatial.new()
	_trim.name = "Trim"
	add_child(_trim)
	var dark_mat := SpatialMaterial.new()
	dark_mat.albedo_color = Color(0.14, 0.16, 0.18)
	dark_mat.metallic = 0.85
	dark_mat.roughness = 0.35
	if cuttable:
		# Cuello termico central y bridas de sujecion en los extremos.
		for s in [-1.0, 1.0]:
			var flange := MeshInstance.new()
			var fc := CubeMesh.new()
			fc.size = Vector3(size.x * 1.32, min(0.08, size.y * 0.18), size.z * 1.32)
			flange.mesh = fc
			flange.material_override = dark_mat
			flange.translation = Vector3(0, s * (size.y * 0.42), 0)
			_trim.add_child(flange)
		var ring := MeshInstance.new()
		var rc := CubeMesh.new()
		rc.size = Vector3(size.x * 1.18, min(0.12, size.y * 0.25), size.z * 1.18)
		ring.mesh = rc
		var ring_mat := SpatialMaterial.new()
		ring_mat.albedo_color = Color(1.0, 0.45, 0.05)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(1.0, 0.38, 0.02)
		ring_mat.emission_energy = 1.4
		ring.material_override = ring_mat
		_trim.add_child(ring)
	elif size.x >= 4.0 and size.y <= 0.4:
		# Viga / rampa de lanzamiento (SeesawArm, CatapultArm, CentrifugeArm): rieles laterales y franjas de seguridad.
		var rail_h := size.y + 0.06
		for sz in [-1.0, 1.0]:
			var rail := MeshInstance.new()
			var rc := CubeMesh.new()
			rc.size = Vector3(size.x * 0.98, rail_h, 0.09)
			rail.mesh = rc
			rail.material_override = dark_mat
			rail.translation = Vector3(0, 0.02, sz * (size.z * 0.5 - 0.04))
			_trim.add_child(rail)
		for sx in [-1.0, 1.0]:
			var tip := MeshInstance.new()
			var tc := CubeMesh.new()
			tc.size = Vector3(0.38, size.y + 0.02, size.z * 0.92)
			tip.mesh = tc
			tip.material_override = HazardMat
			tip.translation = Vector3(sx * (size.x * 0.5 - 0.22), 0.005, 0)
			_trim.add_child(tip)
	elif size.x >= 2.2 and size.z >= 2.2 and size.y <= 0.35:
		# Gondola / plataforma suspendida: cantoneras y borde de seguridad.
		for sx in [-1.0, 1.0]:
			var curb := MeshInstance.new()
			var cc := CubeMesh.new()
			cc.size = Vector3(0.12, size.y + 0.08, size.z)
			curb.mesh = cc
			curb.material_override = HazardMat
			curb.translation = Vector3(sx * (size.x * 0.5 - 0.06), 0.03, 0)
			_trim.add_child(curb)
	elif abs(size.x - size.y) < 0.25 and abs(size.y - size.z) < 0.25 and size.x >= 0.75:
		# Contrapeso / lastre: cinchas metalicas perimetrales y argolla superior.
		for sy in [-0.32, 0.32]:
			var band := MeshInstance.new()
			var bc := CubeMesh.new()
			bc.size = Vector3(size.x * 1.04, 0.08, size.z * 1.04)
			band.mesh = bc
			band.material_override = dark_mat
			band.translation = Vector3(0, sy * size.y, 0)
			_trim.add_child(band)
		var lug := MeshInstance.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.14
		lc.bottom_radius = 0.18
		lc.height = 0.12
		lug.mesh = lc
		lug.material_override = dark_mat
		lug.translation = Vector3(0, size.y * 0.5 + 0.05, 0)
		_trim.add_child(lug)


# Suelta una pieza retenida. set_active() es el alias que usa el circuito logico (OLCS).
func release() -> void:
	if _is_cut:
		return
	held = false
	mode = MODE_RIGID
	sleeping = false


func set_active(value: bool, _immediate: bool = false) -> void:
	if value:
		release()


func laser_hit() -> void:
	if not cuttable or _is_cut:
		return
	_laser_hit_this_tick = true
	set_physics_process(true)


func cut_now() -> void:
	if _is_cut:
		return
	_heat = cut_heat_time
	_apply_cut_state(true)
	emit_signal("cut")


func is_cut() -> bool:
	return _is_cut


func _physics_process(delta: float) -> void:
	if _is_cut:
		set_physics_process(false)
		return
	if _laser_hit_this_tick:
		_laser_hit_this_tick = false
		_heat += delta
		_update_heat_visual()
		if _heat >= cut_heat_time:
			_apply_cut_state(true)
			emit_signal("cut")
	else:
		_heat = max(0.0, _heat - cut_cool_rate * delta)
		_update_heat_visual()
		if _heat <= 0.0:
			set_physics_process(false)


func _update_heat_visual() -> void:
	if _mesh == null or not (_mesh.material_override is SpatialMaterial):
		return
	var mat := _mesh.material_override as SpatialMaterial
	var t: float = clamp(_heat / max(0.01, cut_heat_time), 0.0, 1.0)
	var hot := Color(1.0, 0.22, 0.04)
	mat.albedo_color = color.linear_interpolate(hot, t)
	mat.emission_enabled = t > 0.02
	if mat.emission_enabled:
		mat.emission = hot
		mat.emission_energy = t * 2.2


func _apply_cut_state(cut_state: bool) -> void:
	_is_cut = cut_state
	if cut_state:
		set_physics_process(false)
		visible = false
		collision_layer = 0
		collision_mask = 0
		if _shape != null:
			_shape.disabled = true
		mode = MODE_STATIC
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		visible = true
		collision_layer = LAYER_PROP
		collision_mask = MASK_PROP
		if _shape != null:
			_shape.disabled = false
		mode = MODE_STATIC if held else MODE_RIGID
		_update_heat_visual()


func reset_to_layout(item: Dictionary, initial_transform: Transform) -> void:
	held = bool(item.get("held", false))
	_heat = 0.0
	_laser_hit_this_tick = false
	_apply_cut_state(false)
	transform = initial_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false


func _on_tree_node_added(node: Node) -> void:
	if node is KinematicBody:
		call_deferred("_ignore_players")


func _ignore_players() -> void:
	if not is_inside_tree():
		return
	for player in get_tree().get_nodes_in_group("player"):
		if player is PhysicsBody:
			add_collision_exception_with(player)


func get_snapshot() -> Dictionary:
	var o := global_transform.origin
	var r := global_transform.basis.get_euler()
	return {
		"pos": [o.x, o.y, o.z],
		"rot": [r.x, r.y, r.z],
		"vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"ang": [angular_velocity.x, angular_velocity.y, angular_velocity.z],
		"held": held,
		"sleeping": sleeping,
		"cut": _is_cut,
		"heat": _heat,
	}


func restore_snapshot(data: Dictionary) -> void:
	var p: Array = data.get("pos", [0, 0, 0])
	var r: Array = data.get("rot", [0, 0, 0])
	var v: Array = data.get("vel", [0, 0, 0])
	var a: Array = data.get("ang", [0, 0, 0])
	global_transform = Transform(Basis(Vector3(r[0], r[1], r[2])), Vector3(p[0], p[1], p[2]))
	linear_velocity = Vector3(v[0], v[1], v[2])
	angular_velocity = Vector3(a[0], a[1], a[2])
	held = bool(data.get("held", false))
	_heat = float(data.get("heat", 0.0))
	_apply_cut_state(bool(data.get("cut", false)))
	if not _is_cut:
		sleeping = bool(data.get("sleeping", false))
