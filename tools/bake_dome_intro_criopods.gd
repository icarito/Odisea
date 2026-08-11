extends SceneTree

# bake_dome_intro_criopods.gd — Hornea los seis anillos de criopods de Dome_Intro a
# mallas estaticas en disco, una por anillo y por capa.
#
# ANTES: los 218 criopods vivian como escenas instanciadas dentro del .tscn (1332
# nodos, 218 StaticBody) y RadialScatter los batcheaba a MultiMeshInstance en CADA
# carga de la escena, por call_deferred. O sea: el .tscn guardaba las posiciones
# horneadas pero la geometria dibujable se rearmaba en runtime, y los nodos
# originales quedaban vivos "para colision e interaccion" — pero los criopods de
# Dome_Intro no son interactuables, solo son un muro de cajas.
#
# DESPUES: una ArrayMesh por anillo y por capa (carcasa / vidrio / tarjeta del
# piloto), mas UN StaticBody por anillo con las 37 cajas colgando. Mismo dibujo,
# mismas colisiones, sin nodos ni trabajo de arranque.
#
# Por que TRES mallas por anillo y no una con tres superficies: cada capa tiene que
# seguir siendo su propio nodo porque el pipeline de materiales trabaja por NODO, no
# por superficie. La tarjeta del piloto esta en el grupo "no_occlusion" (PropDitherManager
# la saltea), la carcasa si se convierte al shader de dither y encima recibe el
# next_pass de hielo, y el vidrio es transparente asi que _can_apply_occlusion_dither
# lo rechaza. Metidas en un solo nodo, las tres compartirian el destino de la primera.
#
# Los materiales se guardan UNA vez y se referencian desde los seis anillos (mismo
# motivo que en bake_dome_intro_hub_floors.gd: seis copias privadas del mismo material
# son seis conversiones distintas en PropDitherManager y seis escrituras por frame en
# vez de una, ademas de cero batching entre anillos).
#
# Salida:
#   core_v2/levels/interiors/DomeIntro_Criopods<N>_{shell,glass,cards}.mesh
#   core_v2/levels/interiors/DomeIntro_Criopod_{shell,glass}.material
#   core_v2/levels/interiors/DomeIntro_Criopod_box.shape
#   core_v2/levels/interiors/DomeIntro_Criopods.nodes  (fragmento .tscn, ver
#     tools/splice_criopod_bake.py — este script NO toca la escena)
#
# Run: godot3-bin --no-window -s tools/bake_dome_intro_criopods.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const OUT_DIR := "res://core_v2/levels/interiors/"
const FRAGMENT_PATH := OUT_DIR + "DomeIntro_Criopods.nodes"

# Ruta relativa dentro del criopod -> nombre de la capa horneada. El orden importa
# solo para que el fragmento salga legible.
const LAYERS := [
	{"path": ".", "name": "shell", "node": "Shell", "no_occlusion": false},
	{"path": "Interior/Glass", "name": "glass", "node": "Glass", "no_occlusion": false},
	{"path": "PersonCard2", "name": "cards", "node": "PersonCards", "no_occlusion": true},
]

var _shared_materials := {}  # firma de contenido -> ruta del .material en disco
var _box_shape_path := ""
var _fragment := PoolStringArray()
var _ext_resources := []  # rutas en orden de aparicion, para el splicer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("[bake_criopods] no pude cargar %s" % SCENE_PATH)
		quit(1)
		return

	# Mismo motivo que en bake_dome_intro_hub_floors.gd: con PropDitherManager activo
	# lo que se leeria son sus ShaderMaterial de runtime, no los materiales autorizados.
	# Lo mismo vale para el freezer, que encadena el overlay de hielo como next_pass.
	var dither = get_root().get_node_or_null("PropDitherManager")
	if dither != null:
		dither.set_process(false)
		if is_connected("node_added", dither, "_on_node_added"):
			disconnect("node_added", dither, "_on_node_added")

	var root: Node = packed.instance()
	get_root().add_child(root)
	# A proposito NO se espera ningun frame: el batching de RadialScatter entra por
	# call_deferred y aca hacen falta los MeshInstance originales, no los Batched_*.
	var spatial: Node = root.get_node_or_null("Spatial")
	if spatial == null:
		push_error("[bake_criopods] no encuentro el nodo Spatial")
		quit(1)
		return

	var rings := []
	for child in spatial.get_children():
		if child.name.begins_with("Criopods"):
			rings.append(child)
	if rings.empty():
		push_error("[bake_criopods] no encontre anillos Criopods*")
		quit(1)
		return

	for ring in rings:
		if not _bake_ring(ring):
			quit(1)
			return

	_write_fragment()
	quit(0)


func _bake_ring(ring: Spatial) -> bool:
	var items := []
	for child in ring.get_children():
		# Los Batched_* no existen todavia (ver arriba), pero el filtro se deja por si
		# alguna vez se hornea despues de un frame.
		if child is Spatial and not child.name.begins_with("Batched_"):
			items.append(child)
	if items.empty():
		push_error("[bake_criopods] %s no tiene items" % ring.name)
		return false

	var to_ring: Transform = ring.global_transform.affine_inverse()
	var linea := PoolStringArray()
	linea.append("%s: %d pods" % [ring.name, items.size()])

	_fragment.append('[node name="%s" type="Spatial" parent="Spatial"]' % ring.name)
	_fragment.append("transform = %s" % _fmt_transform(ring.transform))
	_fragment.append("")

	for layer in LAYERS:
		var muestra: MeshInstance = _layer_node(items[0], layer.path)
		if muestra == null or muestra.mesh == null:
			push_error("[bake_criopods] %s: no encuentro la capa %s" % [ring.name, layer.path])
			return false

		var merged := ArrayMesh.new()
		for surface_index in range(muestra.mesh.get_surface_count()):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var aportes := 0
			for item in items:
				var mi: MeshInstance = _layer_node(item, layer.path)
				if mi == null or mi.mesh == null or not mi.visible:
					continue
				# append_from transforma vertices, normales Y tangentes. Las tangentes
				# importan: card_parallax.shader calcula el parallax en espacio tangente
				# (TANGENT/BINORMAL/NORMAL), asi que una tangente mal rotada le cambia la
				# direccion de la profundidad a la tarjeta del piloto.
				st.append_from(mi.mesh, surface_index, to_ring * mi.global_transform)
				aportes += 1
			if aportes == 0:
				continue
			var _e = st.commit(merged)
			var mat: Material = _active_material(muestra, surface_index)
			if mat != null:
				merged.surface_set_material(merged.get_surface_count() - 1, _shared_material(mat, layer.name))

		var out_mesh: String = OUT_DIR + "DomeIntro_%s_%s.mesh" % [ring.name, layer.name]
		if ResourceSaver.save(out_mesh, merged) != OK:
			push_error("[bake_criopods] no pude guardar %s" % out_mesh)
			return false

		var verts := 0
		for i in range(merged.get_surface_count()):
			verts += merged.surface_get_array_len(i)
		linea.append("%s=%d verts/%d surf" % [layer.name, verts, merged.get_surface_count()])

		_fragment.append('[node name="%s" type="MeshInstance" parent="Spatial/%s"%s]' % [
			layer.node, ring.name,
			' groups=["no_occlusion"]' if layer.no_occlusion else ""])
		_fragment.append("mesh = ExtResource( %d )" % _ext_id(out_mesh))
		# El horneado de PropDitherManager apaga las sombras al convertir, pero el
		# vidrio y las tarjetas nunca pasan por ahi: se copia lo que tenia el prop.
		if muestra.cast_shadow != GeometryInstance.SHADOW_CASTING_SETTING_ON:
			_fragment.append("cast_shadow = %d" % muestra.cast_shadow)
		if muestra.layers != 1:
			_fragment.append("layers = %d" % muestra.layers)
		_fragment.append("")

	# PoolStringArray es tipo por valor: si _bake_collision recibiera `linea` lo que
	# agregue se pierde al volver. Devuelve la cuenta y se arma el texto aca.
	var cajas: int = _bake_collision(ring, items, to_ring)
	if cajas < 0:
		return false
	linea.append("colision=%d cajas" % cajas)

	print("[bake_criopods] " + linea.join("  "))
	return true


# Una sola StaticBody por anillo, con una CollisionShape por pod colgando.
#
# Fusionar las 37 cajas en un unico ConcavePolygonShape habria dejado 6 nodos en vez
# de 224, pero rompe IceSubmergedCuller: ese sistema decide por forma, usando el radio
# de la esfera que la envuelve (ShapeBounds). Una caja de pod tiene radio ~1 m; el
# trimesh de un anillo entero tendria radio ~12 m, asi que el anillo se declararia
# "todavia al alcance" hasta que el hielo estuviera 12 m por encima y nunca se
# apagaria. Las cajas sueltas conservan el comportamiento exacto de hoy.
func _bake_collision(ring: Spatial, items: Array, to_ring: Transform) -> int:
	var formas := []
	for item in items:
		for body in item.get_children():
			if not (body is StaticBody):
				continue
			for cs in body.get_children():
				if not (cs is CollisionShape) or cs.shape == null:
					continue
				formas.append({
					"xform": to_ring * cs.global_transform,
					"shape": cs.shape,
					"layer": body.collision_layer,
					"mask": body.collision_mask,
				})
	if formas.empty():
		push_error("[bake_criopods] %s: ningun pod aporto colision" % ring.name)
		return -1

	if _box_shape_path == "":
		var path: String = OUT_DIR + "DomeIntro_Criopod_box.shape"
		if ResourceSaver.save(path, formas[0].shape) != OK:
			push_error("[bake_criopods] no pude guardar %s" % path)
			return -1
		_box_shape_path = path

	_fragment.append('[node name="StaticBody" type="StaticBody" parent="Spatial/%s"]' % ring.name)
	_fragment.append("collision_layer = %d" % formas[0].layer)
	_fragment.append("collision_mask = %d" % formas[0].mask)
	_fragment.append("")
	for i in range(formas.size()):
		_fragment.append('[node name="Pod_%02d" type="CollisionShape" parent="Spatial/%s/StaticBody"]' % [
			i, ring.name])
		_fragment.append("transform = %s" % _fmt_transform(formas[i].xform))
		_fragment.append("shape = ExtResource( %d )" % _ext_id(_box_shape_path))
		_fragment.append("")

	return formas.size()


func _layer_node(item: Node, path: String) -> MeshInstance:
	if path == ".":
		return item as MeshInstance
	return item.get_node_or_null(path) as MeshInstance


# El override por instancia gana sobre el material de la malla; los items de Dome_Intro
# traen material/0 propio en el .tscn, asi que leer solo la malla horneaba el material
# equivocado.
func _active_material(mi: MeshInstance, surface_index: int) -> Material:
	var mat: Material = mi.get_surface_material(surface_index)
	if mat == null:
		mat = mi.mesh.surface_get_material(surface_index)
	if mat == null:
		mat = mi.material_override
	return mat


# Un material ya guardado en disco se reusa entre los seis anillos. Si el material ya
# vive en disco (pilot_material.tres) se referencia tal cual.
#
# "En disco" es tener ARCHIVO propio, no tener resource_path: los sub-recursos de una
# escena tambien traen path, con la forma "res://algo.tscn::36". Aceptar esos como si
# fueran archivos hacia que ResourceSaver los embebiera dentro de cada .mesh — seis
# copias privadas del material del vidrio, o sea seis materiales distintos en runtime
# donde deberia haber uno.
func _shared_material(mat: Material, layer_name: String) -> Material:
	if mat.resource_path != "" and mat.resource_path.find("::") < 0:
		return mat
	var firma: String = _material_signature(mat)
	if not _shared_materials.has(firma):
		var path: String = OUT_DIR + "DomeIntro_Criopod_%s.material" % layer_name
		if ResourceSaver.save(path, mat) != OK:
			push_error("[bake_criopods] no pude guardar %s" % path)
			return mat
		_shared_materials[firma] = load(path)
	return _shared_materials[firma]


func _material_signature(mat: Material) -> String:
	var parts := PoolStringArray()
	parts.append(mat.get_class())
	for p in mat.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		if p.name in ["resource_path", "resource_name", "resource_local_to_scene"]:
			continue
		var value = mat.get(p.name)
		if value is Resource:
			parts.append("%s=%s" % [p.name, (value as Resource).resource_path])
		else:
			parts.append("%s=%s" % [p.name, str(value)])
	return parts.join("|")


func _ext_id(path: String) -> int:
	var idx: int = _ext_resources.find(path)
	if idx < 0:
		_ext_resources.append(path)
		idx = _ext_resources.size() - 1
	# Los ids reales los asigna el splicer segun lo que ya haya en la escena; aca se
	# emite un indice 0..N y el splicer lo remapea.
	return idx


func _fmt_transform(t: Transform) -> String:
	var b := t.basis
	return "Transform( %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s )" % [
		_f(b.x.x), _f(b.y.x), _f(b.z.x),
		_f(b.x.y), _f(b.y.y), _f(b.z.y),
		_f(b.x.z), _f(b.y.z), _f(b.z.z),
		_f(t.origin.x), _f(t.origin.y), _f(t.origin.z)]


func _f(v: float) -> String:
	return str(stepify(v, 0.000001))


func _write_fragment() -> void:
	var f := File.new()
	if f.open(FRAGMENT_PATH, File.WRITE) != OK:
		push_error("[bake_criopods] no pude escribir %s" % FRAGMENT_PATH)
		return
	# Cabecera: las rutas que el splicer tiene que dar de alta como ext_resource, en el
	# mismo orden que los indices emitidos arriba.
	for i in range(_ext_resources.size()):
		f.store_line("#ext %d %s" % [i, _ext_resources[i]])
	f.store_line("#endext")
	f.store_string(_fragment.join("\n"))
	f.close()
	print("[bake_criopods] fragmento -> %s (%d ext_resources)" % [
		FRAGMENT_PATH, _ext_resources.size()])
