tool
extends BaseZoneV2

# WindTunnelV2.gd - Deterministic Wind Area inheriting from BaseZoneV2
# Applies forces to PlayerControllerV2 and PushableBoxV2.

export(Vector3) var wind_force := Vector3(10, 0, 0)
export(bool) var is_active := true
export(float) var cycle_duration := 0.0 # 0 = constant
export(bool) var debug := false

var _time_accumulator := 0.0
var _pending_snapshot = null

func _ready():
	add_to_group("replay_sync")
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null

func step(dt: float) -> void:
	if cycle_duration > 0.0:
		_time_accumulator += dt
		# Simple 50/50 duty cycle for intermittency
		is_active = fmod(_time_accumulator, cycle_duration) < (cycle_duration * 0.5)

	_update_visuals(dt)

	if not is_active:
		return

	var area = _host_area if _host_area else self
	var bodies = area.get_overlapping_bodies()

	# Transform local wind_force to world space
	var world_force = global_transform.basis.xform(wind_force)

	for body in bodies:
		if not is_instance_valid(body):
			continue

		if body.has_method("apply_wind_force"):
			body.apply_wind_force(world_force)
		elif body is RigidBody:
			# Fallback for generic rigid bodies (non-deterministic integration)
			body.add_central_force(world_force)

func _update_visuals(dt: float) -> void:
	# Rotate fan mesh
	var fan = get_node_or_null("Visual/FanMesh")
	if fan:
		var speed = wind_force.length() if is_active else 0.0
		# Rotate around local UP axis (assuming cylinder height is aligned with UP in its local space)
		fan.rotate_object_local(Vector3.UP, speed * dt)

	# Update particles
	var particles = get_node_or_null("Visual/CPUParticles")
	if particles and particles is CPUParticles:
		particles.emitting = is_active
		if is_active:
			# Adjust particle direction to match wind_force (local)
			particles.direction = wind_force.normalized()
			particles.initial_velocity = wind_force.length()
			# Sync particle emission box to zone_extents if available
			particles.emission_box_extents = Vector3(0, zone_extents.y * 0.9, zone_extents.z * 0.9)

func get_snapshot() -> Dictionary:
	return {
		"active": is_active,
		"time": _time_accumulator
	}

func restore_snapshot(data: Dictionary) -> void:
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)

func _apply_snapshot(data: Dictionary) -> void:
	is_active = data.get("active", true)
	_time_accumulator = data.get("time", 0.0)

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	# GUARD: avoid double-stepping during replays/recording when SessionManager is active
	if SessionManager.is_replaying or SessionManager.is_recording:
		return
	step(delta)
