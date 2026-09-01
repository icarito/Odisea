extends Area
class_name TremorZoneV2
tool

# TremorZoneV2.gd - Localized Tremor Component (FD-288)
# Applies oscillatory physical impulses to the player and RigidBody/PushableBoxV2 objects.
# Reuses CinematicManager.trigger_camera_shake for visual feedback.

export(float) var impulse_strength := 6.0
export(float, 0.05, 5.0) var period := 0.12
export(float, 0.5, 20.0) var frequency := 10.0
export(float) var duration := 1.0
export(int) var seed := 0
export(bool) var affect_player := true
export(bool) var affect_rigid := true
export(float) var camera_amplitude := 0.05
export(bool) var is_active := true setget set_active

var _time_acc: float = 0.0
var _camera_shake_triggered: bool = false

func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("tremor_zone")

func set_active(val: bool) -> void:
	is_active = val
	if is_active:
		_time_acc = 0.0
		_camera_shake_triggered = false

func get_impulse_direction_at_time(t: float) -> Vector3:
	var safe_period := max(0.001, period)
	var cycle_idx := int(floor(t / safe_period))
	return get_impulse_direction(cycle_idx)

func get_impulse_direction(cycle_idx: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	# Deterministic seed calculation per cycle
	rng.seed = int((seed + cycle_idx * 10007) & 0x7fffffff)
	var angle := rng.randf_range(0.0, 2.0 * PI)
	var vert := rng.randf_range(-0.3, 0.3)
	var dir := Vector3(cos(angle), vert, sin(angle))
	if dir.length_squared() > 0.0001:
		return dir.normalized()
	return Vector3.UP

func _trigger_camera_shake() -> void:
	var cm = get_node_or_null("/root/CinematicManager")
	if cm and cm.has_method("trigger_camera_shake"):
		cm.trigger_camera_shake(duration, camera_amplitude, frequency)

func _apply_impulse_to_body(body: Node, impulse: Vector3, dt: float) -> void:
	if not is_instance_valid(body):
		return
	if affect_player and body.has_method("set_external_velocity"):
		var current_ext := Vector3.ZERO
		if "external_velocity" in body:
			current_ext = body.external_velocity
		elif body.has_method("get_external_velocity"):
			current_ext = body.get_external_velocity()
		body.set_external_velocity(current_ext + impulse)
		if body.has_method("set_external_source_is_static"):
			body.set_external_source_is_static(false)
	elif affect_rigid and body is RigidBody and (body as RigidBody).mode != RigidBody.MODE_STATIC:
		(body as RigidBody).apply_central_impulse(impulse * dt)

func step(dt: float) -> void:
	if not is_active:
		return
	if Engine.editor_hint:
		return
	if duration > 0.0 and _time_acc >= duration:
		is_active = false
		return

	if not _camera_shake_triggered and camera_amplitude > 0.0:
		_trigger_camera_shake()
		_camera_shake_triggered = true

	var dir := get_impulse_direction_at_time(_time_acc)
	var impulse := dir * impulse_strength

	var bodies := get_overlapping_bodies()
	for body in bodies:
		_apply_impulse_to_body(body, impulse, dt)

	_time_acc += dt

func _physics_process(delta: float) -> void:
	step(delta)

# --- SNAPSHOT ---

func get_snapshot() -> Dictionary:
	return {
		"is_active": is_active,
		"seed": seed,
		"time_acc": _time_acc,
		"camera_shake_triggered": _camera_shake_triggered
	}

func restore_snapshot(data: Dictionary) -> void:
	seed = int(data.get("seed", seed))
	_time_acc = float(data.get("time_acc", 0.0))
	_camera_shake_triggered = bool(data.get("camera_shake_triggered", false))
	is_active = bool(data.get("is_active", true))
