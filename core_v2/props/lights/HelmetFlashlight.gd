extends Spatial

export(bool) var enabled := true setget set_enabled
export(float, 0.5, 5.9) var spot_range := 5.9 setget set_spot_range
export(float, 10.0, 90.0) var spot_angle := 50.0 setget set_spot_angle
export(Color) var light_color := Color(0.85, 0.95, 1.0, 1.0) setget set_light_color
export(float, 0.0, 16.0) var light_energy := 7.0 setget set_light_energy
export(bool) var scan_mode := false setget set_scan_mode
export(float, 0.1, 10.0) var scan_speed := 2.0
export(bool) var shadow_enabled := false setget set_shadow_enabled
export(Texture) var mask_texture: Texture = preload("res://core_v2/props/lights/HelmetFlashlightMask.png")
export(Vector2) var mask_tiling := Vector2(1.0, 4.0)
export(NodePath) var skeleton_path := NodePath("Visual/Pivot/Skeleton/Skinned_Mesh_0/Skeleton")
export(NodePath) var visual_pivot_path := NodePath("Visual/Pivot")
export(String) var mount_bone := "DEF-shoulderR"
# Offset sobre el hueso, en espacio del cuerpo (X = lateral, Y = arriba, Z = adelante).
export(Vector3) var mount_offset := Vector3(0.0, 0.1, 0.06)
# Adelanta la SpotLight (no el nodo: el mesh emisivo se queda en el hombro). Si la luz
# nace dentro del mesh, sus poligonos proyectan sombras propias sobre toda la escena.
export(float) var muzzle_offset := 0.3
# Igual que el laser: no dejar que la linterna apunte hacia atras a traves del cuerpo.
export(float) var min_aim_dot := 0.1

onready var _spot_light: SpotLight = $SpotLight
onready var _volumetric_cone: MeshInstance = $VolumetricCone
onready var _emitter: MeshInstance = $Emitter

var _material: ShaderMaterial = null
var _scroll_offset: float = 0.0
var _skeleton: Skeleton = null
var _mount_bone_idx: int = -1
var _visual_pivot: Spatial = null


func _ready() -> void:
	if _volumetric_cone and _volumetric_cone.get_surface_material(0):
		_material = _volumetric_cone.get_surface_material(0).duplicate()
		_volumetric_cone.set_surface_material(0, _material)

	var owner_node := get_parent()
	if owner_node:
		var skel = owner_node.get_node_or_null(skeleton_path)
		if skel is Skeleton:
			_skeleton = skel
			_mount_bone_idx = skel.find_bone(mount_bone)
		_visual_pivot = owner_node.get_node_or_null(visual_pivot_path) as Spatial

	_apply_light_params()
	_update_cone_transform()
	set_enabled(enabled)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flashlight"):
		toggle()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	if not enabled:
		return

	_update_mount()

	if scan_mode:
		_scroll_offset += delta * scan_speed
		if _material:
			_material.set_shader_param("mask_scroll", _scroll_offset)


func _update_mount() -> void:
	if _skeleton == null or _mount_bone_idx < 0:
		return
	var camera := get_viewport().get_camera()
	if camera == null:
		return

	# El modelo mira hacia +Z del pivot (misma convencion que _get_multi_tool_forward).
	var body_forward: Vector3 = -global_transform.basis.z.normalized()
	var body_basis := Basis()
	if _visual_pivot and is_instance_valid(_visual_pivot):
		body_basis = _visual_pivot.global_transform.basis
		body_forward = body_basis.z.normalized()

	var origin: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_mount_bone_idx)).origin
	origin += body_basis.orthonormalized().xform(mount_offset)

	var center: Vector2 = get_viewport().size * 0.5
	var aim_dir: Vector3 = camera.project_ray_normal(center).normalized()
	if aim_dir.dot(body_forward) < min_aim_dot:
		aim_dir = body_forward

	var t := Transform(global_transform.basis, origin)
	global_transform = t.looking_at(origin + aim_dir, Vector3.UP)


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(val: bool) -> void:
	enabled = val
	if is_inside_tree():
		if _spot_light:
			_spot_light.visible = enabled
		if _volumetric_cone:
			_volumetric_cone.visible = enabled
		if _emitter:
			_emitter.visible = enabled
		set_process(enabled)


func set_spot_range(val: float) -> void:
	# Enforce MobileLightBudget contract: spot_range must stay < 6.0m
	spot_range = clamp(val, 0.5, 5.9)
	if is_inside_tree():
		_apply_light_params()
		_update_cone_transform()


func set_spot_angle(val: float) -> void:
	spot_angle = clamp(val, 10.0, 90.0)
	if is_inside_tree():
		_apply_light_params()
		_update_cone_transform()


func set_light_color(val: Color) -> void:
	light_color = val
	if is_inside_tree():
		_apply_light_params()


func set_light_energy(val: float) -> void:
	light_energy = val
	if is_inside_tree():
		_apply_light_params()


func set_scan_mode(val: bool) -> void:
	scan_mode = val
	if is_inside_tree() and _material:
		_material.set_shader_param("use_mask", scan_mode)


func set_shadow_enabled(val: bool) -> void:
	shadow_enabled = val
	if is_inside_tree() and _spot_light:
		_spot_light.shadow_enabled = shadow_enabled


func _apply_light_params() -> void:
	if _spot_light:
		_spot_light.translation = Vector3(0.0, 0.0, -muzzle_offset)
		_spot_light.spot_range = spot_range
		_spot_light.spot_angle = spot_angle
		_spot_light.light_color = light_color
		_spot_light.light_energy = light_energy
		_spot_light.shadow_enabled = shadow_enabled

	if _material:
		_material.set_shader_param("color", light_color)
		_material.set_shader_param("use_mask", scan_mode)
		if mask_texture:
			_material.set_shader_param("mask", mask_texture)
		_material.set_shader_param("mask_tiling", mask_tiling)


func _update_cone_transform() -> void:
	if not _volumetric_cone:
		return

	var radius: float = tan(deg2rad(spot_angle * 0.5)) * spot_range
	# CylinderMesh height is along local Y (before X-rotation), so scale Y is spot_range
	_volumetric_cone.scale = Vector3(radius, spot_range, radius)
	# +90 deja el ápice (top_radius = 0) en el casco y la base ancha lejos.
	_volumetric_cone.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_volumetric_cone.translation = Vector3(0.0, 0.0, -muzzle_offset - spot_range * 0.5)
