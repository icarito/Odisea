extends SceneTree

# bake_ringhub_floor.gd — Hornea el piso de RingHub_Level a .mesh.
#
# Reemplaza al CSGBox de 50x50 que habia antes: no llegaba al borde del domo
# (dejaba un anillo negro entre r=25 y r=35), se teselaba en runtime y no tenia
# UV2, asi que no podia entrar en el lightmap.
#
# El disco comparte el numero de radiales con DomeInteriorLowPoly (16), asi que
# el borde del piso cae exactamente sobre la base del domo: sin costura visible.
# El material es la variante desktop (RingHub_Floor_desktop.tres, PBR con textura
# tiled): se embebe una copia para que el .mesh se vea bien solo, aunque la escena
# y RingHubFloorMaterial.gd usan el .tres como fuente de verdad.
#
# UV1 = (x, z)/4: planar, una repeticion cada 4 m. Es lo que consume el material
# texturado (uv1_scale lo reescala). UV2 = planar [0,1] sobre el disco: es lo que
# consume BakedLightmap.
#
# Ademas del disco hornea una capa de JUNTAS EMISIVAS (RingHub_Floor_joints_baked.mesh):
# lineas finas sobre las juntas del patron de Rusty Metal Grid, para que el piso tenga
# una referencia visual cuando el ambiente esta a oscuras (DARK) y en el camino plano
# low-end, donde no hay luces. La textura repite cada 8 m (uv1_scale 0.5 sobre UV1 =
# world/4) y sus juntas caen a 1/6, 1/2 y 5/6 del tile en ambos ejes; las lineas se
# alinean a esas fracciones. La separacion en runtime la hace RingHubFloorMaterial.gd.
#
# Run: tools/godot --path . --no-window -s tools/bake_ringhub_floor.gd
# Output: core_v2/levels/RingHub_Floor_baked.mesh
#         core_v2/levels/RingHub_Floor_joints_baked.mesh  (sin material embebido:
#         el .tres RingHub_Floor_joints.tres es la fuente de verdad en runtime)

const RADIUS := 35.0
const SEGMENTS := 16
const RINGS := 4
const MATERIAL_SRC := "res://core_v2/levels/interiors/RingHub_Floor_desktop.tres"
const OUT_MESH := "res://core_v2/levels/RingHub_Floor_baked.mesh"
# Juntas: mundo por repeticion de la textura y fracciones de junta dentro del tile.
const JOINT_TILE := 8.0
const JOINT_FRACS := [1.0 / 6.0, 0.5, 5.0 / 6.0]
const JOINT_WIDTH := 0.06
const JOINT_Y := 0.012
const OUT_JOINTS := "res://core_v2/levels/RingHub_Floor_joints_baked.mesh"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var src: Material = load(MATERIAL_SRC)
	if src == null or not (src is SpatialMaterial):
		push_error("[bake_ringhub_floor] no pude leer el material de %s" % MATERIAL_SRC)
		quit(1)
		return
	# Copia: la escena usa el .tres compartido, el mesh solo guarda su propia
	# version embebida para verse bien abierto solo.
	var material: SpatialMaterial = (src as SpatialMaterial).duplicate()
	material.resource_name = "M_RingHubFloor"

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
	_bake_joints()
	quit(0)


# Capa de juntas emisivas: lineas finas sobre las juntas del patron de la textura.
# Sin material embebido a proposito: en runtime RingHubFloorMaterial.gd le pone
# material_override = RingHub_Floor_joints.tres, asi el .tres es la fuente de verdad
# (y el gate lo aplana/ilumina igual que cualquier otro nodo, porque mira el override).
func _bake_joints() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = JOINT_WIDTH * 0.5
	for k in range(-6, 6):
		for frac in JOINT_FRACS:
			var o: float = JOINT_TILE * (float(k) + float(frac))
			if abs(o) >= RADIUS - JOINT_WIDTH:
				continue
			var reach: float = sqrt(RADIUS * RADIUS - o * o)
			# Linea a lo largo de Z (junta vertical del patron)...
			_line(st, Vector3(o, JOINT_Y, -reach), Vector3(o, JOINT_Y, reach), hw)
			# ...y a lo largo de X (junta horizontal).
			_line(st, Vector3(-reach, JOINT_Y, o), Vector3(reach, JOINT_Y, o), hw)
	st.index()
	var out := ArrayMesh.new()
	st.commit(out)
	out.take_over_path(OUT_JOINTS)
	var err := ResourceSaver.save(OUT_JOINTS, out)
	if err != OK:
		push_error("[bake_ringhub_floor] fallo guardando juntas: %s" % err)
		return
	print("[bake_ringhub_floor] juntas OK: aabb=%s, %d triangulos" % [
		out.get_aabb(), out.surface_get_array_index_len(0) / 3])


# Quad de ancho 2*hw centrado en el segmento [from, to], normal +Y. La cull esta
# deshabilitada en el material, asi que el winding no importa.
func _line(st: SurfaceTool, from: Vector3, to: Vector3, hw: float) -> void:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	var p := Vector2(-d.y, d.x) * hw
	var a := from + Vector3(p.x, 0.0, p.y)
	var b := to + Vector3(p.x, 0.0, p.y)
	var c := to - Vector3(p.x, 0.0, p.y)
	var e := from - Vector3(p.x, 0.0, p.y)
	_quad(st, a, b, c, e)


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
