tool
extends Spatial

export(NodePath) var scatter_path := NodePath("Scatter3D2")
export(NodePath) var bake_source_root_path := NodePath("CrioBatch")
export(bool) var build_person_card_lod := true
export(int, 3, 24) var person_card_radial_segments := 6
export(bool) var build_runtime_colliders := true
export(bool) var build_single_combined_collider := true
export(int, 0, 1200) var startup_wait_max_frames := 720
export(int) var collision_layer := 64
export(int) var collision_mask := 255
export(Vector3) var baked_runtime_origin_offset := Vector3(0, -0.838061, 0)
export(String, FILE, "*.scn,*.tscn") var baked_scene_output_path := "res://core_v2/levels/chunks/BaseTerraceCryopodDecorBaked.scn"
export(String, FILE, "*.tres") var layout_resource_output_path := "res://core_v2/levels/chunks/BaseTerraceCryopodDecorLayout.tres"
export(bool) var editor_auto_bake_on_change := false
export(bool) var editor_bake_now := false setget _set_editor_bake_now

const COLLIDER_CONTAINER_NAME := "_DeferredCryopodColliders"
const PERSON_CARD_CONTAINER_NAME := "_CryopodPersonCardLOD"
const BAKED_SHELL_BATCH_NAME := "CryopodShellBatch"
const BAKED_GLASS_BATCH_NAME := "CryopodGlassBatch"
const BAKED_COLLIDER_NAME := "CryopodDecorCollider"
const PERSON_CARD_LOCAL_TRANSFORM := Transform(
	Vector3(1, -1.50996e-07, -1.05697e-07),
	Vector3(-1.50996e-07, -1, -7.32463e-08),
	Vector3(-1.50996e-07, 1.04638e-07, -0.7),
	Vector3(0, 1.40804, -0.114267)
)
const PILOT_MATERIAL = preload("res://core_v2/props/parallax_assets/pilot_material.tres")
const CryopodDecorLayoutResource = preload("res://core_v2/levels/chunks/CryopodDecorLayoutResource.gd")

var _editor_is_baking := false
var _editor_last_signature := ""

func _ready() -> void:
	if Engine.editor_hint:
		_editor_last_signature = _compute_editor_signature()
		set_process(editor_auto_bake_on_change)
		return
	if build_person_card_lod:
		_build_person_card_lod_mesh()
	if not build_runtime_colliders:
		return
	call_deferred("_build_runtime_colliders_when_ready")

func _process(_delta: float) -> void:
	if not Engine.editor_hint:
		set_process(false)
		return
	if not editor_auto_bake_on_change or _editor_is_baking:
		return
	var current_signature := _compute_editor_signature()
	if current_signature == "" or current_signature == _editor_last_signature:
		return
	_editor_last_signature = current_signature
	call_deferred("_run_editor_bake")

func _build_runtime_colliders_when_ready() -> void:
	if get_node_or_null(COLLIDER_CONTAINER_NAME):
		return
	var session = get_node_or_null("/root/SessionManager")
	if session and session.has_method("is_startup_gate_open") and not bool(session.is_startup_gate_open()):
		if session.has_method("wait_until_startup_gate_open"):
			var wait_state = session.wait_until_startup_gate_open(startup_wait_max_frames)
			if wait_state is GDScriptFunctionState:
				yield(wait_state, "completed")
	_build_runtime_colliders()

func _build_runtime_colliders() -> void:
	var entries = _get_runtime_pod_entries()
	if entries.empty():
		return

	if build_single_combined_collider:
		var combined_aabb = _compute_entries_aabb(entries)
		if combined_aabb == null:
			return
		var collider = _create_combined_collider(combined_aabb)
		collider.name = COLLIDER_CONTAINER_NAME
		add_child(collider)
		return

	var shared_shape = _create_shared_shape(_extract_pods(entries))
	if shared_shape == null:
		return
	var collider_root := Spatial.new()
	collider_root.name = COLLIDER_CONTAINER_NAME
	add_child(collider_root)
	for entry in entries:
		var pod: MeshInstance = entry["pod"]
		var body := StaticBody.new()
		body.name = "%sCollider" % pod.name
		body.transform = entry["transform"]
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		var collision_shape := CollisionShape.new()
		collision_shape.shape = shared_shape
		body.add_child(collision_shape)
		collider_root.add_child(body)

func _build_person_card_lod_mesh() -> void:
	if get_node_or_null(PERSON_CARD_CONTAINER_NAME):
		return
	var entries = _get_runtime_pod_entries()
	if entries.empty():
		return

	var mesh := CylinderMesh.new()
	mesh.material = PILOT_MATERIAL
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 1.369
	mesh.radial_segments = person_card_radial_segments
	mesh.rings = 0

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = entries.size()

	for i in range(entries.size()):
		multimesh.set_instance_transform(i, entries[i]["transform"] * PERSON_CARD_LOCAL_TRANSFORM)

	var multimesh_instance := MultiMeshInstance.new()
	multimesh_instance.name = PERSON_CARD_CONTAINER_NAME
	multimesh_instance.multimesh = multimesh
	add_child(multimesh_instance)

func _create_shared_shape(pods: Array) -> Shape:
	for pod in pods:
		if pod.mesh:
			return pod.mesh.create_trimesh_shape()
	return null

func _get_scatter_pods(scatter: Spatial) -> Array:
	var pods := []
	for child in scatter.get_children():
		if child is MeshInstance:
			var pod := child as MeshInstance
			if pod.mesh:
				pods.append(pod)
	return pods

func _get_pod_chunk_transform(scatter: Spatial, pod: Spatial) -> Transform:
	return scatter.transform * pod.transform

func _get_runtime_pod_entries() -> Array:
	var scatter = get_node_or_null(scatter_path)
	if scatter:
		var entries := []
		for pod in _get_scatter_pods(scatter):
			entries.append({
				"pod": pod,
				"transform": _get_pod_chunk_transform(scatter, pod)
			})
		return entries
	var source_root = get_node_or_null(bake_source_root_path)
	if source_root == null:
		return []
	var entries := []
	for pod in _get_bake_source_pods(source_root):
		entries.append({
			"pod": pod,
			"transform": _get_local_transform_to_root(pod)
		})
	return entries

func bake_baked_scene_copy() -> bool:
	var source_root = get_node_or_null(bake_source_root_path)
	if source_root == null:
		push_error("CryopodDecor bake source root not found: %s" % bake_source_root_path)
		return false

	var pods = _get_bake_source_pods(source_root)
	if pods.empty():
		push_error("CryopodDecor bake source has no pod instances.")
		return false

	var shell_mesh: Mesh = null
	var glass_mesh: Mesh = null
	var shell_material: Material = null
	var glass_material: Material = null
	var shell_transforms := []
	var glass_transforms := []
	var person_card_transforms := []
	var combined_aabb = _compute_entries_aabb(_build_entries_from_pods(pods))
	if combined_aabb == null:
		push_error("CryopodDecor bake could not compute combined AABB.")
		return false

	for pod in pods:
		if shell_mesh == null:
			shell_mesh = pod.mesh
			shell_material = _get_instance_material(pod, 0)
		var pod_transform := _get_local_transform_to_root(pod)
		shell_transforms.append(pod_transform)
		person_card_transforms.append(pod_transform * PERSON_CARD_LOCAL_TRANSFORM)

		var glass = pod.get_node_or_null("Glass")
		if glass and glass is MeshInstance:
			var glass_mesh_instance := glass as MeshInstance
			if glass_mesh == null:
				glass_mesh = glass_mesh_instance.mesh
				glass_material = _get_instance_material(glass_mesh_instance, 0)
			if glass_mesh_instance.mesh:
				var glass_transform := _get_local_transform_to_root(glass_mesh_instance)
				glass_transforms.append(glass_transform)

	var baked_root := Spatial.new()
	baked_root.name = "CryopodDecorBaked"
	_add_owned_child(baked_root, _create_baked_batch(BAKED_SHELL_BATCH_NAME, shell_mesh, shell_material, shell_transforms))
	_add_owned_child(baked_root, _create_baked_batch(BAKED_GLASS_BATCH_NAME, glass_mesh, glass_material, glass_transforms))
	_add_owned_child(baked_root, _create_person_card_batch(person_card_transforms))
	_add_owned_child(baked_root, _create_combined_collider(combined_aabb))

	var packed_scene := PackedScene.new()
	var pack_err := packed_scene.pack(baked_root)
	if pack_err != OK:
		push_error("CryopodDecor bake pack failed: %d" % pack_err)
		baked_root.free()
		return false
	var save_err := ResourceSaver.save(baked_scene_output_path, packed_scene)
	baked_root.free()
	if save_err != OK:
		push_error("CryopodDecor bake save failed: %d -> %s" % [save_err, baked_scene_output_path])
		return false
	return true

func bake_layout_resource() -> bool:
	var source_root = get_node_or_null(bake_source_root_path)
	if source_root == null:
		push_error("CryopodDecor layout bake source root not found: %s" % bake_source_root_path)
		return false
	var pods = _get_bake_source_pods(source_root)
	if pods.empty():
		push_error("CryopodDecor layout bake source has no pod instances.")
		return false
	var entries = _build_entries_from_pods(pods)
	var combined_aabb = _compute_entries_aabb(entries)
	if combined_aabb == null:
		push_error("CryopodDecor layout bake could not compute combined AABB.")
		return false
	var layout = CryopodDecorLayoutResource.new()
	layout.pod_transforms = []
	for entry in entries:
		layout.pod_transforms.append(entry["transform"])
	layout.combined_aabb = combined_aabb
	layout.runtime_origin_offset = baked_runtime_origin_offset
	var save_err := ResourceSaver.save(layout_resource_output_path, layout)
	if save_err != OK:
		push_error("CryopodDecor layout bake save failed: %d -> %s" % [save_err, layout_resource_output_path])
		return false
	return true

func _set_editor_bake_now(value: bool) -> void:
	editor_bake_now = value
	if not value or not Engine.editor_hint or _editor_is_baking:
		return
	call_deferred("_run_editor_bake")

func _run_editor_bake() -> void:
	if _editor_is_baking:
		return
	_editor_is_baking = true
	var ok_layout := bake_layout_resource()
	var ok_scene := bake_baked_scene_copy()
	var ok := ok_layout and ok_scene
	if ok:
		_editor_last_signature = _compute_editor_signature()
	editor_bake_now = false
	_editor_is_baking = false
	property_list_changed_notify()

func _compute_editor_signature() -> String:
	var source_root = get_node_or_null(bake_source_root_path)
	if source_root == null:
		return ""
	var chunks := []
	for pod in _get_bake_source_pods(source_root):
		chunks.append(pod.name)
		chunks.append(var2str(_get_local_transform_to_root(pod)))
	return "|".join(chunks)

func _get_bake_source_pods(source_root: Node) -> Array:
	var pods := []
	for child in source_root.get_children():
		if child is MeshInstance:
			var pod := child as MeshInstance
			if pod.mesh:
				pods.append(pod)
	return pods

func _build_entries_from_pods(pods: Array) -> Array:
	var entries := []
	for pod in pods:
		entries.append({
			"pod": pod,
			"transform": _get_local_transform_to_root(pod)
		})
	return entries

func _create_baked_batch(name: String, mesh: Mesh, material: Material, transforms: Array) -> MultiMeshInstance:
	var instance := MultiMeshInstance.new()
	instance.name = name
	if mesh == null or transforms.empty():
		return instance
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	instance.multimesh = multimesh
	if material:
		instance.material_override = material
	return instance

func _create_person_card_batch(transforms: Array) -> MultiMeshInstance:
	var mesh := CylinderMesh.new()
	mesh.material = PILOT_MATERIAL
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 1.369
	mesh.radial_segments = person_card_radial_segments
	mesh.rings = 0
	return _create_baked_batch(PERSON_CARD_CONTAINER_NAME, mesh, null, transforms)

func _create_combined_collider(combined_aabb: AABB) -> StaticBody:
	var body := StaticBody.new()
	body.name = BAKED_COLLIDER_NAME
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	var collision_shape := CollisionShape.new()
	var shape := BoxShape.new()
	shape.extents = combined_aabb.size * 0.5
	collision_shape.shape = shape
	collision_shape.transform.origin = combined_aabb.position + (combined_aabb.size * 0.5)
	body.add_child(collision_shape)
	collision_shape.owner = body
	return body

func _compute_entries_aabb(entries: Array):
	var has_aabb := false
	var combined_aabb: AABB
	for entry in entries:
		var pod: MeshInstance = entry["pod"]
		var pod_transform: Transform = entry["transform"]
		if pod.mesh:
			var pod_aabb := _transform_aabb(pod.mesh.get_aabb(), pod_transform)
			combined_aabb = pod_aabb if not has_aabb else combined_aabb.merge(pod_aabb)
			has_aabb = true
		var glass = pod.get_node_or_null("Glass")
		if glass and glass is MeshInstance:
			var glass_mesh_instance := glass as MeshInstance
			if glass_mesh_instance.mesh:
				var glass_transform := pod_transform * glass_mesh_instance.transform
				var glass_aabb := _transform_aabb(glass_mesh_instance.mesh.get_aabb(), glass_transform)
				combined_aabb = glass_aabb if not has_aabb else combined_aabb.merge(glass_aabb)
				has_aabb = true
	return combined_aabb if has_aabb else null

func _extract_pods(entries: Array) -> Array:
	var pods := []
	for entry in entries:
		pods.append(entry["pod"])
	return pods

func _get_instance_material(instance: MeshInstance, surface_index: int) -> Material:
	var material = instance.get_surface_material(surface_index)
	if material:
		return material
	if instance.mesh and surface_index < instance.mesh.get_surface_count():
		return instance.mesh.surface_get_material(surface_index)
	return null

func _get_local_transform_to_root(node: Spatial) -> Transform:
	var transform_accum := Transform.IDENTITY
	var current: Spatial = node
	while current and current != self:
		transform_accum = current.transform * transform_accum
		current = current.get_parent() as Spatial
	return transform_accum

func _transform_aabb(aabb: AABB, transform: Transform) -> AABB:
	var corners = [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z),
	]
	var transformed = AABB(transform.xform(corners[0]), Vector3.ZERO)
	for i in range(1, corners.size()):
		transformed = transformed.expand(transform.xform(corners[i]))
	return transformed

func _add_owned_child(owner_root: Node, child: Node) -> void:
	owner_root.add_child(child)
	child.owner = owner_root
