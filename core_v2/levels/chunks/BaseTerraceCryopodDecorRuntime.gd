tool
extends Spatial

export(String, FILE, "*.tres") var layout_resource_path := "res://core_v2/levels/chunks/BaseTerraceCryopodDecorLayout.tres"
export(PackedScene) var source_pod_scene = preload("res://core_v2/props/CriopodParallaxDecor.tscn")
export(bool) var build_person_card_lod := true
export(int, 3, 24) var person_card_radial_segments := 6
export(bool) var build_runtime_colliders := true
export(bool) var build_single_combined_collider := false
export(int, 0, 1200) var startup_wait_max_frames := 720
export(int) var collision_layer := 64
export(int) var collision_mask := 255

const SHELL_BATCH_NAME := "CryopodShellBatch"
const GLASS_BATCH_NAME := "CryopodGlassBatch"
const PERSON_CARD_BATCH_NAME := "_CryopodPersonCardLOD"
const COLLIDER_NAME := "CryopodDecorCollider"
const PERSON_CARD_LOCAL_TRANSFORM := Transform(
	Vector3(1, -1.50996e-07, -1.05697e-07),
	Vector3(-1.50996e-07, -1, -7.32463e-08),
	Vector3(-1.50996e-07, 1.04638e-07, -0.7),
	Vector3(0, 1.40804, -0.114267)
)
const PILOT_MATERIAL = preload("res://core_v2/props/parallax_assets/pilot_material.tres")

var _layout = null
var _shell_mesh: Mesh = null
var _glass_mesh: Mesh = null
var _shell_material: Material = null
var _glass_material: Material = null
var _glass_transform := Transform.IDENTITY
var _local_combined_aabb := AABB()
var _shell_cast_shadow := GeometryInstance.SHADOW_CASTING_SETTING_ON
var _glass_cast_shadow := GeometryInstance.SHADOW_CASTING_SETTING_ON
var _shell_layers := 1
var _glass_layers := 1
var _shell_use_in_baked_light := true
var _glass_use_in_baked_light := true

func _ready() -> void:
	_clear_generated_children()
	_layout = load(layout_resource_path)
	if _layout == null:
		push_error("CryopodDecorRuntime could not load layout: %s" % layout_resource_path)
		return
	if not _capture_source_resources():
		return
	_build_shell_batch()
	_build_glass_batch()
	if build_person_card_lod:
		_build_person_card_batch()
	if Engine.editor_hint:
		return
	if build_runtime_colliders:
		call_deferred("_build_runtime_collider_when_ready")

func _clear_generated_children() -> void:
	for name in [SHELL_BATCH_NAME, GLASS_BATCH_NAME, PERSON_CARD_BATCH_NAME, COLLIDER_NAME]:
		var node = get_node_or_null(name)
		if node:
			node.free()

func _build_runtime_collider_when_ready() -> void:
	if get_node_or_null(COLLIDER_NAME):
		return
	var session = get_node_or_null("/root/SessionManager")
	if session and session.has_method("is_startup_gate_open") and not bool(session.is_startup_gate_open()):
		if session.has_method("wait_until_startup_gate_open"):
			var wait_state = session.wait_until_startup_gate_open(startup_wait_max_frames)
			if wait_state is GDScriptFunctionState:
				yield(wait_state, "completed")
	_build_runtime_collider()

func _build_runtime_collider() -> void:
	if _layout == null:
		return
	if build_single_combined_collider:
		var combined_aabb: AABB = _layout.combined_aabb
		if combined_aabb.size == Vector3.ZERO:
			return
		var body := StaticBody.new()
		body.name = COLLIDER_NAME
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		var collision_shape := CollisionShape.new()
		var shape := BoxShape.new()
		shape.extents = combined_aabb.size * 0.5
		collision_shape.shape = shape
		collision_shape.transform.origin = combined_aabb.position + (combined_aabb.size * 0.5) + _layout.runtime_origin_offset
		body.add_child(collision_shape)
		add_child(body)
		return

	if _local_combined_aabb.size == Vector3.ZERO:
		return
	var collider_root := Spatial.new()
	collider_root.name = COLLIDER_NAME
	add_child(collider_root)

	var shared_shape := BoxShape.new()
	shared_shape.extents = _local_combined_aabb.size * 0.5
	var local_center := _local_combined_aabb.position + (_local_combined_aabb.size * 0.5)

	for i in range(_layout.pod_transforms.size()):
		var body := StaticBody.new()
		body.name = "CryopodCollider%d" % i
		body.transform = _apply_runtime_offset(_layout.pod_transforms[i])
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask

		var collision_shape := CollisionShape.new()
		collision_shape.shape = shared_shape
		collision_shape.transform.origin = local_center
		body.add_child(collision_shape)
		collider_root.add_child(body)

func _build_shell_batch() -> void:
	_create_batch(
		SHELL_BATCH_NAME,
		_shell_mesh,
		_shell_material,
		_get_runtime_pod_transforms(),
		_shell_cast_shadow,
		_shell_layers,
		_shell_use_in_baked_light
	)

func _build_glass_batch() -> void:
	var transforms := []
	for pod_transform in _get_runtime_pod_transforms():
		transforms.append(pod_transform * _glass_transform)
	_create_batch(
		GLASS_BATCH_NAME,
		_glass_mesh,
		_glass_material,
		transforms,
		_glass_cast_shadow,
		_glass_layers,
		_glass_use_in_baked_light
	)

func _build_person_card_batch() -> void:
	var mesh := CylinderMesh.new()
	mesh.material = PILOT_MATERIAL
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 1.369
	mesh.radial_segments = person_card_radial_segments
	mesh.rings = 0
	var transforms := []
	for pod_transform in _get_runtime_pod_transforms():
		transforms.append(pod_transform * PERSON_CARD_LOCAL_TRANSFORM)
	var person_card_batch := _create_batch(
		PERSON_CARD_BATCH_NAME,
		mesh,
		null,
		transforms,
		GeometryInstance.SHADOW_CASTING_SETTING_OFF,
		_shell_layers,
		false
	)
	if person_card_batch:
		person_card_batch.set("flags_do_not_receive_shadows", true)

func _create_batch(
	name: String,
	mesh: Mesh,
	material: Material,
	transforms: Array,
	cast_shadow: int,
	layers: int,
	use_in_baked_light: bool
) -> MultiMeshInstance:
	if mesh == null or transforms.empty():
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance.new()
	instance.name = name
	instance.multimesh = multimesh
	instance.cast_shadow = cast_shadow
	instance.layers = layers
	instance.set("use_in_baked_light", use_in_baked_light)
	if material:
		instance.material_override = material
	add_child(instance)
	return instance

func _capture_source_resources() -> bool:
	if source_pod_scene == null:
		push_error("CryopodDecorRuntime has no source_pod_scene.")
		return false
	var pod_root = source_pod_scene.instance()
	if pod_root == null:
		push_error("CryopodDecorRuntime could not instance source_pod_scene.")
		return false
	_shell_mesh = pod_root.get("mesh")
	if pod_root is MeshInstance:
		var shell_instance := pod_root as MeshInstance
		_shell_material = _get_instance_material(shell_instance, 0)
		_shell_cast_shadow = shell_instance.cast_shadow
		_shell_layers = shell_instance.layers
		_shell_use_in_baked_light = shell_instance.use_in_baked_light
	var glass = pod_root.get_node_or_null("Glass")
	if glass and glass is MeshInstance:
		var glass_instance := glass as MeshInstance
		_glass_mesh = glass_instance.mesh
		_glass_material = _get_instance_material(glass_instance, 0)
		_glass_transform = glass_instance.transform
		_glass_cast_shadow = glass_instance.cast_shadow
		_glass_layers = glass_instance.layers
		_glass_use_in_baked_light = glass_instance.use_in_baked_light
	_local_combined_aabb = _compute_local_combined_aabb(pod_root, glass)
	pod_root.free()
	return _shell_mesh != null and _glass_mesh != null

func _get_instance_material(instance: MeshInstance, surface_index: int) -> Material:
	var material = instance.get_surface_material(surface_index)
	if material:
		return material
	if instance.mesh and surface_index < instance.mesh.get_surface_count():
		return instance.mesh.surface_get_material(surface_index)
	return null

func _get_runtime_pod_transforms() -> Array:
	var adjusted := []
	for pod_transform in _layout.pod_transforms:
		adjusted.append(_apply_runtime_offset(pod_transform))
	return adjusted

func _apply_runtime_offset(pod_transform: Transform) -> Transform:
	var adjusted := pod_transform
	adjusted.origin += _layout.runtime_origin_offset
	return adjusted

func _compute_local_combined_aabb(pod_root: Node, glass: Node) -> AABB:
	var has_aabb := false
	var combined := AABB()
	if pod_root is MeshInstance:
		var shell := pod_root as MeshInstance
		if shell.mesh:
			combined = shell.mesh.get_aabb()
			has_aabb = true
	if glass and glass is MeshInstance:
		var glass_instance := glass as MeshInstance
		if glass_instance.mesh:
			var glass_aabb := _transform_aabb(glass_instance.mesh.get_aabb(), glass_instance.transform)
			combined = glass_aabb if not has_aabb else combined.merge(glass_aabb)
			has_aabb = true
	return combined if has_aabb else AABB()

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
