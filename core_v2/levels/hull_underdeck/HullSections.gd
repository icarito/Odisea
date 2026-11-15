extends "res://core_v2/levels/scaffold_run/ScaffoldRunLab.gd"

# Entrecasco por SECCIONES: anillos consecutivos a lo largo del eje de la nave, cada uno con
# su propia gravedad y su propio giro. La ruta corre a lo largo del eje (+Z) y cruza de un
# anillo al siguiente; el casco se curva hacia arriba a los lados.
#
# - Gravedad: cada seccion fija la del jugador, y su tramo esta dimensionado (y horneado) para
#   esa gravedad: mismos chunks, otros huecos y otros muros.
# - Giro: el mundo se ancla al anillo que pisa el jugador; los demas derivan de costado segun
#   la diferencia de giro. Solo deriva el FONDO (es periodico cada vano, asi que se envuelve
#   sin costura); la ruta de cada anillo se queda donde esta.
# - Empalme: al cruzar a un anillo que gira distinto, el jugador conserva su velocidad y el
#   piso nuevo se le va de costado: se lo lleva un barrido lateral que se apaga solo.
#
# `gravity` (m/s2) y `drift` (m/s de arco, + hacia +X) son perillas de diseño independientes,
# NO se derivan una de otra con g = w2·r: a estos radios una diferencia de gravedad que se
# sienta implicaria decenas de m/s de deriva.
#
#   tools/launch_game.sh --scene res://core_v2/levels/hull_underdeck/HullSections.tscn

const KIT := "res://core_v2/props/hull_underdeck/"
const BAY_WIDTH := 48.0        # ancho del vano = paso de arco del fondo
const SPINE_DROP := 1.8
const SWEEP_DECAY := 3.0       # m/s2 con que se apaga el barrido del empalme
const FLOOR_HALF_WIDTH := 60.0

export(float) var route_radius := 304.0
export(float) var hull_radius := 320.0
export(float) var terrace_radius := 282.0
export(int, 0, 4) var side_lanes := 2

var sections := [
	{"count": 6, "gravity": 14.0, "drift": 0.0},
	{"count": 6, "gravity": 8.0, "drift": 2.5},
	{"count": 6, "gravity": 20.0, "drift": -3.0},
]

var _placements := []
var _decor_roots := []   # Spatial por seccion, sobre el eje de la nave
var _offsets := []       # deriva acumulada de cada seccion (m de arco)
var _current := -1
var _sweep := 0.0


func _generate(m: Dictionary) -> Dictionary:
	var graph: Dictionary = Registry.generate_sections(seed_value, sections, m)
	_placements = graph["placements"]
	_build_decor()
	return graph


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.024)
	env.ambient_light_color = Color(0.42, 0.50, 0.62)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_color = Color(0.02, 0.028, 0.04)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 190.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	for cfg in [[Vector3(-70.0, 30.0, 0.0), 0.75, Color(1.0, 0.88, 0.7)],
			[Vector3(55.0, -150.0, 0.0), 0.22, Color(0.55, 0.7, 1.0)]]:
		var light := DirectionalLight.new()
		light.rotation_degrees = cfg[0]
		light.light_energy = cfg[1]
		light.light_color = cfg[2]
		add_child(light)


# Fondo de cada seccion: forro del casco y enves de terrazas como MultiMesh colgados de un
# nodo sobre el eje de la nave. Girar ese nodo desliza todo el anillo de costado.
func _build_decor() -> void:
	var z := 0.0
	var arc_step: float = BAY_WIDTH / hull_radius
	for section in sections:
		var count: int = int(section["count"])
		var root := Spatial.new()
		root.name = "Ring_%d" % _decor_roots.size()
		root.translation = Vector3(0.0, route_radius, 0.0)
		add_child(root)
		for piece in [["hull_bay", hull_radius, 1.0], ["terrace_underside", terrace_radius, terrace_radius / hull_radius]]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = load(KIT + str(piece[0]) + ".mesh")
			mm.instance_count = count * (side_lanes * 2 + 1)
			var i := 0
			for j in range(count):
				for lane in range(-side_lanes, side_lanes + 1):
					var a: float = float(lane) * arc_step
					var basis := Basis(Vector3(0.0, 0.0, 1.0), a)
					basis.x *= float(piece[2])  # el techo cubre el mismo angulo con menos arco
					var radius: float = float(piece[1])
					mm.set_instance_transform(i, Transform(basis,
						Vector3(radius * sin(a), -radius * cos(a), z + float(j) * Registry.CHUNK_LENGTH)))
					i += 1
			var mmi := MultiMeshInstance.new()
			mmi.name = str(piece[0])
			mmi.multimesh = mm
			root.add_child(mmi)
		# El forro se pisa bajo la ruta (caja plana: a +-60 m la flecha del arco es ~1 m).
		var length: float = float(count) * Registry.CHUNK_LENGTH
		var body := StaticBody.new()
		body.name = "HullFloor_%d" % _decor_roots.size()
		var col := CollisionShape.new()
		var box := BoxShape.new()
		box.extents = Vector3(FLOOR_HALF_WIDTH, 0.2, length * 0.5)
		col.shape = box
		body.add_child(col)
		body.translation = Vector3(0.0, route_radius - hull_radius - 0.2, z + length * 0.5)
		add_child(body)
		_decor_roots.append(root)
		_offsets.append(0.0)
		z += length


func _decorate_chunk(chunk: Spatial, placement: Dictionary) -> void:
	var hull_y: float = route_radius - hull_radius - float(placement["origin"].y)
	var spine_y: float = float(placement["low"]) - SPINE_DROP
	var pylon := MeshInstance.new()
	pylon.name = "Pylon"
	pylon.mesh = load(KIT + "hull_pylon.mesh")
	pylon.translation = Vector3(0.0, hull_y, 0.3)
	pylon.scale = Vector3(1.0, spine_y - hull_y, 1.0)
	chunk.add_child(pylon)


func section_at(z: float) -> int:
	if _placements.empty():
		return 0
	var index: int = int(clamp(floor(z / Registry.CHUNK_LENGTH), 0, _placements.size() - 1))
	return int(_placements[index]["section"])


func current_section() -> int:
	return _current


func _physics_process(delta: float) -> void:
	._physics_process(delta)
	if not is_instance_valid(_pilot) or _autopilot == null:
		return
	var section: int = section_at(to_local(_pilot.global_transform.origin).z)
	if section != _current:
		# Empalme: el jugador trae la velocidad del anillo que deja.
		if _current >= 0:
			_sweep += float(sections[_current]["drift"]) - float(sections[section]["drift"])
		_current = section
		_pilot.jump_logic.gravity = -Registry.gravity_tier(float(sections[section]["gravity"]))
		_autopilot.refresh_metrics()
	if _sweep != 0.0:
		_sweep = move_toward(_sweep, 0.0, SWEEP_DECAY * delta)
		_pilot.set_external_source_is_static(false)
		_pilot.set_external_velocity(Vector3(_sweep, 0.0, 0.0))
	var here: float = float(sections[_current]["drift"])
	for i in range(_decor_roots.size()):
		_offsets[i] = fposmod(_offsets[i] + (float(sections[i]["drift"]) - here) * delta, BAY_WIDTH)
		_decor_roots[i].rotation.z = _offsets[i] / hull_radius
