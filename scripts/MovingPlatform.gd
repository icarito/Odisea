extends KinematicBody

export(Vector3) var point_a = Vector3.ZERO
export(Vector3) var point_b = Vector3(0, 0, 10)
export(float) var speed = 3.0
export(bool) var ping_pong = true
export(float) var wait_time = 0.5
export(Curve) var acceleration_curve
export(bool) var start_at_a = true

var _target := Vector3.ZERO
var _direction := Vector3.ZERO
var _waiting := false
var _wait_timer := 0.0
var _t := 0.0
var last_position := Vector3.ZERO
var platform_bodies := []
onready var passenger_area: Area = $PassengerArea if has_node("PassengerArea") else null

func _ready():
	if start_at_a:
		_target = point_b
		translation = point_a
	else:
		_target = point_a
		translation = point_b
	last_position = global_transform.origin
	if passenger_area:
		if not passenger_area.is_connected("body_entered", self, "_on_PassengerArea_body_entered"):
			passenger_area.connect("body_entered", self, "_on_PassengerArea_body_entered")
		if not passenger_area.is_connected("body_exited", self, "_on_PassengerArea_body_exited"):
			passenger_area.connect("body_exited", self, "_on_PassengerArea_body_exited")

func _physics_process(delta):
	if _waiting:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_waiting = false
		return

	var to_target = _target - translation
	var dist = to_target.length()
	if dist < 0.01:
		_on_reach_target()
		return

	_direction = to_target.normalized()
	var v = speed
	if acceleration_curve:
		# t en [0,1] según progreso entre puntos
		var total = (point_b - point_a).length()
		var origin = point_b
		if start_at_a:
			origin = point_a
		var progressed = (translation - origin).length()
		var ratio = 0.0
		if total > 0.0:
			ratio = progressed / total
		_t = clamp(ratio, 0.0, 1.0)
		v *= acceleration_curve.interpolate(_t)

	move_and_slide(_direction * v)

	# Calcular velocidad instantánea y transferirla a pasajeros
	var current_pos := global_transform.origin
	var platform_velocity := (current_pos - last_position) / max(delta, 0.0001)
	last_position = current_pos
	for body in platform_bodies:
		if body and body.has_method("set_external_velocity"):
			body.set_external_velocity(platform_velocity)

func _on_reach_target():
	if wait_time > 0.0:
		_waiting = true
		_wait_timer = wait_time

	if ping_pong:
		if _target == point_b:
			_target = point_a
		else:
			_target = point_b
	else:
		# ciclo A->B->A continuo, mismo comportamiento
		if _target == point_b:
			_target = point_a
		else:
			_target = point_b

func _on_PassengerArea_body_entered(body):
	if body and not platform_bodies.has(body):
		platform_bodies.append(body)

func _on_PassengerArea_body_exited(body):
	if body:
		platform_bodies.erase(body)
