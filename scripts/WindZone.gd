extends Area

export (float) var lift_force := 6.0
export (float) var max_speed := 8.0
export (bool) var pulsating := false
export (float) var pulse_amplitude := 0.5
export (float) var pulse_frequency := 1.0

var _bodies := []
var _time := 0.0

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

func _on_body_entered(body: Object) -> void:
	if body in _bodies:
		return
	_bodies.append(body)

func _on_body_exited(body: Object) -> void:
	if body in _bodies:
		_bodies.erase(body)
	if is_instance_valid(body) and body.has_method("set_external_velocity"):
		body.set_external_velocity(Vector3.ZERO)

func _physics_process(delta: float) -> void:
	_time += delta
	var pulse := 1.0
	if pulsating:
		pulse += sin(_time * TAU * pulse_frequency) * pulse_amplitude
	var up_vel := clamp(lift_force * pulse, 0.0, max_speed)
	var world_push := global_transform.basis.xform(Vector3(0, up_vel, 0))
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(world_push)
		elif body is RigidBody:
			# Aproxima fuerza para rigidbodies
			body.add_central_force(Vector3(0, lift_force * pulse, 0))
