extends SceneTree

# qodot_audit_props.gd — Censo de props para la integracion Qodot/TrenchBroom.
#
# Para cada .tscn bajo core_v2/props/ mide el AABB REAL (visual + colision) y lista
# los export del script raiz con su default. Es el insumo del audit: el
# meta_properties.size de una point class debe salir de aca y no de un 16^3 generico.
#
# No agrega los nodos al arbol a proposito: instance() no dispara _ready(), asi que
# los props que dependen de autoloads (que no existen bajo `-s`) no revientan.
# El AABB se acumula recorriendo el arbol con la transformada compuesta a mano.
#
# Run: godot3-bin --no-window -s tools/qodot_audit_props.gd
# Salida: /tmp/qodot_props_audit.json  (o $QODOT_AUDIT_OUT)

const PROPS_DIR := "res://core_v2/props"
const DEFAULT_OUT := "/tmp/qodot_props_audit.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var out_path := OS.get_environment("QODOT_AUDIT_OUT")
	if out_path == "":
		out_path = DEFAULT_OUT

	var scenes := []
	_collect(PROPS_DIR, scenes)
	scenes.sort()

	var report := {}
	var pending := []
	for path in scenes:
		var entry := _audit_scene(path)
		report[path] = entry
		# Los props procedurales (andamios, vallas, radiador) construyen su malla en
		# _ready() o por call_deferred, asi que fuera del arbol no miden nada. Solo a
		# esos se les paga el costo de instanciarlos de verdad.
		if entry["aabb_union"].empty() and entry["error"] == "":
			var live_root = _spawn_live(path)
			if live_root != null:
				pending.append([path, live_root])

	# Un par de frames para que corran los call_deferred de construccion.
	for _i in range(4):
		yield(self, "idle_frame")

	for item in pending:
		var path: String = item[0]
		var holder: Spatial = item[1]
		var acc := {"visual": null, "collision": null}
		_walk(holder.get_child(0), Transform.IDENTITY, acc, true)
		var union = _merge(acc["visual"], acc["collision"])
		if union != null:
			report[path]["aabb_visual"] = _aabb_to_array(acc["visual"])
			report[path]["aabb_collision"] = _aabb_to_array(acc["collision"])
			report[path]["aabb_union"] = _aabb_to_array(union)
			report[path]["measured_live"] = true
		holder.queue_free()

	var f := File.new()
	f.open(out_path, File.WRITE)
	f.store_string(JSON.print(report, "  "))
	f.close()
	print("wrote %s (%d scenes)" % [out_path, scenes.size()])
	quit()

func _spawn_live(path: String):
	var packed = load(path)
	if packed == null:
		return null
	var root: Node = packed.instance(PackedScene.GEN_EDIT_STATE_DISABLED)
	if root == null:
		return null
	var holder := Spatial.new()
	get_root().add_child(holder)
	holder.add_child(root)
	return holder

func _collect(dir_path: String, out: Array) -> void:
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return
	d.list_dir_begin(true, true)
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".tscn"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()

func _audit_scene(path: String) -> Dictionary:
	var entry := {
		"error": "",
		"root_class": "",
		"script": "",
		"exports": {},
		"aabb_visual": [],
		"aabb_collision": [],
		"aabb_union": [],
		"measured_live": false,
		"has_activated_signal": false,
		"has_deactivated_signal": false,
	}

	var packed = load(path)
	if packed == null:
		entry["error"] = "load failed"
		return entry

	var root: Node = packed.instance(PackedScene.GEN_EDIT_STATE_DISABLED)
	if root == null:
		entry["error"] = "instance failed"
		return entry

	entry["root_class"] = root.get_class()
	var scr = root.get_script()
	if scr != null:
		entry["script"] = scr.resource_path
		entry["exports"] = _script_exports(root)

	for sig in root.get_signal_list():
		if sig["name"] == "activated":
			entry["has_activated_signal"] = true
		elif sig["name"] == "deactivated":
			entry["has_deactivated_signal"] = true

	var acc := {"visual": null, "collision": null}
	var base := Transform.IDENTITY
	if root is Spatial:
		# La transformada propia de la raiz no cuenta: el AABB se quiere en el
		# espacio local del prop, que es donde TrenchBroom lo va a plantar.
		base = Transform.IDENTITY
	_walk(root, base, acc, true)

	entry["aabb_visual"] = _aabb_to_array(acc["visual"])
	entry["aabb_collision"] = _aabb_to_array(acc["collision"])
	entry["aabb_union"] = _aabb_to_array(_merge(acc["visual"], acc["collision"]))

	root.free()
	return entry

func _script_exports(node: Node) -> Dictionary:
	var res := {}
	for prop in node.get_property_list():
		var usage := int(prop["usage"])
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var name := String(prop["name"])
		if name.begins_with("_"):
			continue
		res[name] = _jsonable(node.get(name))
	return res

func _jsonable(v):
	match typeof(v):
		TYPE_VECTOR3:
			return {"__type": "Vector3", "v": [v.x, v.y, v.z]}
		TYPE_VECTOR2:
			return {"__type": "Vector2", "v": [v.x, v.y]}
		TYPE_COLOR:
			return {"__type": "Color", "v": [v.r, v.g, v.b, v.a]}
		TYPE_NODE_PATH:
			return {"__type": "NodePath", "v": String(v)}
		TYPE_OBJECT:
			if v == null:
				return null
			return {"__type": "Object", "v": v.get_class()}
		TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING:
			return v
		TYPE_ARRAY:
			return {"__type": "Array", "v": v.size()}
		TYPE_DICTIONARY:
			return {"__type": "Dictionary", "v": v.size()}
	return {"__type": "other", "v": typeof(v)}

func _walk(node: Node, parent_xform: Transform, acc: Dictionary, is_root: bool) -> void:
	var xform := parent_xform
	if node is Spatial and not is_root:
		xform = parent_xform * node.transform

	var visual = _visual_aabb(node)
	if visual != null:
		acc["visual"] = _merge(acc["visual"], xform.xform(visual))

	# Solo cuentan las formas de un cuerpo solido. Las de un Area son volumenes de
	# deteccion (el empuje del ventilador, la zona de interaccion) y son un orden de
	# magnitud mas grandes que el prop: meterlas infla la caja de TrenchBroom.
	if node is CollisionShape and node.shape != null and not node.disabled:
		if node.get_parent() is PhysicsBody:
			var shape_aabb = _shape_aabb(node.shape)
			if shape_aabb != null:
				acc["collision"] = _merge(acc["collision"], xform.xform(shape_aabb))

	for child in node.get_children():
		_walk(child, xform, acc, false)

# Devuelve el AABB local que aporta el nodo a la silueta del prop, o null.
# Light/Particles/probes se excluyen a proposito: get_aabb() de una OmniLight
# devuelve su volumen de influencia (decenas de metros), no su cuerpo visible.
func _visual_aabb(node: Node):
	if not (node is Spatial) or not node.visible:
		return null

	if node is Light or node is Particles or node is CPUParticles:
		return null
	if node is GIProbe or node is ReflectionProbe or node is BakedLightmap:
		return null

	# Un CSG restador/intersector no aporta silueta: al reves, suele ser mas grande
	# que el resultado (la caja que perfora el hueco de una puerta). Contarlo infla
	# la caja de la entidad varios metros.
	if node is CSGShape and node.operation != CSGShape.OPERATION_UNION:
		return null

	# Los CSG no evaluan su geometria fuera del arbol, asi que get_aabb() devuelve
	# vacio. Se reconstruye desde los parametros de la primitiva.
	if node is CSGBox:
		var e := Vector3(node.width, node.height, node.depth) * 0.5
		return AABB(-e, e * 2.0)
	if node is CSGSphere:
		var r: float = node.radius
		return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	if node is CSGCylinder:
		var cr: float = node.radius
		var ch: float = node.height * 0.5
		return AABB(Vector3(-cr, -ch, -cr), Vector3(cr * 2.0, ch * 2.0, cr * 2.0))
	if node is CSGTorus:
		var outer: float = node.outer_radius
		var tube: float = (node.outer_radius - node.inner_radius) * 0.5
		return AABB(Vector3(-outer, -tube, -outer), Vector3(outer * 2.0, tube * 2.0, outer * 2.0))
	if node is CSGMesh:
		if node.mesh == null:
			return null
		return node.mesh.get_aabb()
	if node is CSGShape:
		# CSGPolygon / CSGCombiner: sus hijos ya se recorren aparte.
		return null

	if node is MeshInstance:
		if node.mesh == null:
			return null
		return node.mesh.get_aabb()
	if node is MultiMeshInstance:
		if node.multimesh == null:
			return null
		return node.get_aabb()
	if node is SpriteBase3D:
		return node.get_aabb()
	if node is ImmediateGeometry:
		return null

	return null

func _shape_aabb(shape: Shape):
	if shape is BoxShape:
		return AABB(-shape.extents, shape.extents * 2.0)
	if shape is SphereShape:
		var r: float = shape.radius
		return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	if shape is CapsuleShape:
		var r2: float = shape.radius
		var h: float = shape.height * 0.5 + r2
		return AABB(Vector3(-r2, -h, -r2), Vector3(r2 * 2.0, h * 2.0, r2 * 2.0))
	if shape is CylinderShape:
		var r3: float = shape.radius
		var h3: float = shape.height * 0.5
		return AABB(Vector3(-r3, -h3, -r3), Vector3(r3 * 2.0, h3 * 2.0, r3 * 2.0))
	if shape is ConcavePolygonShape:
		return _points_aabb(shape.get_faces())
	if shape is ConvexPolygonShape:
		return _points_aabb(shape.points)
	return null

func _points_aabb(points) -> AABB:
	if points == null or points.size() == 0:
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		box = box.expand(points[i])
	return box

func _merge(a, b):
	if a == null:
		return b
	if b == null:
		return a
	return (a as AABB).merge(b as AABB)

func _aabb_to_array(box) -> Array:
	if box == null:
		return []
	var b := box as AABB
	return [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z]
