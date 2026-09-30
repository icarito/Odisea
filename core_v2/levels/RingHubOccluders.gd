extends Spatial

# RingHubOccluders.gd — oclusion estatica barata para RingHub (FD-316 tarea EE).
#
# El tier LOW venia ahorrando geometria OCULTANDO los trozos lejanos del andamio
# (culler de distancia del gate, 2d7b3d61) y el pop-in se notaba. La via preferida
# es dejar de DIBUJAR lo que la camara no puede ver: RingHub es un cilindro de
# pisos apilados (Hub/RingFloor y Hub/Floor_2..5, radio exterior 13 m / interior
# 6 m, un piso cada 4.5 m desde y=4.5) con un nucleo central del que salen los
# HubSpokes. Los poligonos de este nodo son las superficies opacas REALES del
# nivel, aproximadas a partir de esa geometria conocida: un anillo horizontal por
# piso y el prisma del nucleo. El motor descarta lo que quede detras de ellos.
#
# Godot 3.6 usa los Occluder en runtime sin horneado previo (OccluderShapePolygon
# es una primitiva); el presupuesto de formas activas vive en
# rendering/misc/occlusion_culling/max_active_polygons y se sube en project.godot.
#
# Se construye SOLO en tier LOW por defecto (es donde hacia falta), pero el env
# ODISEA_OCCLUDERS lo fuerza o lo niega para el A/B: ODISEA_OCCLUDERS=1 en
# cualquier tier, ODISEA_OCCLUDERS=0 lo apaga aunque el gate este en LOW.
#
# Los poligonos son visual-only: no tienen colision ni estado, no entran a
# replay_sync y no cambian la simulacion.

const OCCLUDERS_ENV := "ODISEA_OCCLUDERS"

# Geometria conocida de RingHub_Level.tscn. Editable desde el Inspector si el hub
# cambia de pisos/radios; los defaults son los del nivel actual.
export(Array, float) var floor_heights := [4.5, 9.0, 13.5, 18.0, 22.5]
export(float, 0.5, 60.0, 0.1) var floor_outer_radius := 13.0
export(float, 0.0, 60.0, 0.1) var floor_inner_radius := 6.0
export(int, 3, 16) var floor_sides := 8

# Nucleo central: prisma vertical del que salen los HubSpokes.
export(float, 0.1, 30.0, 0.1) var core_radius := 1.2
export(float, -200.0, 200.0, 0.1) var core_bottom := 4.5
export(float, -200.0, 200.0, 0.1) var core_top := 22.5
export(int, 3, 16) var core_sides := 4

export(bool) var enabled := true

var _built := false

func _ready() -> void:
	if not _should_build():
		return
	build()

# Encendido por defecto en tier LOW; ODISEA_OCCLUDERS=1/0 lo fuerza o lo niega en
# cualquier tier sin rebuild (A/B con la traza de replay del device).
func _should_build() -> bool:
	if not enabled:
		return false
	var raw := OS.get_environment(OCCLUDERS_ENV).strip_edges().to_lower()
	if raw in ["1", "true", "yes", "on"]:
		return true
	if raw in ["0", "false", "no", "off"]:
		return false
	var gate = get_node_or_null("/root/GLES3VendorGate")
	return gate != null and gate.has_method("is_low_tier") and bool(gate.is_low_tier())

# Construye los occluders una vez. Idempotente.
func build() -> void:
	if _built:
		return
	_built = true
	var count := 0
	var floor_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	for height in floor_heights:
		var floor_occ := Occluder.new()
		floor_occ.name = "FloorOccluder_%d" % count
		floor_occ.transform = Transform(floor_basis, Vector3(0.0, float(height), 0.0))
		var floor_shape := OccluderShapePolygon.new()
		floor_shape.two_way = true
		floor_shape.polygon_points = _ring_points(floor_outer_radius)
		floor_shape.hole_points = _ring_points(floor_inner_radius)
		floor_occ.shape = floor_shape
		add_child(floor_occ)
		count += 1

	var core_mid_y: float = (core_bottom + core_top) * 0.5
	var core_height: float = max(0.01, core_top - core_bottom)
	var chord: float = 2.0 * core_radius * tan(PI / float(core_sides))
	for i in range(core_sides):
		var angle: float = TAU * float(i) / float(core_sides)
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var side := Occluder.new()
		side.name = "CoreOccluder_%d" % i
		# El poligono vive en el plano XY local; esta base lo para vertical. Tiene que ser
		# una rotacion propia (determinante +1): Basis(tangent, UP, radial) da un eje Z
		# espejado y el culler de occlusion descartaba el poligono (el A/B no cambiaba
		# nada). Con -radial como Z la mano queda derecha y el plano es el mismo.
		side.transform = Transform(Basis(tangent, Vector3.UP, -radial), radial * core_radius + Vector3.UP * core_mid_y)
		var core_shape := OccluderShapePolygon.new()
		core_shape.two_way = true
		core_shape.polygon_points = PoolVector2Array([
			Vector2(-chord * 0.5, -core_height * 0.5),
			Vector2(chord * 0.5, -core_height * 0.5),
			Vector2(chord * 0.5, core_height * 0.5),
			Vector2(-chord * 0.5, core_height * 0.5),
		])
		side.shape = core_shape
		add_child(side)
		count += 1
	print("[RingHubOccluders] %d occluders (%d pisos + %d nucleo)" % [count, floor_heights.size(), core_sides])

# Anillo convexo regular en el plano local (el agujero del piso entra por
# hole_points). Los puntos son 2D: con la base de los pisos, local X/Y cae en el
# plano XZ del mundo.
func _ring_points(radius: float) -> PoolVector2Array:
	var points := PoolVector2Array()
	for i in range(floor_sides):
		var angle: float = TAU * float(i) / float(floor_sides)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

# Cuantos occluders deberia haber con la configuracion actual.
func expected_occluder_count() -> int:
	return floor_heights.size() + core_sides

# Cuantos occluders hay construidos (0 si no corrio el build).
func occluder_count() -> int:
	var total := 0
	for child in get_children():
		if child is Occluder:
			total += 1
	return total
