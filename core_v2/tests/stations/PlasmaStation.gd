extends Spatial

# PlasmaStation.gd — cablea el ciclo de plasma (FD-257) con sus capas visuales.
#
# No tiene estado propio: todo sale de PlasmaConduit.get_warning_progress() y
# get_hazard_intensity(), así que no necesita snapshot — el estado vive en
# PlasmaConduit/PlasmaRoute, que sí cumplen el contrato de replay (AGENTS.md
# §5.3). Este nodo solo traduce esas dos lecturas a lo que se ve:
#   - brillo de la tubería (PipeCoolantRun, plasma cian/violeta una vez al arrancar)
#   - fuga de plasma (CPUParticles + flipbook de PlasmaExhaust hacia +Y)
#   - la barrera de daño (FireEmitter), solo mientras hay chorro real
#
# La fuga es partícula decorativa y el FireEmitter invisible mantiene el daño
# determinista. Se reutiliza el shader de PlasmaExhaust, pero no su malla cono:
# el núcleo va dentro del tubo y el escape nace como partículas desde la rotura.

const PIPE_ALBEDO_PLASMA := Color(0.14, 0.09, 0.04, 1.0)
const PIPE_EMISSION_PLASMA := Color(1.0, 0.62, 0.16, 1.0)

const PIPE_FLOW_HEALTHY := 1.0
const PIPE_FLOW_WARNING := 2.0
const PIPE_FLOW_VENTING := 3.0
const PIPE_SPEED_HEALTHY := 0.7
const PIPE_SPEED_WARNING := 1.6
const CORE_SPEED_HEALTHY := 1.0
const CORE_SPEED_WARNING := 1.8
const REROUTED_STATE := 3

const HAZARD_THRESHOLD := 0.01

onready var _conduit: Node = get_node_or_null("PlasmaConduit")
onready var _pipes: Node = get_node_or_null("Pipes")
onready var _leak_particles: CPUParticles = get_node_or_null("PlasmaLeakParticles")
onready var _core: MeshInstance = get_node_or_null("PlasmaCoreLeft")
onready var _cores := [get_node_or_null("PlasmaCoreLeft"), get_node_or_null("PlasmaCoreRight"), get_node_or_null("PlasmaCoreSafe")]

# Ciclo de color del núcleo, tomado tal cual de PlasmaExhaust.gd: el plasma del proyecto
# late entre azul profundo, violeta, carmesí y oro. Un color fijo con un flipbook en loop
# se lee como un salto que se repite; el ciclo lo vuelve continuo.
const CORE_COLOR_CYCLE := [
	Color(0.0, 0.0, 0.5),
	Color(0.5, 0.0, 0.5),
	Color(0.5, 0.0, 0.0),
	Color(0.8, 0.6, 0.0),
	Color(0.0, 0.0, 0.5)
]
const CORE_COLOR_CYCLE_DURATION := 8.0
var _core_color_timer := 0.0
onready var _leak_light: OmniLight = get_node_or_null("LeakLight")
onready var _barrier: Node = get_node_or_null("FireEmitter")

var _core_material: ShaderMaterial = null
var _was_leaking := false
var _core_phase := 0.0
var _core_speed := CORE_SPEED_HEALTHY
var _core_target_speed := CORE_SPEED_HEALTHY

func _ready() -> void:
	_tint_pipes_plasma()
	if _core:
		_core_material = _core.get_surface_material(0) as ShaderMaterial
	_apply(0.0, 0.0)


func _cycle_core_color(delta: float) -> void:
	_core_color_timer = fmod(_core_color_timer + delta, CORE_COLOR_CYCLE_DURATION)
	var progress: float = _core_color_timer / CORE_COLOR_CYCLE_DURATION
	var steps: int = CORE_COLOR_CYCLE.size() - 1
	var idx: int = int(progress * steps)
	var next_idx: int = min(idx + 1, steps)
	var weight: float = (progress * steps) - idx
	var color: Color = CORE_COLOR_CYCLE[idx].linear_interpolate(CORE_COLOR_CYCLE[next_idx], weight)
	for core in _cores:
		if core == null:
			continue
		var mat = core.get_surface_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_param("plasma_color", color)


func _physics_process(delta: float) -> void:
	_cycle_core_color(delta)
	if _conduit:
		_apply(_conduit.get_warning_progress(), _conduit.get_hazard_intensity())
	_core_speed = lerp(_core_speed, _core_target_speed, min(delta * 12.0, 1.0))
	_core_phase += delta * _core_speed
	if _core_material:
		_core_material.set_shader_param("flow_phase", _core_phase)


func _apply(warning: float, hazard: float) -> void:
	# Tubería: de régimen sano a sobrecalentada durante el aviso, y a brillo
	# máximo mientras el chorro está afuera. Depende solo de (warning, hazard),
	# así que es continua a través de las cuatro fases del conduit sin
	# necesitar guardar en qué fase estamos.
	var pipe_warm: float = lerp(PIPE_FLOW_HEALTHY, PIPE_FLOW_WARNING, warning)
	var pipe_target: float = lerp(pipe_warm, PIPE_FLOW_VENTING, hazard)
	var plasma_heat: float = max(warning, hazard)
	var conduit_state: int = _conduit.get_state() if _conduit else 0
	var flow_stopped: bool = conduit_state == REROUTED_STATE
	_core_target_speed = 0.0 if flow_stopped else lerp(CORE_SPEED_HEALTHY, CORE_SPEED_WARNING, warning)
	if _pipes:
		if _pipes.has_method("set_flow_intensity"):
			_pipes.set_flow_intensity(pipe_target)
		if _pipes.has_method("set_flow_speed"):
			_pipes.set_flow_speed(0.0 if flow_stopped else lerp(PIPE_SPEED_HEALTHY, PIPE_SPEED_WARNING, warning))
	if _core_material:
		_core_material.set_shader_param("emission_intensity", lerp(2.0, 4.8, plasma_heat))
		_core_material.set_shader_param("pulse_factor", lerp(1.0, 1.45, plasma_heat))

	# Desde que el conduit abandona NOMINAL hay presión en la junta rota: un
	# escape tenue empieza durante el aviso y escala con plasma_heat. Esto hace
	# legible el daño antes de que FireEmitter habilite la barrera peligrosa.
	var conduit_active: bool = _conduit and _conduit.get_state() != 0
	var leak_active: bool = conduit_active or hazard > HAZARD_THRESHOLD
	if _leak_particles:
		# Un escape ascendente avisa antes de que salga el chorro peligroso;
		# FireEmitter sigue siendo la única capa que causa daño real.
		if leak_active and not _was_leaking:
			_leak_particles.restart()
		_leak_particles.emitting = leak_active
	_was_leaking = leak_active
	if _leak_light:
		_leak_light.visible = leak_active
		_leak_light.light_energy = lerp(1.2, 5.0, plasma_heat)

	# Barrera de daño: solo con el chorro afuera (hazard_intensity). Durante el
	# aviso PlasmaConduit ya deja hazard_intensity en 0 — la tubería solo
	# brilla, todavía no corta el paso.
	if _barrier and _barrier.has_method("set_active"):
		_barrier.set_active(hazard > HAZARD_THRESHOLD)


func _tint_pipes_plasma() -> void:
	# PipeCoolantRun recibe PipePlasma.tres en esta estación. El material que
	# arma es un ShaderMaterial duplicado UNA vez y
	# reutilizado en cada _apply() posterior — nunca se vuelve a cargar desde
	# disco — así que retocar base_color/flow_color acá, una sola vez, alcanza
	# y no se lo pisa el propio flow_intensity que actualizamos cada frame
	# (ese solo toca emission_strength/flow_phase/etc).
	if not _pipes:
		return
	var mesh: MeshInstance = _pipes.get_node_or_null("MainA/MeshInstance")
	if not mesh:
		return
	var mat: Material = mesh.get_surface_material(0)
	if mat is ShaderMaterial:
		mat.set_shader_param("base_color", PIPE_ALBEDO_PLASMA)
		mat.set_shader_param("flow_color", PIPE_EMISSION_PLASMA)
		mat.set_shader_param("flow_contrast", 0.22)
		mat.set_shader_param("metallic_amount", 0.65)
		mat.set_shader_param("roughness_amount", 0.28)
		_pipes.base_emission = 1.6
		_pipes.set_noise_scale(3.2)
		# Opaco: el núcleo tiene que verse SOLO por la rotura. Con el caño translúcido,
		# el ámbar del núcleo atravesaba la pared y toda la cañería se leía magenta.
		_pipes.set_pipe_alpha(1.0)


func interact() -> void:
	# Puente exclusivo para el harness de props: el jugador apunta a cada
	# PipeValve por separado, pero PropStage opera la raíz de la estación.
	for valve_path in ["ValveA", "ValveB"]:
		var valve: Node = get_node_or_null(valve_path)
		if valve and valve.has_method("interact"):
			valve.interact()
