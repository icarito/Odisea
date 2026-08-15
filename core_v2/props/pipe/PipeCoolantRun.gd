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
# Velocidad del recorrido de las vetas.
export(float, 0.0, 4.0) var flow_speed := 0.7 setget set_flow_speed
# Intensidad de la emisión: 0 = caño apagado (sistema sin coolant), 1 = régimen normal.
export(float, 0.0, 3.0) var flow_intensity := 1.0 setget set_flow_intensity
# Emisión a intensidad 1.0. La intensidad la escala.
export(float, 0.0, 4.0) var base_emission := 1.4
# Tamaño del patrón de ruido en metros.
export(float, 0.1, 6.0) var noise_scale := 1.6 setget set_noise_scale

var _material: ShaderMaterial = null


func _ready() -> void:
	_apply()


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
	_material.set_shader_param("speed", flow_speed)
	_material.set_shader_param("emission_strength", base_emission * flow_intensity)
	_material.set_shader_param("noise_scale", noise_scale)

	_assign_to_meshes(self)


func _assign_to_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance:
			child.set_surface_material(0, _material)
		if child.get_child_count() > 0:
			_assign_to_meshes(child)
