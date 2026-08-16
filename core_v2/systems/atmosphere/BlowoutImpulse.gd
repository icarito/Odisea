extends Spatial
class_name BlowoutImpulse

# BlowoutImpulse.gd — le da cuerpo al estallido de sobrepresión (FD-258).
#
# `PressureSection` emite `blowout(radius, force)` y hasta ahora no lo escuchaba nadie: la
# sala construía una amenaza que al llegar no hacía nada. Este componente es el que la
# convierte en algo que se ve y que se siente:
#
#   - dispara el flipbook de explosión (el prop de assets/flipbook_particles), y
#   - empuja lo que haya alrededor: al jugador y a cualquier cuerpo rígido.
#
# El empuje al jugador va por `set_external_velocity`, que es la API que el proyecto
# reserva justamente para knockback, viento y explosiones (AGENTS.md §5.2). Los rígidos
# reciben un impulso normal.

# De dónde escucha el estallido.
export(NodePath) var section_path: NodePath
# El prop de explosión (flipbook + luz). Si no está, el empuje ocurre igual.
export(NodePath) var explosion_path: NodePath
# Empuje al jugador, en m/s, a quemarropa. Cae con la distancia.
export(float) var player_push: float = 9.0
# Impulso a los cuerpos rígidos, a quemarropa.
export(float) var body_push: float = 14.0
# Componente vertical del empuje: una sobrepresión levanta, no solo empuja de costado.
export(float) var lift_ratio: float = 0.45
# Multiplica el radio que informa la sección, por si el efecto tiene que abarcar más.
export(float) var radius_scale: float = 1.0
# Cuánto dura la onda. set_external_velocity, tanto en el jugador como en las cajas, es un
# controlador continuo (persigue una velocidad objetivo), no un impulso: aplicado un solo
# frame mueve centímetros. Sostenerlo un cuarto de segundo es lo que se siente como golpe.
export(float) var shock_duration: float = 0.25

signal blowout_felt(position, radius)

var _explosion: Node = null
var _section: Node = null
var _shock_timer: float = 0.0
var _shock_radius: float = 0.0
var _shock_force: float = 0.0


func _ready() -> void:
	add_to_group("replay_sync")
	_section = get_node_or_null(section_path)
	_explosion = get_node_or_null(explosion_path)
	if _explosion:
		_set_explosion_visible(false)
		# El prop de explosión viene con autoplay y la animación en loop: una vez visible
		# se repetiría para siempre. Se le corta el loop y se lo apaga al terminar.
		var anim = _explosion.get_node_or_null("AnimationPlayer")
		if anim:
			anim.stop()
			if anim.has_animation("Explode"):
				anim.get_animation("Explode").loop = false
			if not anim.is_connected("animation_finished", self, "_on_explosion_finished"):
				anim.connect("animation_finished", self, "_on_explosion_finished")
	if _section and _section.has_signal("blowout"):
		_section.connect("blowout", self, "_on_blowout")


func _on_blowout(radius: float, force: float) -> void:
	_shock_radius = max(radius * radius_scale, 0.1)
	_shock_force = force
	_shock_timer = shock_duration
	_play_explosion()
	_push_everything(_shock_radius, force)
	emit_signal("blowout_felt", global_transform.origin, _shock_radius)


func _physics_process(delta: float) -> void:
	if _shock_timer <= 0.0:
		return
	_shock_timer -= delta
	# Solo el jugador: a los cuerpos rígidos ya se les dio su impulso, que es instantáneo.
	# Repetírselo cada frame durante la onda los mandaba fuera del mapa.
	_push_everything(_shock_radius, _shock_force, false)


func _play_explosion() -> void:
	if _explosion == null:
		return
	_set_explosion_visible(true)
	var anim = _explosion.get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation("Explode"):
		anim.stop()
		anim.play("Explode")


func _on_explosion_finished(_anim_name: String) -> void:
	_set_explosion_visible(false)


func _set_explosion_visible(value: bool) -> void:
	if _explosion and _explosion is Spatial:
		_explosion.visible = value


func _push_everything(radius: float, force: float, impulse_bodies: bool = true) -> void:
	var space := get_world().direct_space_state
	if space == null:
		return
	var shape := SphereShape.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters.new()
	query.set_shape(shape)
	query.transform = Transform(Basis(), global_transform.origin)
	# Entorno, jugador, props y cuerpos varios: todo lo que pueda moverse.
	query.collision_mask = 0x7FFFFFFF
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var origin: Vector3 = global_transform.origin
	var seen := {}
	for hit in space.intersect_shape(query, 32):
		var body = hit.get("collider")
		if body == null or not is_instance_valid(body) or seen.has(body):
			continue
		seen[body] = true
		var to_body: Vector3 = body.global_transform.origin - origin
		var distance: float = to_body.length()
		var direction: Vector3 = Vector3.UP if distance < 0.05 else to_body / distance
		direction.y += lift_ratio
		direction = direction.normalized()
		# La fuerza cae con la distancia: a quemarropa empuja, en el borde apenas roza.
		var falloff: float = clamp(1.0 - distance / radius, 0.0, 1.0)

		if body.is_in_group("player") and body.has_method("set_external_velocity"):
			body.set_external_velocity(direction * player_push * falloff * max(force, 0.1) / 12.0)
			if body.has_method("set_external_source_is_static"):
				body.set_external_source_is_static(false)
		elif body is RigidBody and impulse_bodies:
			# Las cajas del proyecto (PushableBoxV2) viven en KINEMATIC hasta que algo las
			# despierta, y en ese modo apply_impulse no hace nada. Primero se las despierta
			# y recién ahí el impulso tiene efecto.
			if body.has_method("wake_up"):
				body.wake_up()
			var push: Vector3 = direction * body_push * falloff * max(force, 0.1) / 12.0
			if body.mode == RigidBody.MODE_RIGID:
				body.apply_impulse(Vector3.ZERO, push * body.mass * 0.12)
			elif body.has_method("set_external_velocity"):
				body.set_external_velocity(push)


func get_snapshot() -> Dictionary:
	return {"shock_timer": _shock_timer, "shock_radius": _shock_radius, "shock_force": _shock_force}


func restore_snapshot(data: Dictionary) -> void:
	_shock_timer = float(data.get("shock_timer", 0.0))
	_shock_radius = float(data.get("shock_radius", 0.0))
	_shock_force = float(data.get("shock_force", 0.0))
