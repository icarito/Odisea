extends SceneTree

# bake_ringhub_floor.gd — Hornea el piso de RingHub_Level a .mesh.
#
# Reemplaza al CSGBox de 50x50 que habia antes: no llegaba al borde del domo
# (dejaba un anillo negro entre r=25 y r=35), se teselaba en runtime y no tenia
# UV2, asi que no podia entrar en el lightmap.
#
# El disco comparte el numero de radiales con DomeInteriorLowPoly (16), asi que
# el borde del piso cae exactamente sobre la base del domo: sin costura visible.
# El material sale del piso de Dome_Intro (M_BrushedSteelDark del terrace
# horneado): mismo look, sin texturas, y la luz la pone el bake.
#
# UV1 no se usa (el material no tiene textura). UV2 es un planar [0,1] sobre el
# disco: es lo que consume BakedLightmap.
#
# Run: tools/godot --path . --no-window -s tools/bake_ringhub_floor.gd
# Output: core_v2/levels/RingHub_Floor_baked.mesh

const RADIUS := 35.0
const SEGMENTS := 16
const RINGS := 4
const MATERIAL_SRC := "res://core_v2/levels/interiors/DomeTerraceFloor_baked.mesh"
const OUT_MESH := "res://core_v2/levels/RingHub_Floor_baked.mesh"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var src: ArrayMesh = load(MATERIAL_SRC)
	if src == null or src.get_surface_count() == 0:
		push_error("[bake_ringhub_floor] no pude leer el material de %s" % MATERIAL_SRC)
		quit(1)
		return
	var material: SpatialMaterial = src.surface_get_material(0).duplicate()
	material.resource_name = "M_RingHubFloor"
	# El acero del terrace es metallic=1: sin lightmap toda su difusa es negra y el
	# piso queda de espejo oscuro. Bajado a semi-mate para que lea con ambient y
	# para que el bake de luz (que ilumina la difusa) tenga algo sobre que sumar.
	material.metallic = 0.2
	material.roughness = 0.6
	# Con el ambient de RingHub (energy 1.2) el gris del terrace lee casi blanco:
	# bajado a un gris medio-oscuro, mas cerca del piso de Dome_Intro.
	# O20: subido un punto (0.32 -> 0.40) junto con el andamiaje: el dueño pidio el
	# piso un poco mas gris, no tan negro, conservando el contraste con la pared
	# (RingHub_DomeShell, albedo 0.1/0.16/0.19).
	material.albedo_color = Color(0.40, 0.42, 0.44)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	for ring in range(RINGS):
		var r0: float = RADIUS * float(ring) / RINGS
		var r1: float = RADIUS * float(ring + 1) / RINGS
		for seg in range(SEGMENTS):
			var a0: float = TAU * float(seg) / SEGMENTS
			var a1: float = TAU * float(seg + 1) / SEGMENTS
			# Winding CCW visto desde arriba (normal +Y).
			_quad(st,
				_p(r0, a0), _p(r0, a1), _p(r1, a1), _p(r1, a0))
	st.index()
	var out := ArrayMesh.new()
	st.commit(out)

	out.take_over_path(OUT_MESH)
	var err := ResourceSaver.save(OUT_MESH, out)
	if err != OK:
		push_error("[bake_ringhub_floor] fallo guardando: %s" % err)
		quit(1)
		return
	print("[bake_ringhub_floor] OK: aabb=%s, %d triangulos" % [
		out.get_aabb(), out.surface_get_array_index_len(0) / 3])
	quit(0)


func _p(radius: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


# El centro degenera a triangulo (r0 == 0): ese quad se emite como un solo tri.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if a.is_equal_approx(b):
		_tri(st, a, c, d)
		return
	_tri(st, a, b, c)
	_tri(st, a, c, d)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, c, b]:
		st.add_normal(Vector3.UP)
		st.add_uv(Vector2(v.x, v.z) / 4.0)
		st.add_uv2(Vector2(v.x, v.z) / (2.0 * RADIUS) + Vector2(0.5, 0.5))
		st.add_vertex(v)
