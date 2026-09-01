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
export(Color) var lit_color := Color(0.95, 0.25, 0.15, 1.0) setget set_lit_color
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

# Generates a small rectangular frustum (truncated pyramid): wide base, narrower
# flat top, slanted sides. Long axis runs along local X — LightPathV2 orients each
# instance's local Z to the path's tangent (see _update_stud_layer), so a stud
# elongated on X sits crosswise to the corridor, like a real road stud laid across
# the direction of travel rather than a tile running lengthwise with it.
# Base 0.18m x 0.09m, top 0.15m x 0.076m, height 0.018m: low and flat rather than
# a tall dome, closer to a real road-stud's squat profile.
static func generate_stud_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base_x := 0.115
	var base_z := 0.058
	var top_x := 0.095
	var top_z := 0.048
	var height := 0.02

	var base := [
		Vector3(-base_x, 0, -base_z), Vector3(base_x, 0, -base_z),
		Vector3(base_x, 0, base_z), Vector3(-base_x, 0, base_z),
	]
	var top := [
		Vector3(-top_x, height, -top_z), Vector3(top_x, height, -top_z),
		Vector3(top_x, height, top_z), Vector3(-top_x, height, top_z),
	]

	_add_quad(st, top[0], top[1], top[2], top[3], Vector3.UP)
	for i in range(4):
		var j := (i + 1) % 4
		var normal: Vector3 = (base[i] + base[j] - top[i] - top[j]).normalized()
		_add_quad(st, base[i], base[j], top[j], top[i], normal)

	return st.commit()


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	# Standard 0..1 quad UVs regardless of the face's world size, so the reflector
	# texture below reads as a full grid of lens cells on every face instead of a
	# few near-zero texels sampled from the texture's corner.
	var verts := [a, b, c, a, c, d]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(6):
		st.add_normal(normal)
		st.add_uv(uvs[i])
		st.add_vertex(verts[i])

const REFLECTOR_TEXTURE_SIZE := 32
const REFLECTOR_GRID := 4

# Cube-corner reflector sheeting (the "bicycle reflector" look): a tight grid of
# small round lens cells, bright core fading to a dark seam between cells, instead
# of one flat wash of colour. Grayscale so vertex_color_use_as_albedo + emission
# both tint it per light_state without a second texture.
static func create_reflector_texture() -> ImageTexture:
	var image := Image.new()
	image.create(REFLECTOR_TEXTURE_SIZE, REFLECTOR_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.lock()
	var cell: float = float(REFLECTOR_TEXTURE_SIZE) / float(REFLECTOR_GRID)
	for y in range(REFLECTOR_TEXTURE_SIZE):
		for x in range(REFLECTOR_TEXTURE_SIZE):
			var cx: float = fmod(float(x), cell) / cell - 0.5
			var cy: float = fmod(float(y), cell) / cell - 0.5
			var dist: float = Vector2(cx, cy).length() * 2.0
			var level: float = pow(clamp(1.0 - dist, 0.0, 1.0), 1.5)
			# Narrower range than the first pass (was 0.3..1.0): a near-white core
			# next to a near-black seam read as glassy/translucent rather than an
			# opaque moulded-plastic reflector.
			var v: float = lerp(0.42, 0.8, level)
			image.set_pixel(x, y, Color(v, v, v, 1.0))
	image.unlock()
	var texture := ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER | Texture.FLAG_REPEAT)
	return texture

# Material: low-gloss plastic housing + reflector-sheeting texture (albedo AND
# emission), GLES2-safe (opaque, no real transparency).
static func create_stud_material() -> SpatialMaterial:
	var mat := SpatialMaterial.new()
	var reflector := create_reflector_texture()
	mat.flags_unshaded = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.albedo_texture = reflector
	# Road-stud housings are moulded plastic, not chrome: low metallic keeps the
	# flat wash of white/cyan from the old fully-metallic version from clipping.
	mat.metallic = 0.05
	mat.roughness = 0.45
	mat.rim_enabled = true
	mat.rim = 0.2
	mat.rim_tint = 0.5
	mat.emission_enabled = true
	# Fixed material colour, NOT tinted by the per-instance vertex color (that only
	# drives albedo) — it stayed blue even after lit_color changed to red until
	# this got updated too. Matches lit_color's default reflector-red.
	mat.emission = Color(0.95, 0.25, 0.15, 1.0)
	mat.emission_texture = reflector
	# Only the bright lens cells glow — the dark seams between them stay dark —
	# so it reads as a cluster of tiny reflective points instead of one flat glow.
	# 0.2 read as barely-there — the red light nearby didn't visibly trace back to
	# the stud. Middle ground between that and 1.8-3.0, which clipped to a glassy
	# white/washed-out blob.
	mat.emission_energy = 0.7
	mat.emission_on_uv2 = false
	return mat
