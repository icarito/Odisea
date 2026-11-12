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

export(Vector3) var size := Vector3(2.0, 0.2, 1.0) setget set_size
export(float, 1.0, 5000.0) var density := 150.0 # kg/m3; la masa sale de size * density
export(Color) var color := Color(0.55, 0.57, 0.6)
# Retenida: queda fija (MODE_STATIC) hasta que release()/set_active(true) la suelte.
export(bool) var held := false

var _shape: CollisionShape = null
var _mesh: MeshInstance = null


func _ready() -> void:
	collision_layer = LAYER_PROP
	collision_mask = MASK_PROP
	add_to_group("machine_part")
	add_to_group("replay_sync")
	_build()
	if held:
		mode = MODE_STATIC
	_ignore_players()
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
		var mat := SpatialMaterial.new()
		mat.albedo_color = color
		mat.metallic = 0.6
		mat.roughness = 0.55
		_mesh.material_override = mat
		add_child(_mesh)
	(_shape.shape as BoxShape).extents = size * 0.5
	(_mesh.mesh as CubeMesh).size = size
	mass = max(1.0, size.x * size.y * size.z * density)


# Suelta una pieza retenida. set_active() es el alias que usa el circuito logico (OLCS).
func release() -> void:
	held = false
	mode = MODE_RIGID
	sleeping = false


func set_active(value: bool, _immediate: bool = false) -> void:
	if value:
		release()


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
	mode = MODE_STATIC if held else MODE_RIGID
	sleeping = bool(data.get("sleeping", false))
