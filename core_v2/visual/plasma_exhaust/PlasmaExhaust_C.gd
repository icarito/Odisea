extends "res://core_v2/visual/plasma_exhaust/PlasmaExhaustBase.gd"

# Performance Cost: High (GPU Particles)
# LOD Support: Yes (Particles visible distance / visibility AABB)

export(int) var amount := 200 setget set_amount
export(float) var lifetime := 2.0 setget set_lifetime
export(float) var initial_velocity := 5.0 setget set_initial_velocity
export(float) var spread := 15.0 setget set_spread

onready var particles = $Particles

func _ready():
	_update_particles()

func set_amount(val: int):
	amount = val
	if is_inside_tree() and particles:
		particles.amount = amount

func set_lifetime(val: float):
	lifetime = val
	if is_inside_tree() and particles:
		particles.lifetime = lifetime

func set_initial_velocity(val: float):
	initial_velocity = val
	_update_particles()

func set_spread(val: float):
	spread = val
	_update_particles()

func _update_active_state():
	. _update_active_state()
	if particles:
		particles.emitting = is_active

func _update_intensity():
	if particles:
		# We can modulate speed or scale by intensity
		particles.speed_scale = intensity

func _update_color_phase():
	# Color phase could swap gradients or modulate color
	pass

func _update_particles():
	if not particles: return
	var mat = particles.process_material
	if mat is ParticlesMaterial:
		mat.initial_velocity = initial_velocity
		mat.spread = spread
