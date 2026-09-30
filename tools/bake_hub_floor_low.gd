extends SceneTree

# bake_hub_floor_low.gd — HORNEA las variantes LOW de los pisos del hub de RingHub
# (FD-316 tarea Z). En el Anbernic cada piso son 3 MeshInstance (los tercios
# angulares horneados) x 5 superficies = 15 draws; 5 pisos = 75 de los 108 draws
# por frame del censo 406a5d9e.
#
# Este tool NO regenera geometria: lee los tercios horneados de alta calidad
# (RingHub_Floor_N_third_K.mesh, producto de `make bake-ringhub-hub`) y colapsa las
# 5 superficies de cada uno (rejilla del deck, lados del deck, marco, baranda y
# franja) en UNA sola superficie con el color representativo de cada material
# horneado en vertex colors. Producto: RingHub_Floor_N_low_K.mesh (1 superficie).
#
# Por que no se re-deriva del generador parametrico (ScaffoldHubRing.build()): el
# lightmap de RingHub.lmbake guarda, por nodo CombinedMesh*, su propio StreamTexture
# y su rect en user_data. Los UV2 horneados de estos tercios son los que muestrean
# esa textura. Conservando los UV2 vertex a vertex (merge, no regen) la variante LOW
# sigue recibiendo la luz cocinada identica; regenerar la malla cambiaria el unwrap
# y la iluminacion del piso. Se preservan los UV2 y se descartan UV1/tangentes
# (el material LOW no tiene textura ni normal map).
#
# Idempotente: siempre lee los tercios de alta y escribe los _low_K; volver a
# correr `make bake-ringhub-hub` (que reescribe los de alta) exige re-correr este
# tool para refrescar los LOW.
#
# Run: tools/godot --path . --no-window -s tools/bake_hub_floor_low.gd
#   (o el binario resuelto por tools/godot_bin.sh, como el resto de los bakes)

const DIR := "res://core_v2/levels/interiors/"
const PREFIX := "RingHub"
const FLOORS := 5
const CHUNKS := 3

# Color de la franja de peligro: su material es un ShaderMaterial (seam_road_lines)
# que pinta las rayas con textura, asi que no hay albedo_color legible. Se ha
# fallback a amarillo de seguridad, igual criterio que GLES3VendorGate._palette_color.
const HAZARD_FALLBACK := Color(0.85, 0.62, 0.12, 1.0)

var _mat_low: SpatialMaterial = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_mat_low = _make_low_material()
	var mat_path: String = DIR + "RingHub_HubFloorLow.material"
	if ResourceSaver.save(mat_path, _mat_low) != OK:
		push_error("[bake_floor_low] no pude guardar %s" % mat_path)
		quit(1)
		return
	_mat_low = load(mat_path)
	for floor_index in range(1, FLOORS + 1):
		for chunk in range(CHUNKS):
			if not _bake_chunk(floor_index, chunk):
				quit(1)
				return
	quit(0)

func _bake_chunk(floor_index: int, chunk: int) -> bool:
	var src_path: String = DIR + "%s_Floor_%d_third_%d.mesh" % [PREFIX, floor_index, chunk]
	var out_path: String = DIR + "%s_Floor_%d_low_%d.mesh" % [PREFIX, floor_index, chunk]
	var high: ArrayMesh = load(src_path) as ArrayMesh
	if high == null:
		push_error("[bake_floor_low] no encuentro %s" % src_path)
		return false

	var low := _merge_surfaces(high)
	if low == null or low.get_surface_count() == 0:
		push_error("[bake_floor_low] merge vacio para %s" % src_path)
		return false
	low.surface_set_material(0, _mat_low)
	# UV2 que consume el lightmap horneado del nodo (ver cabecera). No tocar.
	low.lightmap_size_hint = high.lightmap_size_hint
	if ResourceSaver.save(out_path, low) != OK:
		push_error("[bake_floor_low] no pude guardar %s" % out_path)
		return false

	print("[bake_floor_low] %s: %d superficies / %d verts -> %d superficie / %d verts (%s)" % [
		src_path.get_file(), high.get_surface_count(), _vertex_count(high),
		low.get_surface_count(), _vertex_count(low), out_path.get_file()])
	return true

# Suma todas las superficies en un unico SurfaceTool con el color de cada material
# por vertice. Expande indices a lista de triangulos y deja que index() vuelva a
# unir vertices iguales (posicion+normal+uv2+color): baja el conteo de vertices sin
# cambiar la silueta.
func _merge_surfaces(src: ArrayMesh) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_normals := true
	for surface in range(src.get_surface_count()):
		var arrays: Array = src.surface_get_arrays(surface)
		if arrays == null or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PoolVector3Array()
		if normals.size() != vertices.size():
			has_normals = false
		var uv2: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PoolVector2Array()
		var indices := PoolIntArray()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var color: Color = _surface_color(src.surface_get_material(surface), surface)
		var triangle_vertices: int = indices.size() if not indices.empty() else vertices.size()
		for i in range(0, triangle_vertices, 3):
			for corner in range(3):
				var vertex_index: int = indices[i + corner] if not indices.empty() else i + corner
				tool.add_color(color)
				if uv2.size() == vertices.size():
					tool.add_uv2(uv2[vertex_index])
				if normals.size() == vertices.size():
					tool.add_normal(normals[vertex_index])
				tool.add_vertex(vertices[vertex_index])
	if not has_normals:
		tool.generate_normals()
	tool.index()
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	return mesh

# Color plano de la superficie. SpatialMaterial: su albedo. ShaderMaterial de la
# franja: no expone albedo_color legible, va el amarillo de seguridad.
func _surface_color(material: Material, surface_index: int) -> Color:
	if material is SpatialMaterial:
		var albedo: Color = (material as SpatialMaterial).albedo_color
		if albedo.a < 0.05:
			albedo.a = 1.0
		return Color(albedo.r, albedo.g, albedo.b, 1.0)
	if material is ShaderMaterial:
		var shader := material as ShaderMaterial
		for name in ["albedo_color", "base_color", "color", "tint_color"]:
			var value = shader.get_shader_param(name)
			if value is Color and (value as Color).a > 0.05:
				var c := value as Color
				return Color(c.r, c.g, c.b, 1.0)
	return HAZARD_FALLBACK if surface_index >= 4 else Color(0.3, 0.32, 0.35, 1.0)

# Material unico de la variante: sin textura ni normal map, opaco (en LOW el gate
# apaga transparencia/alpha scissor igual), doble cara porque el deck horneado trae
# winding invertido y vertex colors como albedo.
func _make_low_material() -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.resource_name = "M_HubFloorLow"
	material.vertex_color_use_as_albedo = true
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	material.metallic = 0.5
	material.roughness = 0.65
	material.metallic_specular = 0.5
	return material

func _vertex_count(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays != null and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
	return total
