extends SceneTree

# Lamparas de pared para RingHub: la misma luminaria industrial de Dome_Intro,
# pero solo la malla LOD y dos anillos de ocho en vez de los once de 88 que
# lleva el domo. La cupula de RingHub es una esfera de radio 35 centrada en el
# origen (ver bake_dome_interior_lowpoly.gd), asi que la normal de la pared en
# cada marcador es simplemente su propia direccion desde el origen.
#
# Rebuild con:
#   tools/godot --no-window --audio-driver Dummy --path . \
#     -s res://tools/bake_ringhub_wall_sconces.gd

const MESH_PATH := "res://core_v2/props/scifi_lights/IndustrialWallLampLOD.mesh"
const FIXTURES_PATH := "res://core_v2/levels/interiors/RingHub_WallLightFixtures.tres"
const MARKERS_PATH := "res://core_v2/levels/interiors/RingHub_WallLightMarkers.tres"

const DOME_RADIUS := 35.0
# Los marcadores viven medio metro por dentro de la cascara; el fixture sale
# hacia la pared WALL_OFFSET, quedando justo contra ella sin atravesarla.
const MARKER_INSET := 0.5
const WALL_OFFSET := 0.30
const FIXTURE_SCALE := 3.0
const PER_RING := 8
# Altura de cada anillo y su giro, para que uno no quede tapado por el otro.
const RINGS := [[5.0, 0.0], [14.0, 22.5]]
const LIT_COLOR := Color(0.72, 0.84, 1.0, 1.0)

func _init() -> void:
	var mesh: Mesh = load(MESH_PATH) as Mesh
	if mesh == null:
		_fail("No se pudo cargar %s" % MESH_PATH)
		return

	var markers := MultiMesh.new()
	markers.transform_format = MultiMesh.TRANSFORM_3D
	markers.color_format = MultiMesh.COLOR_8BIT
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	markers.mesh = quad

	var fixtures := MultiMesh.new()
	fixtures.transform_format = MultiMesh.TRANSFORM_3D
	fixtures.mesh = mesh

	var count: int = RINGS.size() * PER_RING
	markers.instance_count = count
	fixtures.instance_count = count

	var index := 0
	for ring in RINGS:
		var height: float = float(ring[0])
		var phase: float = deg2rad(float(ring[1]))
		var ring_radius: float = sqrt(max(DOME_RADIUS * DOME_RADIUS - height * height, 0.0))
		for step in range(PER_RING):
			var angle: float = phase + TAU * float(step) / float(PER_RING)
			var inset: float = max(ring_radius - MARKER_INSET, 0.1)
			var marker := Vector3(cos(angle) * inset, height, sin(angle) * inset)
			markers.set_instance_transform(index, Transform(Basis(), marker))
			markers.set_instance_color(index, LIT_COLOR)
			fixtures.set_instance_transform(index, _fixture_transform(marker))
			index += 1

	if ResourceSaver.save(MARKERS_PATH, markers) != OK:
		_fail("No se pudo guardar %s" % MARKERS_PATH)
		return
	if ResourceSaver.save(FIXTURES_PATH, fixtures) != OK:
		_fail("No se pudo guardar %s" % FIXTURES_PATH)
		return
	print("Horneadas %d lamparas de pared en %s" % [count, FIXTURES_PATH])
	quit()

# Misma convencion que bake_dome_wall_sconces.gd: la luminaria mira hacia
# adentro y se apoya contra la pared, corrida WALL_OFFSET hacia afuera.
func _fixture_transform(marker: Vector3) -> Transform:
	var outward: Vector3 = marker.normalized()
	var inward: Vector3 = -outward
	var right: Vector3 = Vector3.UP.cross(inward).normalized()
	var up: Vector3 = inward.cross(right).normalized()
	var basis := Basis(right, up, inward).scaled(Vector3.ONE * FIXTURE_SCALE)
	return Transform(basis, marker + outward * WALL_OFFSET)

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
