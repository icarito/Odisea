extends KinematicBody

export(float) var speed = 3.0
export(bool) var ping_pong = true
export(float) var wait_time = 0.5
export(Curve) var acceleration_curve
export(NodePath) var target_node_path
export(bool) var active := true
export(bool) var debug_velocity := false
export(float) var reach_threshold := 0.3 # distancia para considerar que llegó al objetivo
export(bool) var parametric_mode := true # si true usa interpolación por progreso en lugar de move_and_slide
export(bool) var clamp_curve_output := true # evita sobrepasar A/B si la curva sale de [0,1]
export(bool) var use_curve_as_speed := true # curva escala velocidad (no posición)
export(float) var min_speed_scale := 0.05 # velocidad mínima para no quedarse congelado si la curva da 0

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
var _prev_to_target := Vector3.ZERO
var progress := 0.0 # 0..1
var direction_sign := 1 # 1 hacia target, -1 hacia start
var path_length := 0.0
var path_dir := Vector3.ZERO
var dist_along := 0.0 # distancia recorrida en modo paramétrico

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
	path_length = (target_pos - start_pos).length()
	path_dir = (target_pos - start_pos).normalized() if path_length > 0 else Vector3.ZERO
	progress = 0.0
	direction_sign = 1
	dist_along = 0.0
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

	if parametric_mode:
		if path_length <= 0.001:
			return
		# Actualizar progress desde distancia recorrida
		progress = dist_along / path_length
		progress = clamp(progress, 0.0, 1.0)
		# Calcular factor de velocidad por curva (solo si se usa como velocidad)
		var speed_scale := 1.0
		if acceleration_curve and use_curve_as_speed:
			speed_scale = acceleration_curve.interpolate(progress)
			if clamp_curve_output:
				speed_scale = max(speed_scale, 0.0)
		# Evitar bloqueo por tramo plano de la curva
		if speed_scale < min_speed_scale:
			speed_scale = min_speed_scale
		# Avance distancia (integración suave)
		var v = speed * speed_scale
		dist_along += v * delta * direction_sign
		# Verificar límites y ping-pong
		if dist_along >= path_length:
			dist_along = path_length
			_on_reach_target()
			if ping_pong:
				direction_sign = -1
			else:
				dist_along = 0.0
		elif dist_along <= 0.0:
			dist_along = 0.0
			_on_reach_target()
			if ping_pong:
				direction_sign = 1
			else:
				dist_along = path_length
		# Posición nueva
		var new_pos := start_pos + path_dir * dist_along
		var platform_velocity := (new_pos - last_position) / max(delta, 0.0001)
		global_transform.origin = new_pos
		last_position = new_pos
		for body in platform_bodies:
			if body and body.has_method("set_external_velocity"):
				body.set_external_velocity(platform_velocity)
				if body.has_method("set_external_source_is_static"):
					body.set_external_source_is_static(false)
		if debug_velocity:
			_debug_accum += delta
			if _debug_accum >= 0.5:
				_debug_accum = 0.0
				print("[Platform] dist_along=", dist_along, " progress=", progress, " dir=", direction_sign, " speed_scale=", speed_scale, " v=", platform_velocity)
		return

	# MODO LEGACY (no parametric): mantener código previo pero con mejor llegada
	var current_pos := global_transform.origin
	var to_target = _target - current_pos
	var dist = to_target.length()
	if dist <= reach_threshold:
		global_transform.origin = _target
		_on_reach_target()
		last_position = global_transform.origin
		return
	_direction = to_target.normalized()
	var v = speed
	move_and_slide(_direction * v)
	var platform_velocity := (global_transform.origin - last_position) / max(delta, 0.0001)
	last_position = global_transform.origin
	for body in platform_bodies:
		if body and body.has_method("set_external_velocity"):
			body.set_external_velocity(platform_velocity)
			if body.has_method("set_external_source_is_static"):
				body.set_external_source_is_static(false)
	if debug_velocity:
		_debug_accum += delta
		if _debug_accum >= 0.5:
			_debug_accum = 0.0
			print("[Platform-Legacy] dist=", dist, " v=", platform_velocity)


func _on_reach_target():
	if wait_time > 0.0:
		_waiting = true
		_wait_timer = wait_time

	if parametric_mode:
		# En modo paramétrico solo se ajusta en función de progress/direction_sign
		return

	# Legacy
	if ping_pong:
		if _target == target_pos:
			_target = start_pos
		else:
			_target = target_pos
	else:
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
