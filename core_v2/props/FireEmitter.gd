tool
extends Area
class_name FireEmitter

signal damage_tick(damage)
signal extinguished()

export(bool) var is_active: bool = true setget set_active
export(float) var damage_per_tick: float = 10.0
export(float) var tick_interval: float = 0.5

var _tick_timer: float = 0.0
var _player_body: Node = null

onready var _particles: Particles = get_node_or_null("Particles")
onready var _collision_shape: CollisionShape = get_node_or_null("CollisionShape")

func _ready():
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

	if not Engine.editor_hint:
		_set_visuals_active(is_active)
		if _collision_shape:
			_collision_shape.disabled = not is_active
	else:
		_set_visuals_active(is_active)

func _process(delta: float):
	if Engine.editor_hint:
		return

	if is_active and _player_body:
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer = 0.0
			emit_signal("damage_tick", damage_per_tick)

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		_player_body = body
		# Optional: apply first tick immediately?
		# Prompt says "cada 0.5s mientras esté dentro".
		# I'll reset timer to 0 to wait 0.5s for first tick.
		_tick_timer = 0.0

func _on_body_exited(body: Node):
	if body == _player_body:
		_player_body = null

func set_active(value: bool):
	is_active = value
	_set_visuals_active(is_active)
	if _collision_shape:
		_collision_shape.set_deferred("disabled", not is_active)
	if not is_active:
		_player_body = null

func _set_visuals_active(active: bool):
	if _particles:
		_particles.emitting = active

func extinguish():
	set_active(false)
	emit_signal("extinguished()")

func interact():
	toggle()

func activate():
	set_active(true)

func deactivate():
	set_active(false)

func toggle():
	set_active(!is_active)
