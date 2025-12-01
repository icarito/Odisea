extends KinematicBody

export(float) var speed = 3.0
export(bool) var ping_pong = true
export(float) var wait_time = 0.5
export(Curve) var acceleration_curve
export(NodePath) var target_node_path
export(bool) var active := true
export(bool) var debug_velocity := false

var _target := Vector3.ZERO
var _direction := Vector3.ZERO
var _waiting := false
var _wait_timer := 0.0
var _t := 0.0
var last_position := Vector3.ZERO
var platform_bodies := []
onready var passenger_area: Area = $PassengerArea if has_node("PassengerArea") else null
onready var target_node: Spatial = null
var start_pos := Vector3.ZERO # global
var target_pos := Vector3.ZERO # global
var _debug_accum := 0.0

func _ready():
	start_pos = global_transform.origin
	# Resolver nodo destino
	if target_node_path and has_node(target_node_path):
		target_node = get_node(target_node_path)
	elif has_node("Target"):
		target_node = $Target
	# Posición de destino
	if target_node:
		target_pos = target_node.global_transform.origin
	else:
		target_pos = start_pos + Vector3(0, 0, 10)
	_target = target_pos
	last_position = global_transform.origin
	if passenger_area:
		if not passenger_area.is_connected("body_entered", self, "_on_PassengerArea_body_entered"):
			passenger_area.connect("body_entered", self, "_on_PassengerArea_body_entered")
		if not passenger_area.is_connected("body_exited", self, "_on_PassengerArea_body_exited"):
			passenger_area.connect("body_exited", self, "_on_PassengerArea_body_exited")

func _physics_process(delta):
	if not active:
		return
	if _waiting:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_waiting = false
		return

	var current_pos := global_transform.origin
	var to_target = _target - current_pos
	var dist = to_target.length()
	if dist < 0.01:
		_on_reach_target()
		return

	_direction = to_target.normalized()
	var v = speed
	if acceleration_curve:
		# t en [0,1] según progreso entre puntos
		var total = (target_pos - start_pos).length()
		var origin = start_pos if _target == target_pos else target_pos
		var progressed = (current_pos - origin).length()
		var ratio = 0.0
		if total > 0.0:
			ratio = progressed / total
		_t = clamp(ratio, 0.0, 1.0)
		var f = acceleration_curve.interpolate(_t)
		if f <= 0.0:
			f = 1.0
		v *= f

	move_and_slide(_direction * v)

	# Calcular velocidad instantánea y transferirla a pasajeros
	var platform_velocity := (current_pos - last_position) / max(delta, 0.0001)
	last_position = current_pos
	for body in platform_bodies:
		if body and body.has_method("set_external_velocity"):
			body.set_external_velocity(platform_velocity)
	if debug_velocity:
		_debug_accum += delta
		if _debug_accum >= 0.5:
			_debug_accum = 0.0
			print("[Platform] v=", platform_velocity)

func _on_reach_target():
	if wait_time > 0.0:
		_waiting = true
		_wait_timer = wait_time

	if ping_pong:
		if _target == target_pos:
			_target = start_pos
		else:
			_target = target_pos
	else:
		# ciclo A->B->A continuo, mismo comportamiento
		if _target == target_pos:
			_target = start_pos
		else:
			_target = target_pos

func _on_PassengerArea_body_entered(body):
	if body and not platform_bodies.has(body):
		platform_bodies.append(body)

func _on_PassengerArea_body_exited(body):
	if body:
		platform_bodies.erase(body)
