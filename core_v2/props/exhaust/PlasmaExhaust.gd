extends Spatial

# PlasmaExhaust.gd
# Controls the visual states and color cycling for the reactor nozzle plasma.

enum State { IDLE, FLARE, SURGE }

var current_state = State.IDLE
var state_timer = 0.0
var flare_timer = 0.0
var color_timer = 0.0
var flow_phase = 0.0

# Colors for the cycle
var color_cycle = [
	Color(0.0, 0.0, 0.5), # Deep Blue
	Color(0.5, 0.0, 0.5), # Violet
	Color(0.5, 0.0, 0.0), # Crimson
	Color(0.8, 0.6, 0.0), # Gold
	Color(0.0, 0.0, 0.5)  # Back to Deep Blue
]
var color_cycle_duration = 8.0

onready var mesh = $PlasmaMesh
onready var particles = $PlasmaParticles/Particles

func _ready():
	# Duplicate materials to ensure instance uniqueness
	if mesh and mesh.material_override:
		mesh.material_override = mesh.material_override.duplicate()

	if particles:
		particles.process_material = particles.process_material.duplicate()

	# Initial state
	_set_state(State.IDLE)

func _process(delta):
	flow_phase += delta
	if mesh and mesh.material_override:
		mesh.material_override.set_shader_param("flow_phase", flow_phase)
	_update_color_cycle(delta)
	_update_state_machine(delta)

func _update_color_cycle(delta):
	color_timer += delta
	if color_timer > color_cycle_duration:
		color_timer -= color_cycle_duration

	var progress = color_timer / color_cycle_duration
	var num_colors = color_cycle.size() - 1
	var idx = int(progress * num_colors)
	var next_idx = idx + 1
	var weight = (progress * num_colors) - idx

	var current_color = color_cycle[idx].linear_interpolate(color_cycle[next_idx], weight)

	if mesh.material_override:
		mesh.material_override.set_shader_param("plasma_color", current_color)

	if particles:
		var mat = particles.process_material as ParticlesMaterial
		if mat:
			mat.color = current_color

func _update_state_machine(delta):
	state_timer += delta
	flare_timer += delta

	# Check for Surge state (mocking Odisea IA active check)
	var odisea_active = _is_odisea_active()
	if odisea_active and current_state != State.SURGE:
		_set_state(State.SURGE)
	elif not odisea_active and current_state == State.SURGE:
		_set_state(State.IDLE)

	match current_state:
		State.IDLE:
			# Pulsing logic
			var pulse = 1.0 + 0.2 * sin(state_timer * PI) # 2s period
			if mesh.material_override:
				mesh.material_override.set_shader_param("pulse_factor", pulse)

			# Trigger Flare every 15s
			if flare_timer > 15.0:
				_set_state(State.FLARE)

		State.FLARE:
			var flare_progress = state_timer / 1.0 # 1s duration
			var pulse = 1.0 + 1.5 * sin(flare_progress * PI)
			if mesh.material_override:
				mesh.material_override.set_shader_param("pulse_factor", pulse)

			if state_timer > 1.0:
				_set_state(State.IDLE)
				flare_timer = 0.0

		State.SURGE:
			# Faster and brighter pulse
			var pulse = 1.5 + 0.5 * sin(state_timer * PI * 2.0) # 1s period, brighter
			if mesh.material_override:
				mesh.material_override.set_shader_param("pulse_factor", pulse)

func _set_state(new_state):
	current_state = new_state
	state_timer = 0.0

func _is_odisea_active():
	# In this repo, Odisea refers to the AI.
	# Integration with A.N.N.A is the primary indicator of AI activity.
	return OS.get_environment("ANNA_ENABLED") == "1"
