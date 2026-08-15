extends Spatial

# PlasmaStation.gd — cablea el ciclo de plasma (FD-257) con sus capas visuales.
#
# No tiene estado propio: todo sale de PlasmaConduit.get_warning_progress() y
# get_hazard_intensity(), así que no necesita snapshot — el estado vive en
# PlasmaConduit/PlasmaRoute, que sí cumplen el contrato de replay (AGENTS.md
# §5.3). Este nodo solo traduce esas dos lecturas a lo que se ve:
#   - brillo de la tubería (PipeCoolantRun, tañido ámbar una vez al arrancar)
#   - brillo del nozzle roto (PlasmaExhaust, vía su emission_intensity libre)
#   - la barrera de daño (FireEmitter), solo mientras hay chorro real
#
# El nozzle real del proyecto (PlasmaExhaust.gd) ya anima pulse_factor y
# plasma_color por su cuenta (ciclo de color propio, estados IDLE/FLARE/SURGE
# atados a una env var). No lo tocamos: emission_intensity es el único shader
# param que ese script nunca escribe, así que es seguro pilotearlo desde acá
# sin pisarle la animación.

const PIPE_ALBEDO_AMBER := Color(0.85, 0.55, 0.12, 1.0)
const PIPE_EMISSION_AMBER := Color(0.4, 0.22, 0.02, 1.0)

const PIPE_FLOW_HEALTHY := 1.0
const PIPE_FLOW_WARNING := 2.0
const PIPE_FLOW_VENTING := 3.0
const PIPE_SPEED_HEALTHY := 0.7
const PIPE_SPEED_WARNING := 1.6

const NOZZLE_EMISSION_HEALTHY := 1.5
const NOZZLE_EMISSION_WARNING := 4.0
const NOZZLE_EMISSION_VENTING := 8.0

const HAZARD_THRESHOLD := 0.01

onready var _conduit: Node = get_node_or_null("PlasmaConduit")
onready var _pipes: Node = get_node_or_null("Pipes")
onready var _nozzle_mesh: MeshInstance = get_node_or_null("PlasmaExhaust/PlasmaMesh")
onready var _barrier: Node = get_node_or_null("FireEmitter")


func _ready() -> void:
	_tint_pipes_amber()
	_apply(0.0, 0.0)


func _physics_process(_delta: float) -> void:
	if _conduit:
		_apply(_conduit.get_warning_progress(), _conduit.get_hazard_intensity())


func _apply(warning: float, hazard: float) -> void:
	# Tubería: de régimen sano a sobrecalentada durante el aviso, y a brillo
	# máximo mientras el chorro está afuera. Depende solo de (warning, hazard),
	# así que es continua a través de las cuatro fases del conduit sin
	# necesitar guardar en qué fase estamos.
	var pipe_warm: float = lerp(PIPE_FLOW_HEALTHY, PIPE_FLOW_WARNING, warning)
	var pipe_target: float = lerp(pipe_warm, PIPE_FLOW_VENTING, hazard)
	if _pipes:
		if _pipes.has_method("set_flow_intensity"):
			_pipes.set_flow_intensity(pipe_target)
		if _pipes.has_method("set_flow_speed"):
			_pipes.set_flow_speed(lerp(PIPE_SPEED_HEALTHY, PIPE_SPEED_WARNING, warning))

	var nozzle_warm: float = lerp(NOZZLE_EMISSION_HEALTHY, NOZZLE_EMISSION_WARNING, warning)
	var nozzle_target: float = lerp(nozzle_warm, NOZZLE_EMISSION_VENTING, hazard)
	if _nozzle_mesh and _nozzle_mesh.material_override:
		_nozzle_mesh.material_override.set_shader_param("emission_intensity", nozzle_target)

	# Barrera de daño: solo con el chorro afuera (hazard_intensity). Durante el
	# aviso PlasmaConduit ya deja hazard_intensity en 0 — la tubería solo
	# brilla, todavía no corta el paso.
	if _barrier and _barrier.has_method("set_active"):
		_barrier.set_active(hazard > HAZARD_THRESHOLD)


func _tint_pipes_amber() -> void:
	# PipeCoolantRun no expone color propio (siempre carga PipeCoolant.tres,
	# cian). El material que arma es un ShaderMaterial duplicado UNA vez y
	# reutilizado en cada _apply() posterior — nunca se vuelve a cargar desde
	# disco — así que retocar base_color/flow_color acá, una sola vez, alcanza
	# y no se lo pisa el propio flow_intensity que actualizamos cada frame
	# (ese solo toca emission_strength/flow_phase/etc).
	if not _pipes:
		return
	var mesh: MeshInstance = _pipes.get_node_or_null("PipeLeft/MeshInstance")
	if not mesh:
		return
	var mat: Material = mesh.get_surface_material(0)
	if mat is ShaderMaterial:
		mat.set_shader_param("base_color", PIPE_ALBEDO_AMBER)
		mat.set_shader_param("flow_color", PIPE_EMISSION_AMBER)
