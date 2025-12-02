extends Area

# Fuerza de elevación (lift) aplicada como gravedad local en dirección basis.y
# Rotando el nodo cambias la dirección del viento (volumen tipo conveyor 3D)
export (float) var lift := -12.0
export (bool) var debug := false
export (float) var max_speed_along_wind := 6.0

var _bodies := []
var _prev_positions := {}
onready var _particles := $Particles

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

func _on_body_entered(body: Object) -> void:
	if body in _bodies:
		return
	_bodies.append(body)
	if debug:
		print("[WindZone] body_entered: ", body.name)
	# Aplicar override de gravedad inmediatamente
	if body.has_method("set_gravity_override"):
		var grav = global_transform.basis.y * lift
		body.set_gravity_override(grav)
		if debug:
			print("[WindZone] set_gravity_override to: ", grav, " on:", body.name)

func _on_body_exited(body: Object) -> void:
	if body in _bodies:
		_bodies.erase(body)
	if debug:
		print("[WindZone] body_exited: ", body.name)
	# Restaurar gravedad normal
	if is_instance_valid(body) and body.has_method("clear_gravity_override"):
		body.clear_gravity_override()
		if debug:
			print("[WindZone] cleared gravity_override for: ", body.name)

func _physics_process(delta: float) -> void:
	# Dirección local "up" del WindZone en espacio mundial
	var world_dir := global_transform.basis.orthonormalized().y
	
	# Actualizar partículas con dirección del viento
	if is_instance_valid(_particles):
		_particles.direction = world_dir
		_particles.initial_velocity = clamp(abs(lift), 0.0, 15.0)
		_particles.spread = 0.0
		_particles.gravity = Vector3.ZERO
	
	# Mantener override de gravedad activo mientras los cuerpos están dentro
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		# Actualizar gravedad aplicada en dirección del zone
		if body.has_method("set_gravity_override"):
			# Estimar velocidad del cuerpo para capear empuje si supera el máximo
			var prev_pos = _prev_positions.get(body, body.global_transform.origin)
			var velocity = (body.global_transform.origin - prev_pos) / delta
			_prev_positions[body] = body.global_transform.origin
			var speed_along = velocity.dot(world_dir)
			var grav = world_dir * lift
			if speed_along > max_speed_along_wind:
				# No empujar más si ya supera la velocidad máxima en dirección del viento
				grav = Vector3.ZERO
			body.set_gravity_override(grav)
			if debug and OS.get_ticks_msec() % 250 < 16:
				print("[WindZone] updating gravity_override: ", grav, " speed_along=", speed_along, " on: ", body.name)
