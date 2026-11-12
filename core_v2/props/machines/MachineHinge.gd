extends Spatial
# Sin class_name: registrarlo exige que el editor reescriba project.godot.

# FD-320: bisagra de maquina. Une una pieza a un ancla fija (pivote de balancin, eje de
# catapulta) o a otra pieza (gondola de pendulo). El eje de giro es el Z local del nodo.
#
# Box3D no ancla joints al mundo: siempre hacen falta dos cuerpos. Si no se da body_b, la
# bisagra crea su propio StaticBody como ancla.

export(NodePath) var body_a_path: NodePath
export(NodePath) var body_b_path: NodePath # vacio = ancla fija en este punto
export(bool) var use_limit := false
export(float, -180.0, 180.0) var limit_lower_deg := -45.0
export(float, -180.0, 180.0) var limit_upper_deg := 45.0
# Motor: gira body_a a motor_speed (rad/s) con hasta motor_torque. Lo enciende
# set_active(), que es la interfaz del circuito logico (OLCS) y de palancas.
export(bool) var motor_enabled := false
export(float) var motor_speed := 2.0
export(float) var motor_torque := 4000.0
export(bool) var show_axle := true

var _joint: HingeJoint = null
var _anchor: StaticBody = null


func _ready() -> void:
	add_to_group("machine_hinge")
	if show_axle:
		_build_axle()
	# Diferido: las piezas hermanas terminan su _ready (y entran al espacio fisico) antes
	# de crear el joint.
	call_deferred("attach")


func attach() -> void:
	detach()
	var body_a := get_node_or_null(body_a_path) as PhysicsBody
	if body_a == null:
		return
	var body_b := get_node_or_null(body_b_path) as PhysicsBody
	if body_b == null:
		if _anchor == null:
			_anchor = StaticBody.new()
			_anchor.name = "Anchor"
			_anchor.collision_layer = 0
			_anchor.collision_mask = 0
			add_child(_anchor)
		body_b = _anchor
	_joint = HingeJoint.new()
	_joint.name = "Joint"
	add_child(_joint)
	_joint.set_flag(HingeJoint.FLAG_USE_LIMIT, use_limit)
	_joint.set_param(HingeJoint.PARAM_LIMIT_LOWER, deg2rad(limit_lower_deg))
	_joint.set_param(HingeJoint.PARAM_LIMIT_UPPER, deg2rad(limit_upper_deg))
	_joint.set_param(HingeJoint.PARAM_MOTOR_TARGET_VELOCITY, motor_speed)
	_joint.set_param(HingeJoint.PARAM_MOTOR_MAX_IMPULSE, motor_torque)
	_joint.set_flag(HingeJoint.FLAG_ENABLE_MOTOR, motor_enabled)
	_joint.set_node_a(_joint.get_path_to(body_a))
	_joint.set_node_b(_joint.get_path_to(body_b))


func detach() -> void:
	if _joint != null and is_instance_valid(_joint):
		_joint.queue_free()
	_joint = null


func set_active(value: bool, _immediate: bool = false) -> void:
	motor_enabled = value
	if _joint != null and is_instance_valid(_joint):
		_joint.set_flag(HingeJoint.FLAG_ENABLE_MOTOR, value)
	var body_a := get_node_or_null(body_a_path) as RigidBody
	if body_a != null:
		body_a.sleeping = false


func _build_axle() -> void:
	var mesh := MeshInstance.new()
	mesh.name = "Axle"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 1.4
	cyl.radial_segments = 12
	mesh.mesh = cyl
	# El cilindro nace sobre Y; el eje de la bisagra es Z.
	mesh.rotation = Vector3(PI * 0.5, 0, 0)
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.9, 0.45, 0.1)
	mat.metallic = 0.7
	mat.roughness = 0.4
	mesh.material_override = mat
	add_child(mesh)
