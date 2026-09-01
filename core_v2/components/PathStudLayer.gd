tool
extends Spatial
class_name PathStudLayer

# PathStudLayer.gd - Procedural reflective road-stud layer for LightPathV2 / Path routes.
# Generates a single MultiMeshInstance of flattened beveled stud meshes (< 200 triangles).
# State behavior:
#   FULL (2): Subtle emissive core on all studs.
#   LOW_POWER (1): Every Nth stud emissive with a slow blink pattern.
#   DARK (0): No emission, metallic base + fresnel rim only.

enum LightState {
	DARK = 0,
	LOW_POWER = 1,
	FULL = 2
}

export(LightState) var light_state: int = LightState.FULL setget set_light_state
export(NodePath) var target_path_node: NodePath setget set_target_path_node
export(Color) var lit_color := Color(0.4, 0.85, 1.0, 1.0) setget set_lit_color
export(Color) var base_color := Color(0.2, 0.22, 0.25, 1.0) setget set_base_color
export(int, 2, 10) var low_power_stride := 3 setget set_low_power_stride
export(float, 0.1, 5.0) var blink_speed := 1.5

var _multimesh_instance: MultiMeshInstance = null
var _stud_mesh: Mesh = null
var _stud_material: SpatialMaterial = null
var _transforms: Array = []
var _blink_timer: float = 0.0

func _ready() -> void:
	if _stud_mesh == null:
		_stud_mesh = generate_stud_mesh()
	if _stud_material == null:
		_stud_material = create_stud_material()

	_ensure_multimesh_instance()
	rebuild_from_target()
	_update_stud_colors()

func set_light_state(value: int) -> void:
	light_state = value
	if is_inside_tree():
		_update_stud_colors()
		set_process(light_state == LightState.LOW_POWER)

func set_target_path_node(value: NodePath) -> void:
	target_path_node = value
	if is_inside_tree():
		rebuild_from_target()

func set_lit_color(value: Color) -> void:
	lit_color = value
	if is_inside_tree():
		_update_stud_colors()

func set_base_color(value: Color) -> void:
	base_color = value
	if is_inside_tree():
		_update_stud_colors()

func set_low_power_stride(value: int) -> void:
	low_power_stride = max(1, value)
	if is_inside_tree():
		_update_stud_colors()

func _process(delta: float) -> void:
	if light_state != LightState.LOW_POWER:
		return
	_blink_timer += delta * blink_speed
	_update_stud_colors()

func rebuild_from_target() -> void:
	var points_or_xforms := []

	var target: Node = null
	if target_path_node != NodePath() and has_node(target_path_node):
		target = get_node(target_path_node)
	elif get_parent() is Spatial:
		target = get_parent()

	if target:
		if target is MultiMeshInstance and target.multimesh:
			var mm: MultiMesh = target.multimesh
			for i in range(mm.instance_count):
				var xf: Transform = mm.get_instance_transform(i)
				var world_pos: Vector3 = target.global_transform.xform(xf.origin)
				points_or_xforms.append(global_transform.affine_inverse().xform(world_pos))
		elif target.has_node("Markers"):
			var markers: MultiMeshInstance = target.get_node("Markers") as MultiMeshInstance
			if markers and markers.multimesh:
				var mm: MultiMesh = markers.multimesh
				for i in range(mm.instance_count):
					var xf: Transform = mm.get_instance_transform(i)
					var world_pos: Vector3 = markers.global_transform.xform(xf.origin)
					points_or_xforms.append(global_transform.affine_inverse().xform(world_pos))
		elif target is Path and target.curve:
			var curve: Curve3D = target.curve
			var baked_len: float = curve.get_baked_length()
			var step: float = 2.0
			var count: int = int(baked_len / step) + 1
			for i in range(count):
				var offset: float = float(i) * step
				var pos: Vector3 = curve.interpolate_baked(offset)
				var world_pos: Vector3 = target.global_transform.xform(pos)
				points_or_xforms.append(global_transform.affine_inverse().xform(world_pos))
		else:
			for child in target.get_children():
				if child is Position3D or (child is Spatial and not child is MultiMeshInstance):
					var world_pos: Vector3 = child.global_transform.origin
					points_or_xforms.append(global_transform.affine_inverse().xform(world_pos))

	set_positions(points_or_xforms)

func set_positions(positions: Array) -> void:
	_transforms.clear()
	for pos in positions:
		if pos is Vector3:
			_transforms.append(Transform(Basis(), pos))
		elif pos is Transform:
			_transforms.append(pos)
	_rebuild_multimesh()

func set_transforms(transforms: Array) -> void:
	_transforms = transforms.duplicate()
	_rebuild_multimesh()

func _ensure_multimesh_instance() -> void:
	if _multimesh_instance == null or not is_instance_valid(_multimesh_instance):
		_multimesh_instance = get_node_or_null("StudMultiMesh") as MultiMeshInstance
		if _multimesh_instance == null:
			_multimesh_instance = MultiMeshInstance.new()
			_multimesh_instance.name = "StudMultiMesh"
			add_child(_multimesh_instance)

func _rebuild_multimesh() -> void:
	_ensure_multimesh_instance()
	if _transforms.empty():
		if _multimesh_instance.multimesh:
			_multimesh_instance.multimesh.instance_count = 0
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_8BIT
	mm.mesh = _stud_mesh
	mm.instance_count = _transforms.size()

	for i in range(_transforms.size()):
		mm.set_instance_transform(i, _transforms[i])
		mm.set_instance_color(i, base_color)

	_multimesh_instance.multimesh = mm
	_multimesh_instance.material_override = _stud_material
	_multimesh_instance.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_update_stud_colors()

func _update_stud_colors() -> void:
	_ensure_multimesh_instance()
	if _multimesh_instance == null or _multimesh_instance.multimesh == null:
		return

	var mm: MultiMesh = _multimesh_instance.multimesh
	var count: int = mm.instance_count
	if count == 0:
		return

	match light_state:
		LightState.DARK:
			for i in range(count):
				mm.set_instance_color(i, base_color)
		LightState.FULL:
			for i in range(count):
				mm.set_instance_color(i, lit_color)
		LightState.LOW_POWER:
			var pulse: float = (sin(_blink_timer * TAU) * 0.5 + 0.5)
			var active_color: Color = base_color.linear_interpolate(lit_color, 0.3 + pulse * 0.7)
			for i in range(count):
				if i % low_power_stride == 0:
					mm.set_instance_color(i, active_color)
				else:
					mm.set_instance_color(i, base_color)

# Generates flattened hemisphere / beveled disc mesh (< 200 triangles)
# Radius = 0.14m, Height = 0.04m. 8 radial segments x 3 rings = 48 triangles.
# Bumped up from the original 0.08m/0.025m (FD-285 spec): at that size the stud was
# smaller than a single grate-deck cell and read as invisible in actual play.
static func generate_stud_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radial_segments := 8
	var rings := 3
	var radius := 0.14
	var height := 0.04

	for r in range(rings + 1):
		var v_ratio := float(r) / float(rings)
		var ring_angle := v_ratio * (PI * 0.5)
		var ring_y := cos(ring_angle) * height
		var ring_r := sin(ring_angle) * radius

		for s in range(radial_segments):
			var u_ratio := float(s) / float(radial_segments)
			var rad_angle := u_ratio * TAU
			var x := cos(rad_angle) * ring_r
			var z := sin(rad_angle) * ring_r

			var norm := Vector3(x, ring_y * 2.0, z).normalized()
			st.add_normal(norm)
			st.add_uv(Vector2(u_ratio, v_ratio))
			st.add_vertex(Vector3(x, ring_y, z))

	for r in range(rings):
		for s in range(radial_segments):
			var next_s := (s + 1) % radial_segments
			var current_row := r * radial_segments
			var next_row := (r + 1) * radial_segments

			var i0 := current_row + s
			var i1 := current_row + next_s
			var i2 := next_row + s
			var i3 := next_row + next_s

			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)

			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)

	return st.commit()

# Material: Opaque metallic base + GLES2-safe fresnel rim
static func create_stud_material() -> SpatialMaterial:
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.metallic = 0.6
	mat.roughness = 0.3
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.8, 1.0)
	# 0.5 read as basically off against the deck's own texture/ambient in play; a
	# fresnel-only rim on a metallic disc needs a strong push to read at a glance.
	mat.emission_energy = 3.0
	mat.emission_on_uv2 = false
	return mat
