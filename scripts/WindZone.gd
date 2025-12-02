extends Area

export (float) var lift_force := 6.0
export (float) var max_speed := 8.0
export (bool) var pulsating := false
export (float) var pulse_amplitude := 0.5
export (float) var pulse_frequency := 1.0
export (bool) var affect_rigid_bodies := true
export (bool) var use_accumulated_force_for_kinematic := true
export (bool) var debug = false

var _bodies := []
var _time := 0.0
onready var _particles := $Particles

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")
	# Add particles for wind visualization
	# Partículas de viento desde escena dedicada
	# Las partículas se configuran en la escena `WindZone.tscn`.

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
	# Fuerza efectiva del viento (magnitud) tras pulso
	var push_mag := lift_force * pulse
	# Dirección local "up" del WindZone en espacio mundial (entendible por partículas)
	var world_dir := global_transform.basis.y.normalized()
	var world_push := world_dir * push_mag
	if debug and OS.get_ticks_msec() % 250 < 16:
		print("[WindZone] bodies:", _bodies.size(), " dir:", world_dir, " mag:", push_mag)
	# Sincronizar feedback visual (CPUParticles expone propiedades directamente)
	if is_instance_valid(_particles):
		_particles.direction = global_transform.basis.y
		_particles.initial_velocity = clamp(push_mag, 0.0, max_speed)
		_particles.spread = 0.0
		_particles.gravity = Vector3(0,0,0)
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		# Acumular fuerza de viento por frame (contrarresta gravedad si push_mag es mayor)
		if use_accumulated_force_for_kinematic and body.has_method("accumulate_external_force"):
			body.accumulate_external_force(world_push * delta)
			if debug and OS.get_ticks_msec() % 250 < 16:
				print("[WindZone] accumulate force:", world_push * delta, " on:", body)
		elif body.has_method("set_external_velocity"):
			# Fallback: aplicar como velocidad (menos estable frente a gravedad)
			body.set_external_velocity(world_push)
			if debug and OS.get_ticks_msec() % 250 < 16:
				print("[WindZone] set_external_velocity:", world_push, " on:", body)
		elif affect_rigid_bodies and body is RigidBody:
			# Aproxima fuerza para rigidbodies
			body.add_central_force(world_push)
			if debug and OS.get_ticks_msec() % 250 < 16:
				print("[WindZone] add_central_force:", world_push, " on:", body)
