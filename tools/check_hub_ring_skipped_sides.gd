extends SceneTree

# check_hub_ring_skipped_sides.gd — Verifica ScaffoldHubRing.skipped_sides.
#
# Lo que se rompe si el salteo esta mal no se ve en un diff: el anillo sigue
# construyendo y solo queda un borde sin baranda por el que el jugador se cae.
#
# El conteo de vertices NO sirve para verificar la baranda: _add_rail_edge emite un
# numero fijo de tubos por tramo, sin importar el largo, asi que sacar un sector
# (pierde su arco interno y su arco externo) y darle baranda radial a los dos
# vecinos da exactamente el mismo total. Hay que mirar DONDE quedaron los vertices:
# la baranda radial pasa por el medio del anillo (r ~ 10.3 con outer 13 / inner 6),
# un radio donde el anillo completo no tiene ninguna baranda.
#
# Run: godot3-bin --path . --no-window -s tools/check_hub_ring_skipped_sides.gd

const HubRing := preload("res://core_v2/props/scaffold/ScaffoldHubRing.gd")

const SIDES := 8
const OUTER := 13.0
const INNER := 6.0
# Orden de commit en _build_compact_ring(): deck_top, deck, frame, rail[, hazard].
const SURFACE_DECK := 0
const SURFACE_FRAME := 2
const SURFACE_RAIL := 3

var _fallas := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var completo: ArrayMesh = _construir([])
	var un_hueco: ArrayMesh = _construir([2])
	var intercalado: ArrayMesh = _construir([1, 3, 5, 7])

	_check("deck baja al sacar un sector",
		_largo(un_hueco, SURFACE_DECK) < _largo(completo, SURFACE_DECK))
	_check("deck baja mas al intercalar",
		_largo(intercalado, SURFACE_DECK) < _largo(un_hueco, SURFACE_DECK))

	# Referencia: sin huecos ningun borde radial esta al aire, asi que a media
	# profundidad del deck no puede haber baranda.
	_check("el anillo completo no tiene baranda radial",
		not _hay_baranda_radial(completo, 90.0) and not _hay_baranda_radial(completo, 135.0))

	# Sacar el sector 2 (90..135 grados) deja sus DOS bordes al aire.
	_check("un hueco cierra su borde a 90 grados", _hay_baranda_radial(un_hueco, 90.0))
	_check("un hueco cierra su borde a 135 grados", _hay_baranda_radial(un_hueco, 135.0))
	_check("un hueco no toca bordes ajenos", not _hay_baranda_radial(un_hueco, 45.0))

	# Intercalado: quedan en pie 0, 2, 4 y 6, cada uno con sus dos bordes al aire.
	for grados in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]:
		_check("intercalado cierra el borde a %d grados" % int(grados),
			_hay_baranda_radial(intercalado, grados))

	# Cuatro sectores en pie con sus dos esquinas al aire: ocho columnas, las mismas
	# que el anillo completo. Si el vecino ausente no repusiera la columna de la
	# esquina `b`, serian cuatro y el deck quedaria volado.
	_check("el intercalado conserva las columnas",
		_largo(intercalado, SURFACE_FRAME) == _largo(completo, SURFACE_FRAME))

	# Indices fuera de rango y negativos normalizan contra sides.
	_check("indice fuera de rango normaliza", _hay_baranda_radial(_construir([10]), 90.0))
	_check("indice negativo normaliza", _hay_baranda_radial(_construir([-6]), 90.0))

	if _fallas > 0:
		push_error("[check_hub_ring] %d fallas" % _fallas)
		quit(1)
		return
	print("[check_hub_ring] ok, %d comprobaciones" % _comprobaciones)
	quit(0)


func _construir(fuera: Array) -> ArrayMesh:
	var ring: Spatial = HubRing.new()
	ring.auto_build = false
	ring.sides = SIDES
	ring.outer_radius = OUTER
	ring.inner_radius = INNER
	ring.skipped_sides = fuera
	get_root().add_child(ring)
	ring.build()
	var mesh: ArrayMesh = ring.get_node("CombinedMesh").mesh
	ring.queue_free()
	return mesh


# Hay baranda cruzando el deck en ese angulo? Se mira la BANDA radial intermedia:
# una baranda de arco toca ese angulo solo en la esquina del poligono (r ~ 14.1 la
# externa, ~6.5 la interna) y su cuerda se hunde recien a 22.5 grados de ahi, asi
# que entre r=8 y r=12.6 a ese angulo no puede haber nada... salvo una baranda que
# cruce el deck de lado a lado.
#
# Se miden centroides de triangulo, no vertices: _add_round_beam arma cada tubo con
# dos anillos de vertices, uno en cada punta, y ninguno en el medio del tramo.
func _hay_baranda_radial(mesh: ArrayMesh, grados: float) -> bool:
	var corner_scale: float = 1.0 / cos(TAU / float(SIDES) * 0.5)
	var r_min: float = INNER * corner_scale + 1.5
	var r_max: float = OUTER * corner_scale - 1.5
	for centro in _centroides(mesh, SURFACE_RAIL):
		var plano := Vector2(centro.x, centro.z)
		var radio: float = plano.length()
		if radio < r_min or radio > r_max:
			continue
		if abs(rad2deg(plano.angle()) - grados) < 2.0 or abs(rad2deg(plano.angle()) - grados + 360.0) < 2.0:
			return true
	return false


func _centroides(mesh: ArrayMesh, surface: int) -> Array:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices == null or indices.size() == 0:
		indices = PoolIntArray(range(verts.size()))
	var salida := []
	var i := 0
	while i + 2 < indices.size():
		salida.append((verts[indices[i]] + verts[indices[i + 1]] + verts[indices[i + 2]]) / 3.0)
		i += 3
	return salida


func _largo(mesh: ArrayMesh, surface: int) -> int:
	return mesh.surface_get_array_len(surface)


var _comprobaciones := 0

func _check(que: String, ok: bool) -> void:
	_comprobaciones += 1
	if not ok:
		_fallas += 1
		printerr("[check_hub_ring] FALLA: %s" % que)
