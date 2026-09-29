extends SceneTree

# Variante ultra-low de la luminaria industrial de pared (FD-316, tarea V).
#
# La malla horneada que comparten los domos (IndustrialWallLampLOD.mesh) ronda los
# 1465 vertices por instancia y el MultiMesh prebaked la dibuja entera aunque el
# LOD adaptativo no aplique: el nodo llega con auto_build=false y sin
# fixture_lod_mesh, asi que la ruta de _drive_fixture_lod sale sin hacer nada. En
# el Anbernic (640x480) los 16 apliques del domo, siempre en frustum desde el
# criopod, suman ~23k vertices por nada.
#
# Esta herramienta genera por revolucion una silueta simplificada (disco de pared
# + campana de 3 anillos + ampolla de vidrio; sin biseles) con <= 150 vertices.
# Conserva la MISMA estructura de la LOD: superficie 0 = cuerpo metalico,
# superficie 1 = vidrio emisivo, para que RingHubLightState siga animando la
# emision del vidrio. No toca IndustrialWallLampLOD.mesh ni IndustrialWallLampLow.mesh.
#
# Rebuild con:
#   tools/godot --no-window --audio-driver Dummy --path . \
#     -s res://tools/build_wall_lamp_low_detail.gd

const SOURCE_LOD := "res://core_v2/props/scifi_lights/IndustrialWallLampLOD.mesh"
const TARGET := "res://core_v2/props/scifi_lights/IndustrialWallLampLODLow.mesh"

# El eje +Z del aplique mira hacia adentro del domo (misma convencion que
# _fixture_transform en bake_ringhub_wall_sconces.gd: el plato apoya en la pared
# en z=0 y la campana crece hacia +Z).
const BODY_SEGMENTS := 12
const GLASS_SEGMENTS := 8
const PLATE_RADIUS := 0.10
# Perfil (radio, z) de la campana, revolucionado alrededor del eje Z.
const SHADE_PROFILE := [
	Vector2(0.05, 0.02),
	Vector2(0.115, 0.125),
	Vector2(0.09, 0.145),
]
const GLASS_RADIUS := 0.055
const GLASS_BACK_Z := 0.04
const GLASS_FRONT_Z := 0.09

# Acumulador explicito: SurfaceTool reexpande la malla y perderiamos el tope de
# vertices, asi que se arman los arrays a mano. Son Array (tipo referencia) y se
# convierten a Pool*Array recien al comprometer la superficie: mutar un Pool
# guardado como propiedad de un objeto se pierde en GDScript 1.x.
class Builder:
	var vertices := []
	var normals := []
	var uvs := []
	var indices := []

func _init() -> void:
	var source: Mesh = load(SOURCE_LOD) as Mesh
	if source == null or source.get_surface_count() < 2:
		_fail("No se pudo cargar %s con sus dos superficies" % SOURCE_LOD)
		return
	var body_material = source.surface_get_material(0)
	var glass_material = source.surface_get_material(1)
	# El cuerpo se ve por fuera y por dentro (la campana es abierta); el material
	# original puede ser cull_back y dejaria el interior invisible en la version
	# de una sola capa. Se duplica para no tocar el recurso compartido.
	var body_dup = body_material.duplicate() if body_material != null else null
	if body_dup is SpatialMaterial:
		(body_dup as SpatialMaterial).params_cull_mode = SpatialMaterial.CULL_DISABLED
		body_dup.resource_name = str((body_material as SpatialMaterial).resource_name) + "_low"

	var out := ArrayMesh.new()
	var body := Builder.new()
	_add_disc(body, BODY_SEGMENTS, PLATE_RADIUS)
	_add_lathe(body, SHADE_PROFILE, BODY_SEGMENTS)
	_commit(out, body, body_dup if body_dup != null else body_material)
	var glass := Builder.new()
	_add_capped_cylinder(glass, GLASS_SEGMENTS, GLASS_RADIUS, GLASS_BACK_Z, GLASS_FRONT_Z)
	_commit(out, glass, glass_material)
	out.resource_name = "IndustrialWallLampLODLow"

	var result: int = ResourceSaver.save(TARGET, out)
	if result != OK:
		_fail("ResourceSaver fallo con codigo %d" % result)
		return
	print("Aplique low-detail: %d vertices en %d superficies -> %s" % [
		_vertex_count(out), out.get_surface_count(), TARGET])
	quit()

func _push(builder: Builder, position: Vector3, normal: Vector3, uv: Vector2) -> int:
	var index: int = builder.vertices.size()
	builder.vertices.push_back(position)
	builder.normals.push_back(normal)
	builder.uvs.push_back(uv)
	return index

func _tri(builder: Builder, a: int, b: int, c: int) -> void:
	builder.indices.push_back(a)
	builder.indices.push_back(b)
	builder.indices.push_back(c)

# Abanico plano contra z=0, mirando hacia +Z.
func _add_disc(builder: Builder, segments: int, radius: float) -> void:
	var base: int = _push(builder, Vector3(0.0, 0.0, 0.0), Vector3.BACK, Vector2(0.5, 0.5))
	for index in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		var unit := Vector2(cos(angle), sin(angle))
		_push(builder, Vector3(unit.x * radius, unit.y * radius, 0.0), Vector3.BACK,
			unit * 0.5 + Vector2(0.5, 0.5))
	for index in range(segments):
		var next: int = (index + 1) % segments
		_tri(builder, base, base + 1 + index, base + 1 + next)

# Superficie de revolucion: recorre un perfil (radio, z) y lo gira alrededor de Z.
# Los vertices de anillos contiguos se comparten, asi el conteo es perfil*segmentos.
func _add_lathe(builder: Builder, profile: Array, segments: int) -> void:
	var base: int = builder.vertices.size()
	for ring in range(profile.size()):
		var point: Vector2 = profile[ring]
		var v: float = float(ring) / float(max(profile.size() - 1, 1))
		for index in range(segments):
			var angle: float = TAU * float(index) / float(segments)
			var unit := Vector2(cos(angle), sin(angle))
			_push(builder, Vector3(unit.x * point.x, unit.y * point.x, point.y),
				Vector3(unit.x, unit.y, 0.0), Vector2(float(index) / float(segments), v))
	for ring in range(profile.size() - 1):
		var ring_base: int = base + ring * segments
		for index in range(segments):
			var next: int = (index + 1) % segments
			var a: int = ring_base + index
			var b: int = ring_base + next
			var c: int = ring_base + segments + index
			var d: int = ring_base + segments + next
			_tri(builder, a, b, c)
			_tri(builder, b, d, c)

# Cilindro corto con las dos tapas, para que la ampolla se lea encendida desde
# cualquier angulo. Los anillos se comparten con los abanicos de las tapas.
func _add_capped_cylinder(builder: Builder, segments: int, radius: float, z0: float, z1: float) -> void:
	for ring in range(2):
		var z: float = z0 if ring == 0 else z1
		for index in range(segments):
			var angle: float = TAU * float(index) / float(segments)
			var unit := Vector2(cos(angle), sin(angle))
			_push(builder, Vector3(unit.x * radius, unit.y * radius, z),
				Vector3(unit.x, unit.y, 0.0), Vector2(float(index) / float(segments), float(ring)))
	var center_back: int = _push(builder, Vector3(0.0, 0.0, z0), -Vector3.BACK, Vector2(0.5, 0.5))
	var center_front: int = _push(builder, Vector3(0.0, 0.0, z1), Vector3.BACK, Vector2(0.5, 0.5))
	for index in range(segments):
		var next: int = (index + 1) % segments
		# Lado.
		_tri(builder, index, index + segments, next)
		_tri(builder, next, index + segments, next + segments)
		# Tapa trasera (z0, mira hacia -Z) y delantera (z1, mira hacia +Z).
		_tri(builder, center_back, next, index)
		_tri(builder, center_front, index + segments, next + segments)

func _commit(out: ArrayMesh, builder: Builder, material) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PoolVector3Array(builder.vertices)
	arrays[Mesh.ARRAY_NORMAL] = PoolVector3Array(builder.normals)
	arrays[Mesh.ARRAY_TEX_UV] = PoolVector2Array(builder.uvs)
	arrays[Mesh.ARRAY_INDEX] = PoolIntArray(builder.indices)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(out.get_surface_count() - 1, material)

func _vertex_count(mesh: Mesh) -> int:
	var total := 0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		total += (arrays[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
	return total

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
