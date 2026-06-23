extends StaticBody
class_name CylindricalInteriorCollider

export(float, 0.1, 1000.0) var inner_radius: float = 30.0
export(float, 0.05, 10.0) var wall_thickness: float = 4.0
export(float, 0.1, 10000.0) var height: float = 8000.0
export(int, 8, 64) var segments: int = 32
export(NodePath) var constrained_body_path: NodePath
export(float, 0.0, 5.0) var body_clearance: float = 0.55

var _constrained_body: KinematicBody = null

func _ready() -> void:
	_constrained_body = get_node_or_null(constrained_body_path) as KinematicBody
	var angle_step: float = TAU / float(segments)
	var half_width: float = inner_radius * tan(angle_step * 0.5) * 1.1
	var center_radius: float = inner_radius + wall_thickness * 0.5
	for index in range(segments):
		var angle: float = angle_step * float(index)
		var shape := BoxShape.new()
		shape.extents = Vector3(half_width, height * 0.5, wall_thickness * 0.5)
		var collision := CollisionShape.new()
		collision.name = "Wall%02d" % index
		collision.shape = shape
		collision.rotation.y = -angle
		collision.translation = Vector3(sin(angle), 0.0, cos(angle)) * center_radius
		add_child(collision)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_constrained_body):
		return
	var local_position: Vector3 = to_local(_constrained_body.global_transform.origin)
	var radial := Vector2(local_position.x, local_position.z)
	var max_radius: float = inner_radius - body_clearance
	if radial.length_squared() <= max_radius * max_radius:
		return
	radial = radial.normalized()
	local_position.x = radial.x * max_radius
	local_position.z = radial.y * max_radius
	_constrained_body.global_transform.origin = to_global(local_position)
	if "velocity" in _constrained_body:
		var outward_local := Vector3(radial.x, 0.0, radial.y)
		var outward_world: Vector3 = global_transform.basis.xform(outward_local).normalized()
		var body_velocity: Vector3 = _constrained_body.velocity
		var outward_speed: float = body_velocity.dot(outward_world)
		if outward_speed > 0.0:
			_constrained_body.velocity = body_velocity - outward_world * outward_speed
