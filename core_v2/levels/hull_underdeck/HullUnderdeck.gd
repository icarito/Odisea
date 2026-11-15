extends "res://core_v2/levels/scaffold_run/ScaffoldRunLab.gd"

# Entrecasco: el espacio entre la espiral de terrazas y el casco de la nave (el "gap
# casco-espirales" de FD-037 / FD-050). Gravedad centrifuga: "abajo" es hacia afuera, asi que
# el casco es el piso y el enves de las terrazas, el techo. El andamio Transit-Run cuelga en
# medio, apoyado en pilones sobre las cuadernas.
#
# Todo va proyectado sobre el cilindro con ScaffoldChunkOrbit: cada vano de fondo (12 m de
# arco, kit de tools/scaffold_chunks/scene_hull.py) cuelga de su chunk, estirado al arco que
# le toca a SU radio para que los vanos calcen entre si.
#
#   tools/launch_game.sh --scene res://core_v2/levels/hull_underdeck/HullUnderdeck.tscn

const KIT := "res://core_v2/props/hull_underdeck/"
const BAY_WIDTH := 48.0
const SIDE_BAYS := 1      # vanos extra a cada lado del central
const SPINE_DROP := 1.8   # la cercha del andamio cuelga esto bajo su plataforma mas baja

# Radios (m desde el eje de la nave). La espiral de terrazas esta en ~220-290.
export(float) var route_radius := 304.0
export(float) var hull_radius := 320.0
export(float) var terrace_radius := 282.0


func _init() -> void:
	orbit_radius = route_radius


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.024)
	env.ambient_light_color = Color(0.42, 0.50, 0.62)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_color = Color(0.02, 0.028, 0.04)
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 170.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Luz calida desde las terrazas (arriba) y un rebote frio desde el casco.
	for cfg in [[Vector3(-70.0, 30.0, 0.0), 0.75, Color(1.0, 0.88, 0.7)],
			[Vector3(55.0, -150.0, 0.0), 0.22, Color(0.55, 0.7, 1.0)]]:
		var light := DirectionalLight.new()
		light.rotation_degrees = cfg[0]
		light.light_energy = cfg[1]
		light.light_color = cfg[2]
		add_child(light)


func _decorate_chunk(chunk: Spatial, placement: Dictionary) -> void:
	var origin_y: float = placement["origin"].y
	var chunk_radius: float = route_radius - origin_y
	var hull_y: float = -(hull_radius - chunk_radius)
	var ceiling_y: float = chunk_radius - terrace_radius
	_add_bay(chunk, "hull_bay", hull_y, hull_radius / chunk_radius, true)
	_add_bay(chunk, "terrace_underside", ceiling_y, terrace_radius / chunk_radius, false)
	# Pilon de la cuaderna a la cercha del andamio, en la junta de entrada del chunk.
	var spine_y: float = float(placement["low"]) - SPINE_DROP
	var pylon := MeshInstance.new()
	pylon.name = "Pylon"
	pylon.mesh = load(KIT + "hull_pylon.mesh")
	pylon.translation = Vector3(0.0, hull_y, 0.3)
	pylon.scale = Vector3(1.0, spine_y - hull_y, 1.0)
	chunk.add_child(pylon)


# Vano de fondo colgado del chunk a la altura `y`. `arc_scale` lo estira o encoge al arco
# que ocupa a su radio (mas largo hacia el casco, mas corto hacia el eje).
func _add_bay(chunk: Spatial, piece: String, y: float, arc_scale: float, walkable: bool) -> void:
	var half: float = Registry.CHUNK_LENGTH * 0.5
	# El espacio es una corona alrededor de todo el tubo: el vano se repite a lo ancho (eje
	# de la nave) para que el casco no se lea como una cinta flotando.
	for lane in range(-SIDE_BAYS, SIDE_BAYS + 1):
		var bay := MeshInstance.new()
		bay.name = "%s_%d" % [piece, lane]
		bay.mesh = load(KIT + piece + ".mesh")
		bay.translation = Vector3(float(lane) * BAY_WIDTH, y, half - half * arc_scale)
		bay.scale = Vector3(1.0, 1.0, arc_scale)
		chunk.add_child(bay)
	if not walkable:
		return
	# El forro del casco se pisa: caer del andamio termina aqui, no en el vacio.
	var body := StaticBody.new()
	body.name = piece + "_floor"
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(BAY_WIDTH * (float(SIDE_BAYS) + 0.5), 0.2, half * arc_scale + 0.1)
	col.shape = box
	body.add_child(col)
	body.translation = Vector3(0.0, y - 0.2, half)
	chunk.add_child(body)
