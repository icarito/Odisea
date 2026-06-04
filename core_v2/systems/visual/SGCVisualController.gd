extends Spatial
class_name SGCVisualController

# FD-052: SGC Cylindrical Projection Visual Controller
# ScaffoldStreamController always sets material_override on its MultiMeshInstances
# (in _add_lod_multimesh). We intercept child_entered_tree on every chunk and
# replace that override with the warp shader material.

export(Array, NodePath) var scaffold_stream_roots: Array = []

export(float, 0.0, 1.0) var transition_blend: float = 1.0  setget set_transition_blend
export(float)            var rotation_speed:   float = 0.0  setget set_rotation_speed
export(float)            var base_radius:       float = 190.0 setget set_base_radius

var _warp_shader: Shader
var _materials: Array = []

func _ready() -> void:
	_warp_shader = load("res://shaders/sgc_cylindrical_warp.shader") as Shader
	if not _warp_shader:
		push_error("SGCVisualController: sgc_cylindrical_warp.shader not found")
		return
	call_deferred("_connect_streams")

func _connect_streams() -> void:
	for np in scaffold_stream_roots:
		var node = get_node_or_null(np)
		if node == null:
			push_warning("SGCVisualController: no node at path %s" % np)
			continue
		node.connect("child_entered_tree", self, "_on_stream_child_entered")

func _on_stream_child_entered(child: Node) -> void:
	if not child.name.begins_with("Chunk"):
		return
	# LOD MultiMeshInstances are added synchronously inside _on_chunk_generated.
	# We arrive here right after add_child(chunk_node), so the LOD nodes are
	# already children of the chunk.
	_wrap_chunk(child)
	# Also catch full-detail MeshInstances added later by the threaded instancer
	child.connect("child_entered_tree", self, "_on_chunk_child_entered")

func _on_chunk_child_entered(node: Node) -> void:
	if node is MultiMeshInstance:
		_override(node as MultiMeshInstance)
	elif node is MeshInstance:
		_override_mi(node as MeshInstance)

func _wrap_chunk(chunk: Node) -> void:
	for child in chunk.get_children():
		if child is MultiMeshInstance:
			_override(child as MultiMeshInstance)
		elif child is MeshInstance:
			_override_mi(child as MeshInstance)

func _override(mmi: MultiMeshInstance) -> void:
	var mat := _make_material()
	mmi.material_override = mat
	_materials.append(mat)

func _override_mi(mi: MeshInstance) -> void:
	var mat := _make_material()
	mi.material_override = mat
	_materials.append(mat)

func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _warp_shader
	_push_uniforms(mat)
	return mat

# ── Setters ────────────────────────────────────────────────────────────────

func set_transition_blend(v: float) -> void:
	transition_blend = clamp(v, 0.0, 1.0)
	_set_param("transition_blend", transition_blend)

func set_rotation_speed(v: float) -> void:
	rotation_speed = v
	_set_param("rotation_speed", rotation_speed)

func set_base_radius(v: float) -> void:
	base_radius = v
	_set_param("base_radius", base_radius)

func animate_to_cylinder(duration: float) -> void:
	var t := _make_tween()
	t.interpolate_property(self, "transition_blend",
		transition_blend, 1.0, duration, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	t.start()

func animate_to_flat(duration: float) -> void:
	var t := _make_tween()
	t.interpolate_property(self, "transition_blend",
		transition_blend, 0.0, duration, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	t.start()

# ── Helpers ────────────────────────────────────────────────────────────────

func _push_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_param("transition_blend", transition_blend)
	mat.set_shader_param("rotation_speed",   rotation_speed)
	mat.set_shader_param("base_radius",      base_radius)
	mat.set_shader_param("debug_theta",      0)

func _set_param(param: String, value) -> void:
	var live := []
	for mat in _materials:
		if is_instance_valid(mat):
			(mat as ShaderMaterial).set_shader_param(param, value)
			live.append(mat)
	_materials = live

func _make_tween() -> Tween:
	var t := Tween.new()
	add_child(t)
	return t
