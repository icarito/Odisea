tool
extends BaseZoneV2
class_name WindTunnelV2

# WindTunnelV2.gd - Deterministic wind force application
# Applies a Vector3 force to all bodies in the zone.

# --- EXPORTED TUNING ---
export(Vector3) var wind_force := Vector3(0, 0, 10)
export(bool) var is_active := true

func _ready():
	add_to_group("replay_sync")
	._ready()

func step(dt: float):
	if not is_active:
		return

	for body_id in _bodies_in_zone:
		var body = _bodies_in_zone[body_id]
		if is_instance_valid(body):
			if body.has_method("apply_wind_force"):
				body.apply_wind_force(wind_force)
			elif body is RigidBody:
				# Apply impulse based on mass for standard RigidBodies
				body.apply_central_impulse(wind_force * dt)

func _physics_process(delta):
	if not SessionManager.is_manual_mode:
		step(delta)

func set_active(active: bool):
	is_active = active

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"is_active": is_active
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("is_active", true)
