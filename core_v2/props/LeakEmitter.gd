tool
extends Spatial
class_name LeakEmitter

export(bool) var emitting: bool = true setget set_emitting

export(float) var timeout: float = 0.0
export(float) var interval: float = 0.0
export(float) var interval_random: float = 0.0
export(float) var duration: float = 1.0
export(float) var fadeout_time: float = 0.5

var _time_alive: float = 0.0
var _burst_timer: float = 0.0
var _is_bursting: bool = false

onready var _mesh: MeshInstance = get_node_or_null("SmokeMesh")
onready var _anim: AnimationPlayer = get_node_or_null("SmokeMesh/AnimationPlayer")
onready var _audio: AudioStreamPlayer3D = get_node_or_null("LeakSound")

var _base_scale: Vector3 = Vector3(1, 1, 1)

func _ready():
	if not Engine.editor_hint:
		if _mesh:
			_base_scale = _mesh.scale
			
		if interval > 0.0:
			_burst_timer = max(0.01, interval + rand_range(-interval_random, interval_random))
			_set_visuals_active(false)
			_is_bursting = false
		else:
			_is_bursting = true
			_set_visuals_active(emitting)

func _process(delta):
	if Engine.editor_hint: return
	
	if timeout > 0.0:
		_time_alive += delta
		if _time_alive >= timeout:
			_set_visuals_active(false)
			set_process(false)
			return
			
	if interval > 0.0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			if not _is_bursting:
				# Start burst
				_is_bursting = true
				_set_visuals_active(true)
				if _audio and _audio.stream: _audio.play()
				_burst_timer = duration
				if _mesh: _mesh.scale = _base_scale
			else:
				# End burst
				_is_bursting = false
				_set_visuals_active(false)
				if _audio: _audio.stop()
				_burst_timer = max(0.01, interval + rand_range(-interval_random, interval_random))
		elif _is_bursting and _burst_timer < fadeout_time:
			# Fade out effect over the last 'fadeout_time' seconds by scaling down
			if _mesh:
				var t = max(0.0, _burst_timer / fadeout_time)
				_mesh.scale = _base_scale * t

func _set_visuals_active(active: bool):
	if active and emitting:
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

func set_emitting(value: bool):
	if emitting != value:
		if value and _audio and _audio.stream: _audio.play()
	emitting = value
	if Engine.editor_hint:
		if _anim:
			if emitting: _anim.play("Explode")
			else: _anim.stop()
		if _mesh:
			_mesh.visible = emitting
			_mesh.scale = _base_scale

func activate():
	set_emitting(true)

func deactivate():
	set_emitting(false)

func toggle():
	set_emitting(!emitting)
