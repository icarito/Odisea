tool
extends Spatial
class_name PipeCoolantRun

# PipeCoolantRun.gd — gobierna el flujo visible de una corrida de tubería.
#
# Se cuelga del nodo que agrupa los tramos (PipeSection, PipeCorner, PipeTee) y aplica
# el material de coolant a todos sus MeshInstance, con una dirección, una velocidad y
# una intensidad comunes. Así una sala puede decir "por acá va el refrigerante, y va
# hacia allá" sin tocar cada tramo a mano.
#
# La intensidad es la palanca de gameplay: un sistema sano corre parejo; una fuga la
# hace caer. Manejarla en runtime con set_flow_intensity().

const COOLANT_MATERIAL := "res://core_v2/props/pipe/PipeCoolant.tres"

# Dirección del flujo, en coordenadas de mundo. El shader muestrea ruido en mundo, así
# que este vector es el que hace que el refrigerante "corra" hacia un lado y no al otro.
export(Vector3) var flow_dir := Vector3(1, 0, 0) setget set_flow_dir
# Velocidad del recorrido de las vetas. Es un objetivo, no un salto: al cambiarla la
# velocidad real la persigue con una rampa, así cortar el caudal frena el patrón en vez
# de congelarlo de golpe.
export(float, 0.0, 4.0) var flow_speed := 0.7 setget set_flow_speed
# Segundos que tarda la velocidad real en alcanzar el objetivo (arrancar o frenar).
export(float, 0.05, 6.0) var speed_ramp := 1.6
# Intensidad de la emisión: 0 = caño apagado (sistema sin coolant), 1 = régimen normal.
export(float, 0.0, 3.0) var flow_intensity := 1.0 setget set_flow_intensity
# Emisión a intensidad 1.0. La intensidad la escala.
export(float, 0.0, 4.0) var base_emission := 1.4
# Tamaño del patrón de ruido en metros.
export(float, 0.1, 6.0) var noise_scale := 1.6 setget set_noise_scale
# Transparencia del caño: 1.0 opaco. Un poco por debajo deja intuir el volumen interno.
export(float, 0.2, 1.0) var pipe_alpha := 0.88 setget set_pipe_alpha

var _material: ShaderMaterial = null
var _phase: float = 0.0
var _current_speed: float = 0.0


func _ready() -> void:
	_current_speed = flow_speed
	_apply()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	# La fase se acumula acá y se manda al shader; el shader no multiplica TIME por la
	# velocidad. Esa es la diferencia entre frenar y congelar: la fase sigue siendo
	# continua mientras la velocidad baja.
	_current_speed = _approach(_current_speed, flow_speed, delta)
	if abs(_current_speed) < 0.0001 and abs(flow_speed) < 0.0001:
		return
	_phase += delta * _current_speed
	if _material:
		_material.set_shader_param("flow_phase", _phase)


func _approach(current: float, target: float, delta: float) -> float:
	if speed_ramp <= 0.0:
		return target
	var step: float = delta / speed_ramp * max(1.0, abs(target - current))
	if current < target:
		return min(current + step, target)
	return max(current - step, target)


func set_flow_dir(v: Vector3) -> void:
	flow_dir = v
	_apply()


func set_flow_speed(v: float) -> void:
	flow_speed = v
	_apply()


func set_flow_intensity(v: float) -> void:
	flow_intensity = clamp(v, 0.0, 3.0)
	_apply()


func set_noise_scale(v: float) -> void:
	noise_scale = v
	_apply()


func set_pipe_alpha(v: float) -> void:
	pipe_alpha = v
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	if _material == null:
		var base = load(COOLANT_MATERIAL)
		if base == null:
			return
		# Duplicado: si no, cada corrida de tubería del nivel pisaría la dirección
		# de todas las demás, porque el .tres es un recurso compartido.
		_material = base.duplicate()

	var dir: Vector3 = flow_dir
	if dir.length() > 0.001:
		dir = dir.normalized()
	_material.set_shader_param("flow_dir", dir)
	_material.set_shader_param("flow_phase", _phase)
	_material.set_shader_param("pipe_alpha", pipe_alpha)
	_material.set_shader_param("emission_strength", base_emission * flow_intensity)
	_material.set_shader_param("noise_scale", noise_scale)

	_assign_to_meshes(self)


func _assign_to_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance:
			child.set_surface_material(0, _material)
		if child.get_child_count() > 0:
			_assign_to_meshes(child)
