extends Area
class_name WindTunnelV2
tool

# WindTunnelV2.gd - Deterministic Wind Force
# Applies external velocity to supported bodies (like PlayerControllerV2).

export(Vector3) var wind_velocity := Vector3(0, 0, -10)
export(bool) var is_active := true setget set_active

func _ready():
	add_to_group("replay_sync")

func set_active(val):
	is_active = val

func step(_dt: float):
	if not is_active: return
	if Engine.editor_hint: return

	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(wind_velocity)
			if body.has_method("set_external_source_is_static"):
				# Treat wind as a static flow field for now
				body.set_external_source_is_static(true)

func _physics_process(delta):
	step(delta)

# --- SNAPSHOT ---

func get_snapshot() -> Dictionary:
	return {
		"active": is_active
	}

func restore_snapshot(data: Dictionary):
	set_active(data.get("active", true))
