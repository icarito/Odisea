extends "res://core_v2/visual/plasma_exhaust/PlasmaExhaustBase.gd"

# Performance Cost: Medium (CPUParticles — GLES2 compatible; GPU Particles do not render under GLES2)
# LOD Support: Yes (Particles visible distance / visibility AABB)

# --- Emission ---
export(int) var amount := 70 setget set_amount
export(float) var lifetime := 2.0 setget set_lifetime
export(float) var lifetime_randomness := 0.4 setget set_lifetime_randomness
export(float) var initial_velocity := 4.0 setget set_initial_velocity
export(float) var velocity_random := 0.6 setget set_velocity_random
export(float) var spread := 20.0 setget set_spread
export(float) var particle_scale := 0.8 setget set_particle_scale
export(float) var scale_random := 0.5 setget set_scale_random

# --- Flipbook / look ---
export(Texture) var flipbook_tex setget set_flipbook_tex
export(Vector2) var flipbook_grid := Vector2(8, 8) setget set_flipbook_grid
export(Color) var core_color := Color(0.28, 0.42, 0.7, 1.0) setget set_core_color
# 1.0 = full additive punch, lower = softer/dimmer so particles blend instead
# of looking like hard burned-in quads.
export(float, 0.0, 1.0) var softness := 0.6 setget set_softness

onready var particles = $Particles

func _ready():
	# Default flipbook if none assigned in the editor. Smoke reads as a vaporous
	# plasma plume once tinted; swap to any 8x8 sheet (fireballs/clouds) from the
	# Inspector via flipbook_tex.
	if flipbook_tex == null:
		flipbook_tex = load("res://assets/flipbook_particles/assets/smokes/smoke_01/textures/smoke_01.tga")
	_update_particles()
	_apply_flipbook()
	_apply_color()

func set_amount(val: int):
	amount = val
	if is_inside_tree() and particles:
		particles.amount = amount

func set_lifetime(val: float):
	lifetime = val
	if is_inside_tree() and particles:
		particles.lifetime = lifetime

func set_lifetime_randomness(val: float):
	lifetime_randomness = val
	if is_inside_tree() and particles:
		particles.lifetime_randomness = lifetime_randomness

func set_initial_velocity(val: float):
	initial_velocity = val
	_update_particles()

func set_velocity_random(val: float):
	velocity_random = val
	_update_particles()

func set_spread(val: float):
	spread = val
	_update_particles()

func set_particle_scale(val: float):
	particle_scale = val
	_update_particles()

func set_scale_random(val: float):
	scale_random = val
	_update_particles()

func set_flipbook_tex(val: Texture):
	flipbook_tex = val
	_apply_flipbook()

func set_flipbook_grid(val: Vector2):
	flipbook_grid = val
	_apply_flipbook()

func set_core_color(val: Color):
	core_color = val
	_apply_color()

func set_softness(val: float):
	softness = clamp(val, 0.0, 1.0)
	_apply_color()

func _update_active_state():
	. _update_active_state()
	if particles:
		particles.emitting = is_active

func _update_intensity():
	if particles:
		# We can modulate speed or scale by intensity
		particles.speed_scale = intensity

func _update_color_phase():
	# color_phase blends the core tint toward white-hot.
	_apply_color()

func _update_particles():
	if not particles: return
	# CPUParticles exposes velocity/spread directly (no process_material).
	particles.initial_velocity = initial_velocity
	particles.initial_velocity_random = velocity_random
	particles.spread = spread
	particles.lifetime_randomness = lifetime_randomness
	particles.scale_amount = particle_scale
	particles.scale_amount_random = scale_random

func _apply_flipbook():
	if not particles: return
	var mesh = particles.mesh
	if mesh == null: return
	var mat = mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else mesh.material
	if mat == null:
		mat = mesh.material
	if mat == null: return
	if flipbook_tex:
		mat.albedo_texture = flipbook_tex
	mat.params_use_alpha_scissor = false
	mat.particles_anim_h_frames = int(flipbook_grid.x)
	mat.particles_anim_v_frames = int(flipbook_grid.y)

func _apply_color():
	if not particles: return
	# Blend the core color toward white-hot as color_phase rises, then drive it
	# through the CPUParticles color so it tints the (white) flipbook uniformly.
	var c = core_color.linear_interpolate(Color(1, 1, 1, 1), color_phase)
	c.a = softness
	particles.color = c
