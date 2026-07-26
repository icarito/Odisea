tool
extends Area
class_name FireEmitter

signal damage_tick(damage)
signal extinguished()

export(bool) var is_active: bool = true setget set_active
export(float) var damage_per_tick: float = 10.0
export(float) var tick_interval: float = 0.5
export(float) var emission_radius: float = 0.5
export(int) var particles_per_second: float = 30
export(float) var emission_height: float = 1.5

var _tick_timer: float = 0.0
var _spawn_timer: float = 0.0
var _player_body: Node = null

onready var _manager: GasParticleManager = get_node_or_null("GasParticleManager")
onready var _collision_shape: CollisionShape = get_node_or_null("CollisionShape")

func _ready():
	add_to_group("replay_sync")
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

	_set_visuals_active(is_active)
	if _collision_shape:
		_collision_shape.disabled = not is_active

func _process(delta: float):
	if Engine.editor_hint:
		return

	if is_active and _manager:
		_spawn_timer += delta
		var spawn_interval := 1.0 / max(particles_per_second, 1.0)
		while _spawn_timer >= spawn_interval:
			_spawn_timer -= spawn_interval
			_spawn_flame_particle()

	if is_active and _player_body:
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer = 0.0
			emit_signal("damage_tick", damage_per_tick)

func _spawn_flame_particle() -> void:
	var offset := Vector3(
		(randf() - 0.5) * emission_radius,
		emission_height,
		(randf() - 0.5) * emission_radius
	)
	var index := _manager.emit_particle(offset)
	_manager.set_particle_combustion(index, true)

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		_player_body = body
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
	if not active and _manager:
		_manager.clear_all()

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

# --- SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"is_active": is_active,
		"tick_timer": _tick_timer,
		"spawn_timer": _spawn_timer,
		"manager": _manager.get_snapshot() if _manager else {}
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("is_active", true)
	_tick_timer = data.get("tick_timer", 0.0)
	_spawn_timer = data.get("spawn_timer", 0.0)

	_set_visuals_active(is_active)
	if _collision_shape:
		_collision_shape.disabled = not is_active
	if _manager and data.has("manager"):
		_manager.restore_snapshot(data["manager"])
