tool
extends Spatial
class_name LeakEmitter

export(bool) var is_active: bool = true setget set_active

export(float) var timeout: float = 0.0
export(float) var interval: float = 0.0
export(float) var interval_random: float = 0.0
export(float) var duration: float = 1.0
export(float) var fadeout_time: float = 5.0
export(bool) var wait_for_runtime_startup: bool = true
export(int, 0, 1200) var startup_wait_max_frames: int = 720

var _time_alive: float = 0.0
var _burst_timer: float = 0.0
var _is_bursting: bool = false
var _timeout_fade_active: bool = false
var _timeout_fade_timer: float = 0.0
var _timeout_fade_start_scale: Vector3 = Vector3(1, 1, 1)
var _startup_gate_pending: bool = false

onready var _mesh: MeshInstance = get_node_or_null("SmokeMesh")
onready var _anim: AnimationPlayer = get_node_or_null("SmokeMesh/AnimationPlayer")
onready var _audio: AudioStreamPlayer3D = get_node_or_null("LeakSound")

var _base_scale: Vector3 = Vector3(1, 1, 1)

func _ready():
	if Engine.editor_hint:
		return
	if _mesh:
		_base_scale = _mesh.scale

	_startup_gate_pending = _should_wait_for_runtime_startup()
	if _is_constant_mode():
		_is_bursting = true
		_set_visuals_active(is_active and not _startup_gate_pending)
		if not _startup_gate_pending and is_active and _audio and not _audio.playing:
			_audio.play()
	else:
		_burst_timer = max(0.01, interval + rand_range(-interval_random, interval_random))
		_set_visuals_active(false)
		_is_bursting = false

	if _startup_gate_pending:
		set_process(false)
		call_deferred("_resume_after_startup_gate")
	elif _is_constant_mode() and timeout <= 0.0:
		set_process(false)
	else:
		set_process(true)

func _should_wait_for_runtime_startup() -> bool:
	if not wait_for_runtime_startup:
		return false
	var session = get_node_or_null("/root/SessionManager")
	if session == null:
		return false
	if session.has_method("is_startup_gate_open"):
		return not bool(session.is_startup_gate_open())
	return true

func _resume_after_startup_gate() -> void:
	var session = get_node_or_null("/root/SessionManager")
	if session and session.has_method("wait_until_startup_gate_open"):
		var wait_state = session.wait_until_startup_gate_open(startup_wait_max_frames)
		if wait_state is GDScriptFunctionState:
			yield(wait_state, "completed")
	_startup_gate_pending = false
	if _is_constant_mode():
		_set_visuals_active(is_active)
		if is_active and _audio and not _audio.playing:
			_audio.play()
		if timeout <= 0.0:
			return
	set_process(true)

func _process(delta):
	if Engine.editor_hint: return
	
	if timeout > 0.0 and not _timeout_fade_active:
		_time_alive += delta
		if _time_alive >= timeout:
			_start_timeout_fade_out()

	if _timeout_fade_active:
		if _mesh:
			if fadeout_time <= 0.0:
				_mesh.scale = Vector3.ZERO
				_set_visuals_active(false)
				set_process(false)
				return
			_timeout_fade_timer = max(0.0, _timeout_fade_timer - delta)
			var t = _timeout_fade_timer / fadeout_time
			_mesh.scale = _timeout_fade_start_scale * t
			if _timeout_fade_timer <= 0.0:
				_set_visuals_active(false)
				set_process(false)
		else:
			_set_visuals_active(false)
			set_process(false)
		return

	# Continuous mode: never run burst toggles ("chorros"), just stay active.
	if _is_constant_mode():
		_is_bursting = true
		_set_visuals_active(is_active)
		if is_active and _audio and not _audio.playing:
			_audio.play()
		elif not is_active and _audio and _audio.playing:
			_audio.stop()
		return

	if interval > 0.0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			if not _is_bursting:
				# Start burst
				_is_bursting = true
				_set_visuals_active(true)
				if is_active and _audio and not _audio.playing:
					_audio.play()
				_burst_timer = duration
				if _mesh: _mesh.scale = _base_scale
			else:
				# End burst
				_is_bursting = false
				_set_visuals_active(false)
				if _audio and _audio.playing:
					_audio.stop()
				_burst_timer = max(0.01, interval + rand_range(-interval_random, interval_random))
		elif _is_bursting and _burst_timer < fadeout_time:
			# Fade out effect over the last 'fadeout_time' seconds by scaling down
			if _mesh:
				var t = max(0.0, _burst_timer / fadeout_time)
				_mesh.scale = _base_scale * t

func _is_constant_mode() -> bool:
	return interval <= 0.0 or duration <= 0.0

func _start_timeout_fade_out() -> void:
	_timeout_fade_active = true
	_timeout_fade_timer = max(0.0, fadeout_time)
	_is_bursting = false

	if _audio and _audio.playing:
		_audio.stop()

	if _mesh:
		_timeout_fade_start_scale = _mesh.scale
		if _timeout_fade_start_scale.length_squared() <= 0.000001:
			_timeout_fade_start_scale = _base_scale
		_mesh.visible = true

	if _anim and _anim.is_playing():
		_anim.stop()

func _set_visuals_active(active: bool):
	if active and is_active:
		if _anim and not _anim.is_playing():
			_anim.play("Explode")
		if _mesh:
			_mesh.visible = true
			_mesh.scale = _base_scale
	else:
		if _anim:
			_anim.stop()
		if _mesh:
			_mesh.visible = false

func set_active(value: bool, immediate: bool = false):
	if is_active != value and not _startup_gate_pending:
		if value and _is_bursting and _audio and not _audio.playing:
			_audio.play()
		elif not value and _audio and _audio.playing:
			_audio.stop()
			
	is_active = value
	
	if immediate:
		_time_alive = 0.0
		_burst_timer = 0.0
		if not _is_bursting and not _is_constant_mode():
			_burst_timer = max(0.01, interval + rand_range(-interval_random, interval_random))

	if not Engine.editor_hint and _is_constant_mode() and not _timeout_fade_active:
		if timeout > 0.0 and not is_processing():
			set_process(true)
		_set_visuals_active(is_active and not _startup_gate_pending)
	if Engine.editor_hint:
		if _anim:
			if is_active: _anim.play("Explode")
			else: _anim.stop()
		if _mesh:
			_mesh.visible = is_active
			_mesh.scale = _base_scale

func interact():
	toggle()

func activate():
	set_active(true)

func deactivate():
	set_active(false)

func toggle():
	set_active(!is_active)
