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
# Nodos en este grupo conservan su material propio aunque cuelguen de la corrida: los
# herrajes (collares, bridas) son metal y no deben recibir el material de fluido.
const SKIP_GROUP := "no_flow_material"

# La intensidad es la palanca de gameplay: un sistema sano corre parejo; una fuga la
# hace caer. Manejarla en runtime con set_flow_intensity().

const DEFAULT_FLOW_MATERIAL := "res://core_v2/props/pipe/PipeCoolant.tres"

# Material de flujo por corrida. Mantiene coolant como default; plasma puede reutilizar
# el mismo controlador con su shader de bandas, sin teñir el shader de criocoolant.
export(String, FILE, "*.tres") var flow_material_path: String = DEFAULT_FLOW_MATERIAL

# Dirección del flujo, en coordenadas de mundo. El shader muestrea ruido en mundo, así
# que este vector es el que hace que el refrigerante "corra" hacia un lado y no al otro.
export(Vector3) var flow_dir := Vector3(1, 0, 0) setget set_flow_dir
# _apply() apaga use_local_axis por defecto (ver más abajo) porque asume tramos RECTOS
# todos con la misma rotación local. Un grupo de arcos curvos (anillo) no cumple esa
# premisa: cada tramo mira a un ángulo distinto, y necesita SU PROPIO eje (el que el
# shader ya calcula por vértice) en vez de un flow_dir fijo para todo el grupo. Activar
# este export en esos grupos respeta use_local_axis=true; el default false no cambia
# nada en ningún uso existente (CoolantLab, tramos rectos de Dome_Intro).
export(bool) var use_local_axis_override := false
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
# Color del caño en reposo y color del fluido que corre por dentro. Por defecto, cian de
# criocoolant; una corrida de atmósfera usa blanco/rojo y una de plasma, ámbar. Es lo que
# permite reusar la misma corrida de tubería para los cuatro sistemas.
export(Color) var base_color := Color(0.06, 0.22, 0.35, 1.0) setget set_base_color
export(Color) var flow_color := Color(0.35, 0.92, 0.98, 1.0) setget set_flow_color
# Tamaño del patrón de ruido en metros.
export(float, 0.1, 6.0) var noise_scale := 1.6 setget set_noise_scale
# Transparencia del caño: 1.0 opaco. Un poco por debajo deja intuir el volumen interno.
export(float, 0.2, 1.0) var pipe_alpha := 0.88 setget set_pipe_alpha
# Descartar las tapas del cilindro. Sirve en un caño translúcido, donde los discos
# interiores se ven a través de la pared; en uno opaco conviene dejarlas, porque son la
# cara redonda del extremo libre.
export(bool) var hide_caps := true

# Collar en la entrada del tramo (extremo -Y local): tapa el borde donde este cilindro
# se toca con el tramo anterior. Cada PipeRun es una malla separada — hide_caps del
# shader descarta la tapa plana, pero no el anillo del borde entre dos mallas distintas,
# que se nota como una costura. El último tramo de una rama (contra el sumidero) no
# necesita nada del lado de salida porque ahí no hay otra malla con la que chocar.
export(bool) var add_entry_collar := true
export(float) var collar_radius_margin := 0.03
export(float) var collar_height := 0.12
export(Color) var collar_color := Color(0.18, 0.2, 0.23, 1.0)

var _material: ShaderMaterial = null
# El shader trata flow_phase == 0.0 como "sin override, animar con TIME" (lo usa
# PipeRun.gd para conducciones decorativas sin lógica de caudal). PipeCoolantRun SÍ
# controla el caudal, así que _phase nunca debe caer justo en ese sentinel — si el
# caudal arranca en 0 (tanque vacío desde el inicio) y nunca se mueve, un flow_phase
# de 0.0 exacto dejaría el caño animándose solo con el reloj, ignorando que está sin
# caudal. Un offset ínfimo evita el choque sin cambiar el patrón visual.
var _phase: float = 0.0001
var _current_speed: float = 0.0


func _ready() -> void:
	_current_speed = flow_speed
	_apply()
	if add_entry_collar:
		_spawn_entry_collar()


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


func set_base_color(v: Color) -> void:
	base_color = v
	_apply()


func set_flow_color(v: Color) -> void:
	flow_color = v
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
		var base = load(flow_material_path)
		if base == null:
			return
		# Una copia por corrida: el material del .tres es un recurso compartido por load(),
		# y dos corridas en la misma escena (oeste/este) se pisaban los parametros entre si
		# — la ultima en aplicar mandaba sobre las dos.
		_material = (base as ShaderMaterial).duplicate()

	var dir: Vector3 = flow_dir
	if dir.length() > 0.001:
		dir = dir.normalized()

	if _material:
		_material.set_shader_param("flow_dir", dir)
		# use_local_axis por defecto en el shader deduce el eje del propio tramo (útil
		# para codos), pero no tiene signo: dos tramos con la misma rotación local
		# animan hacia el mismo lado del mundo aunque su flow_dir real sea opuesto
		# (rama oeste vs este). PipeCoolantRun siempre setea flow_dir explícito por
		# instancia, así que acá se apaga use_local_axis para que el shader lo respete
		# — salvo que use_local_axis_override lo pida (grupo de arcos curvos, ver export).
		_material.set_shader_param("use_local_axis", use_local_axis_override)
		# Un grupo horneado (bake_pipe_network.gd) fusiona varios tramos en un CombinedMesh:
		# WORLD_MATRIX ya no sirve para recuperar el eje de cada tramo original, asi que el
		# shader debe leerlo de COLOR (horneado por-vertice en bake-time) en vez de calcularlo
		# el mismo en runtime.
		_material.set_shader_param("use_baked_axis", has_node("CombinedMesh"))
		_material.set_shader_param("flow_phase", _phase)
		_material.set_shader_param("pipe_alpha", pipe_alpha)
		_material.set_shader_param("emission_strength", base_emission * flow_intensity)
		_material.set_shader_param("noise_scale", noise_scale)
		_material.set_shader_param("base_color", base_color)
		_material.set_shader_param("flow_color", flow_color)
		_material.set_shader_param("hide_caps", hide_caps)

	_assign_to_meshes(self)


const _COLLAR_NAME := "_EntryCollar"


func _spawn_entry_collar() -> void:
	if has_node(_COLLAR_NAME):
		return
	var cyl := _find_cylinder_visual(self)
	if cyl == null:
		return
	var mesh: CylinderMesh = cyl.mesh
	var radius: float = max(mesh.top_radius, mesh.bottom_radius)
	var half_height: float = mesh.height * 0.5

	var collar_mesh := CylinderMesh.new()
	collar_mesh.top_radius = radius + collar_radius_margin
	collar_mesh.bottom_radius = radius + collar_radius_margin
	collar_mesh.height = collar_height
	collar_mesh.radial_segments = mesh.radial_segments
	collar_mesh.rings = 1

	var collar_mat := SpatialMaterial.new()
	collar_mat.albedo_color = collar_color
	collar_mat.metallic = 0.3
	collar_mat.roughness = 0.8

	var collar := MeshInstance.new()
	collar.name = _COLLAR_NAME
	collar.mesh = collar_mesh
	collar.set_surface_material(0, collar_mat)
	collar.add_to_group(SKIP_GROUP)
	# El collar hereda la rotación del Visual (mismo eje que el cilindro del caño) y se
	# ubica en su extremo -Y local: el lado de ENTRADA del tramo, donde se apoya contra
	# el tramo anterior. cyl.transform solo es el eje real del nodo cuando cyl es HIJO
	# DIRECTO de self — _find_cylinder_visual() recorre recursivamente y puede devolver
	# un nieto (por ejemplo el MeshInstance de un PipeSection anidado dentro de un arco
	# de un anillo curvo), cuyo .transform es relativo a SU PADRE INMEDIATO, no a self.
	# Usar la transform global de ambos evita ese desajuste de espacio sin importar
	# cuántos niveles de anidamiento haya entre self y el cilindro real.
	var cyl_to_self: Transform = global_transform.affine_inverse() * cyl.global_transform
	var entry_local: Vector3 = cyl_to_self.xform(Vector3(0, -half_height, 0))
	var collar_basis: Basis = cyl_to_self.basis
	collar.transform = Transform(collar_basis, entry_local)
	add_child(collar)


func _find_cylinder_visual(node: Node) -> MeshInstance:
	for child in node.get_children():
		if child is MeshInstance and child.mesh is CylinderMesh and not child.is_in_group(SKIP_GROUP):
			return child
		if child.get_child_count() > 0:
			var found := _find_cylinder_visual(child)
			if found != null:
				return found
	return null


func _assign_to_meshes(node: Node) -> void:
	for child in node.get_children():
		# Los collares y demás herrajes cuelgan del tramo para que el oclusor por dither
		# los alcance (entra por el StaticBody del tramo), pero son metal: si se les pinta
		# el material de fluido dejan de leerse como juntas y el caño pierde sus marcas.
		if child.is_in_group(SKIP_GROUP):
			continue
		if child is MeshInstance:
			child.set_surface_material(0, _material)
		if child.get_child_count() > 0:
			_assign_to_meshes(child)
