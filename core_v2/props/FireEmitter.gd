extends Spatial
class_name FireEmitter

# FireEmitter.gd - Fire hazard with area damage.
# Adapted from LeakEmitter.gd API but uses GasParticleManager for particles.

export(bool) var auto_start := true
export(int) var burst_count := 3
export(float) var burst_duration := 2.0
export(float) var burst_interval := 8.0
export(float) var fadeout_time := 3.0
export(float) var damage_per_second := 10.0
export(float) var damage_radius := 3.0
export(bool) var continuous := false

onready var _manager: GasParticleManager = get_node_or_null("GasParticleManager")
onready var _damage_area: Area = get_node_or_null("DamageArea")
onready var _damage_shape: CollisionShape = get_node_or_null("DamageArea/CollisionShape")
onready var _audio: AudioStreamPlayer3D = get_node_or_null("FireSound")

var _is_emitting_logic := false
var _time_passed := 0.0
var _emission_weight := 0.0
var _current_bursts := 0
var _burst_active := false

func _init():
	add_to_group("replay_sync")

func _ready():
	if _damage_shape and _damage_shape.shape is SphereShape:
		_damage_shape.shape = _damage_shape.shape.duplicate()
		(_damage_shape.shape as SphereShape).radius = damage_radius

	if auto_start:
		start_emission()

func start_emission():
	_is_emitting_logic = true
	_time_passed = 0.0
	_current_bursts = 0
	_burst_active = false

func stop_emission():
	_is_emitting_logic = false

func toggle():
	if _is_emitting_logic: stop_emission()
	else: start_emission()

func _on_button_activated():
	stop_emission()

func _physics_process(delta: float):
	if Engine.editor_hint: return
	step(delta)

func step(delta: float):
	_update_state(delta)
	if _emission_weight > 0.05:
		_spawn_particles(delta)
		_apply_damage(delta)
	_update_audio()

func _update_state(delta: float):
	if continuous:
		if _is_emitting_logic:
			_emission_weight = min(1.0, _emission_weight + delta * 4.0)
		else:
			_emission_weight = max(0.0, _emission_weight - delta / max(fadeout_time, 0.1))
	else:
		if _is_emitting_logic:
			if burst_count > 0 and _current_bursts >= burst_count:
				_is_emitting_logic = false
				return

			_time_passed += delta
			var cycle = burst_duration + burst_interval
			var t = fmod(_time_passed, cycle)

			if t < burst_duration:
				if not _burst_active:
					_burst_active = true
				_emission_weight = min(1.0, _emission_weight + delta * 5.0)
			else:
				if _burst_active:
					_burst_active = false
					_current_bursts += 1
				_emission_weight = max(0.0, _emission_weight - delta * 2.0)
		else:
			_emission_weight = max(0.0, _emission_weight - delta / max(fadeout_time, 0.1))

func _spawn_particles(delta: float):
	if not _manager: return

	# Roughly 60 particles per second at full strength for fire
	var rate = 60.0 * _emission_weight
	var count = int(rate * delta)
	if randf() < fmod(rate * delta, 1.0):
		count += 1

	for i in range(count):
		var pos = Vector3(rand_range(-0.2, 0.2), 0, rand_range(-0.2, 0.2))
		# Initial velocity
		var vel = Vector3(rand_range(-0.4, 0.4), rand_range(0.5, 1.5), rand_range(-0.4, 0.4)) * (0.8 + 0.2 * _emission_weight)
		_manager.emit_particle(pos, vel, 1.0 + randf() * 0.5, 1.2 + randf() * 0.6)

func _apply_damage(delta: float):
	if not _damage_area or damage_per_second <= 0: return

	var bodies = _damage_area.get_overlapping_bodies()
	if bodies.empty(): return

	var effective_damage = damage_per_second * _emission_weight * delta
	for body in bodies:
		if body.has_method("take_damage"):
			body.take_damage(effective_damage)

func _update_audio():
	if not _audio: return
	if _emission_weight > 0.01:
		if not _audio.playing: _audio.play()
		_audio.unit_db = lerp(-15.0, 10.0, _emission_weight)
	else:
		if _audio.playing: _audio.stop()

func get_snapshot() -> Dictionary:
	return {
		"emitting": _is_emitting_logic,
		"time": _time_passed,
		"weight": _emission_weight,
		"bursts": _current_bursts,
		"b_active": _burst_active
	}

func restore_snapshot(data: Dictionary):
	_is_emitting_logic = data.get("emitting", false)
	_time_passed = data.get("time", 0.0)
	_emission_weight = data.get("weight", 0.0)
	_current_bursts = data.get("bursts", 0)
	_burst_active = data.get("b_active", false)
	_update_audio()
