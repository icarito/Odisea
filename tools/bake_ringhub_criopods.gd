extends SceneTree

# bake_ringhub_criopods.gd — FD-314: hornea el anillo de criopods decorativos de
# RingHub a un visual MultiMesh (3 capas: shell / glass / cards) + una escena de
# colision con una caja por pod, lista para streamear por chunk.
#
# Por que MultiMesh y no la malla fusionada del baker de Dome_Intro: el pod
# funcional de despertar ocupa un slot elegido por run_seed, asi que hace falta
# poder ocultar/mover UNA instancia del pod decorativo (y liberar SU caja de
# colision) sin tocar el resto. Una ArrayMesh fusionada no permite eso.
#
# Salida:
#   core_v2/levels/interiors/RingHub_Criopod_{shell,glass,cards}.mesh   (1 pod por capa)
#   core_v2/levels/interiors/RingHub_Criopod_{shell,glass}.material
#   core_v2/levels/chunks/ringhub/RingHub_Criopods_visual.tscn
#   core_v2/levels/chunks/ringhub/RingHub_Criopods_body.tscn
#
# Run: ODISEA_BAKE_SOURCE=... (opcional) tools/godot --path . --no-window -s tools/bake_ringhub_criopods.gd

const DEFAULT_SOURCE_PATH := "res://core_v2/levels/interiors/RingHub_CriopodsSource.tscn"
const OUT_DIR := "res://core_v2/levels/interiors/"
const CHUNK_DIR := "res://core_v2/levels/chunks/ringhub/"
const PREFIX := "RingHub"
const VISUAL_SCRIPT := "res://core_v2/levels/chunks/ringhub/CriopodRingVisualV2.gd"
const BODY_SCRIPT := "res://core_v2/levels/chunks/ringhub/CriopodRingCollisionV2.gd"
const SLOT_PROVIDER_PATH := NodePath("../../Criopods_Visual")

const LAYER_SHELL := {"path": ".", "name": "shell", "node": "Shell"}
const LAYER_GLASS := {"path": "Interior/Glass", "name": "glass", "node": "Glass"}
const LAYER_CARDS := {"path": "PersonCard2", "name": "cards", "node": "PersonCards"}
const LAYERS := [LAYER_SHELL, LAYER_GLASS, LAYER_CARDS]

var _shared_materials := {}
var _ring_name := "Criopods1"
var _output_suffix := ""
var _output_ring_name := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dither = get_root().get_node_or_null("PropDitherManager")
	if dither != null:
		dither.set_process(false)
		if is_connected("node_added", dither, "_on_node_added"):
			disconnect("node_added", dither, "_on_node_added")
	var gate = get_root().get_node_or_null("GLES3VendorGate")
	if gate != null and gate.has_method("suspend_node_mutation"):
		gate.suspend_node_mutation()

	var source_path: String = OS.get_environment("ODISEA_BAKE_SOURCE")
	if source_path.empty():
		source_path = DEFAULT_SOURCE_PATH
	_ring_name = OS.get_environment("ODISEA_BAKE_RING")
	if _ring_name.empty():
		_ring_name = "Criopods1"
	_output_suffix = OS.get_environment("ODISEA_BAKE_SUFFIX")
	_output_ring_name = OS.get_environment("ODISEA_BAKE_OUTPUT_RING")
	if _output_ring_name.empty():
		_output_ring_name = _ring_name
	var packed: PackedScene = load(source_path)
	if packed == null:
		push_error("[bake_ringhub_criopods] no pude cargar %s" % source_path)
		quit(1)
		return
	var root: Node = packed.instance()
	get_root().add_child(root)
	var ring: Spatial = root.get_node_or_null("Spatial/" + _ring_name) as Spatial
	if ring == null:
		push_error("[bake_ringhub_criopods] no encuentro Spatial/%s en %s" % [_ring_name, source_path])
		quit(1)
		return

	var items := []
	for child in ring.get_children():
		if child is Spatial:
			items.append(child)
	if items.empty():
		push_error("[bake_ringhub_criopods] el anillo no tiene items")
		quit(1)
		return

	var to_ring: Transform = ring.global_transform.affine_inverse()
	var slot_to_index := _slot_to_index(items)
	if not _bake_visual(ring, items, to_ring, slot_to_index):
		quit(1)
		return
	if not _bake_collision(ring, items, to_ring, slot_to_index):
		quit(1)
		return
	print("[bake_ringhub_criopods] %d pods, visual + colision OK" % items.size())
	quit(0)


func _bake_visual(ring: Spatial, items: Array, to_ring: Transform, slot_to_index: Array) -> bool:
	var visual := Spatial.new()
	visual.name = "CriopodRingVisual"
	visual.set_script(load(VISUAL_SCRIPT))
	var ring_node := Spatial.new()
	ring_node.name = _output_ring_name
	ring_node.transform = ring.transform
	visual.add_child(ring_node)
	ring_node.owner = visual

	for layer in LAYERS:
		var sample: MeshInstance = _layer_node(items[0], layer.path)
		if sample == null or sample.mesh == null:
			push_error("[bake_ringhub_criopods] no encuentro capa %s" % layer.path)
			return false

		# Malla de UN pod por capa, guardada aparte para que el MultiMesh la
		# referencie por ruta en vez de embeberla. Las tarjetas son un
		# CylinderMesh (PrimitiveMesh), que no se puede guardar con extension
		# .mesh; va como .tres.
		var mesh_ext: String = ".mesh" if sample.mesh is ArrayMesh else ".tres"
		var mesh_path: String = OUT_DIR + PREFIX + "_Criopod_" + layer.name + mesh_ext
		if ResourceSaver.save(mesh_path, sample.mesh) != OK:
			push_error("[bake_ringhub_criopods] no pude guardar %s" % mesh_path)
			return false
		var mesh_ref: Mesh = load(mesh_path)

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh_ref
		multimesh.instance_count = items.size()
		for i in range(items.size()):
			var layer_node: MeshInstance = _layer_node(items[i], layer.path)
			if layer_node == null or not layer_node.visible:
				multimesh.set_instance_transform(i, Transform(Basis(), Vector3(0.0, -10000.0, 0.0)))
				continue
			multimesh.set_instance_transform(i, to_ring * layer_node.global_transform)

		var instance := MultiMeshInstance.new()
		instance.name = layer.node
		instance.layers = 64
		instance.cast_shadow = sample.cast_shadow
		instance.use_in_baked_light = true
		instance.multimesh = multimesh
		instance.material_override = _shared_material(_active_material(sample, 0), layer.name)
		ring_node.add_child(instance)
		instance.owner = visual

	visual.set("slot_to_instance", slot_to_index)

	var packed := PackedScene.new()
	if packed.pack(visual) != OK:
		push_error("[bake_ringhub_criopods] no pude empacar el visual")
		return false
	var visual_path := _output_path("visual")
	if ResourceSaver.save(visual_path, packed) != OK:
		push_error("[bake_ringhub_criopods] no pude guardar %s" % visual_path)
		return false
	return true


func _bake_collision(ring: Spatial, items: Array, to_ring: Transform, slot_to_index: Array) -> bool:
	var collision_root := Spatial.new()
	collision_root.name = "CriopodRingCollision"
	collision_root.set_script(load(BODY_SCRIPT))
	collision_root.set("slot_provider_path", SLOT_PROVIDER_PATH)
	collision_root.set("body_path", _output_ring_name + "/StaticBody")
	collision_root.set("slot_to_pod", slot_to_index)
	var ring_node := Spatial.new()
	ring_node.name = _output_ring_name
	ring_node.transform = ring.transform
	collision_root.add_child(ring_node)
	ring_node.owner = collision_root
	var body := StaticBody.new()
	body.name = "StaticBody"
	body.collision_layer = 64
	body.collision_mask = 255
	ring_node.add_child(body)
	body.owner = collision_root

	var shapes: Array = []
	for item in items:
		var source_shape: CollisionShape = item.get_node_or_null("StaticBody/CollisionShape")
		if source_shape == null or source_shape.shape == null:
			push_error("[bake_ringhub_criopods] cada pod requiere una caja")
			return false
		shapes.append(source_shape)
	if shapes.empty():
		push_error("[bake_ringhub_criopods] ningun pod aporto colision")
		return false

	for pod_index in range(shapes.size()):
		var source_shape: CollisionShape = shapes[pod_index]
		var cs := CollisionShape.new()
		cs.name = "Pod_%02d" % pod_index
		cs.transform = to_ring * source_shape.global_transform
		cs.shape = source_shape.shape
		body.add_child(cs)
		cs.owner = collision_root

	var packed := PackedScene.new()
	if packed.pack(collision_root) != OK:
		push_error("[bake_ringhub_criopods] no pude empacar la colision")
		return false
	var body_path := _output_path("body")
	if ResourceSaver.save(body_path, packed) != OK:
		push_error("[bake_ringhub_criopods] no pude guardar %s" % body_path)
		return false
	return true


func _output_path(kind: String) -> String:
	return CHUNK_DIR + "RingHub_Criopods%s_%s.tscn" % [_output_suffix, kind]


# Slot del RadialScatter (Item_N) -> indice de instancia/caja. Los slots sin pod
# quedan en -1.
func _slot_to_index(items: Array) -> Array:
	var size := 0
	for item in items:
		size = int(max(size, _slot_of(item.name) + 1))
	var mapping := []
	for _i in range(size):
		mapping.append(-1)
	for i in range(items.size()):
		var slot := _slot_of(items[i].name)
		if slot >= 0:
			mapping[slot] = i
	return mapping


func _slot_of(node_name: String) -> int:
	if not node_name.begins_with("Item_"):
		return -1
	return int(node_name.substr(5))


func _layer_node(item: Node, path: String) -> MeshInstance:
	if path == ".":
		return item as MeshInstance
	return item.get_node_or_null(path) as MeshInstance


func _active_material(mi: MeshInstance, surface_index: int) -> Material:
	var mat: Material = mi.get_surface_material(surface_index)
	if mat == null and mi.mesh != null:
		mat = mi.mesh.surface_get_material(surface_index)
	if mat == null:
		mat = mi.material_override
	return mat


func _shared_material(mat: Material, layer_name: String) -> Material:
	if mat == null:
		return null
	if mat.resource_path != "" and mat.resource_path.find("::") < 0:
		return mat
	var signature: String = _material_signature(mat)
	if not _shared_materials.has(signature):
		var path: String = OUT_DIR + PREFIX + "_Criopod_" + layer_name + ".material"
		if ResourceSaver.save(path, mat) != OK:
			push_error("[bake_ringhub_criopods] no pude guardar %s" % path)
			return mat
		_shared_materials[signature] = load(path)
	return _shared_materials[signature]


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
