extends Area
class_name WindTunnelV2
tool

# WindTunnelV2.gd - Deterministic Wind Force
# Applies external velocity to supported bodies (like PlayerControllerV2).

export(Vector3) var wind_velocity := Vector3(0, 0, -10) setget set_wind_velocity
export(bool) var is_active := true setget set_active

func _ready():
	add_to_group("replay_sync")
	_update_particles()

func set_active(val):
	is_active = val
	_update_particles()

func set_wind_velocity(val):
	wind_velocity = val
	_update_particles()

func _update_particles():
	for child in get_children():
		if child is CPUParticles:
			child.emitting = is_active
			if is_active and wind_velocity.length() > 0.001:
				child.direction = wind_velocity.normalized()
				child.initial_velocity = wind_velocity.length()

func step(_dt: float):
	if not is_active: return
	if Engine.editor_hint: return

	var bodies = get_overlapping_bodies()
	for body in bodies:
		_apply_wind_to_body(body, _dt)

func _apply_wind_to_body(body: Node, dt: float) -> void:
	if not is_instance_valid(body): return
	var global_wind := global_transform.basis.xform(wind_velocity)
	if body.has_method("set_external_velocity"):
		body.set_external_velocity(global_wind)
		if body.has_method("set_external_source_is_static"):
			body.set_external_source_is_static(false)
	elif body is RigidBody and (body as RigidBody).mode != RigidBody.MODE_STATIC:
		(body as RigidBody).apply_central_impulse(global_wind * dt)

func _physics_process(delta):
	step(delta)

# --- SNAPSHOT ---

func get_snapshot() -> Dictionary:
	return {
		"active": is_active
	}

func restore_snapshot(data: Dictionary):
	set_active(data.get("active", true))
