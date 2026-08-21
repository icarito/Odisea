tool
extends PropBaseV2
class_name RadiatorProp

# RadiatorProp.gd
# Industrial wall-mounted radiator prop with incandescent heat glow.
# FD-272: Exposes continuous heat_level (0..1) with deterministic emissive visual feedback.

signal heat_level_changed(level)

export(float, 0.0, 1.0) var heat_level: float = 0.0 setget set_heat_level
export(float, 0.1, 5.0) var width: float = 1.2 setget set_width
export(float, 0.1, 5.0) var height: float = 0.8 setget set_height
export(float, 0.05, 1.0) var depth: float = 0.12 setget set_depth
export(int, 2, 32) var fin_count: int = 10 setget set_fin_count
export(float, 0.0, 10.0) var max_emission_energy: float = 4.0 setget set_max_emission_energy

var _mat_duplicated: bool = false
var _frame_mesh_node: MeshInstance = null
var _fins_mesh_node: MeshInstance = null
var _omni_light: OmniLight = null

const EMISSIVE_TRESPATH = "res://core_v2/props/machinery/RadiatorEmissive.tres"

func _init():
	add_to_group("replay_sync")

func _ready():
	._ready()
	if not is_in_group("replay_sync"):
		add_to_group("replay_sync")
	_cache_nodes()
	_update_geometry()
	_update_emissive_material()

func _cache_nodes() -> void:
	_frame_mesh_node = get_node_or_null("FrameMesh") as MeshInstance
	_fins_mesh_node = get_node_or_null("FinsMesh") as MeshInstance
	_omni_light = get_node_or_null("OmniLight") as OmniLight

func set_heat_level(value: float) -> void:
	var clamped: float = clamp(value, 0.0, 1.0)
	var changed: bool = not is_equal_approx(heat_level, clamped)
	heat_level = clamped
	_update_emissive_material()
	if changed:
		emit_signal("heat_level_changed", heat_level)

func set_width(v: float) -> void:
	width = max(v, 0.1)
	if is_inside_tree():
		_update_geometry()

func set_height(v: float) -> void:
	height = max(v, 0.1)
	if is_inside_tree():
		_update_geometry()

func set_depth(v: float) -> void:
	depth = max(v, 0.05)
	if is_inside_tree():
		_update_geometry()

func set_fin_count(v: int) -> void:
	fin_count = int(clamp(v, 2, 32))
	if is_inside_tree():
		_update_geometry()

func set_max_emission_energy(v: float) -> void:
	max_emission_energy = max(v, 0.0)
	if is_inside_tree():
		_update_emissive_material()

func get_heat_color(level: float) -> Color:
	level = clamp(level, 0.0, 1.0)
	if level <= 0.0:
		return Color(0.0, 0.0, 0.0, 1.0)
	elif level < 0.35:
		var t: float = level / 0.35
		return Color(0.0, 0.0, 0.0, 1.0).linear_interpolate(Color(0.85, 0.05, 0.0, 1.0), t)
	elif level < 0.7:
		var t: float = (level - 0.35) / 0.35
		return Color(0.85, 0.05, 0.0, 1.0).linear_interpolate(Color(1.0, 0.4, 0.0, 1.0), t)
	else:
		var t: float = (level - 0.7) / 0.3
		return Color(1.0, 0.4, 0.0, 1.0).linear_interpolate(Color(1.0, 0.85, 0.55, 1.0), t)

func _update_visuals() -> void:
	._update_visuals()
	_update_emissive_material()

func _update_emissive_material() -> void:
	if not is_inside_tree():
		return

	if not _fins_mesh_node:
		_fins_mesh_node = get_node_or_null("FinsMesh") as MeshInstance

	var heat_color: Color = get_heat_color(heat_level)
	var emission_energy: float = heat_level * max_emission_energy

	if _fins_mesh_node:
		var mat = _get_or_create_fins_material()
		if mat is SpatialMaterial:
			mat.emission_enabled = (heat_level > 0.001)
			mat.emission = heat_color
			mat.emission_energy = emission_energy
			if heat_level > 0.001:
				var bright_albedo: Color = Color(0.2, 0.2, 0.2, 1.0).linear_interpolate(heat_color, 0.3)
				mat.albedo_color = bright_albedo
			else:
				mat.albedo_color = Color(0.2, 0.2, 0.2, 1.0)
		elif mat is ShaderMaterial:
			mat.set_shader_param("emission_enabled", heat_level > 0.001)
			mat.set_shader_param("emission_energy", emission_energy)
			mat.set_shader_param("emission_color", heat_color)

	if not _omni_light:
		_omni_light = get_node_or_null("OmniLight") as OmniLight

	if _omni_light:
		_omni_light.visible = (heat_level > 0.01)
		_omni_light.light_color = heat_color
		_omni_light.light_energy = heat_level * 1.5
		_omni_light.omni_range = max(width, height) * 2.5

func _get_or_create_fins_material() -> Material:
	if not _fins_mesh_node:
		return null

	var mat = _fins_mesh_node.material_override
	if not mat:
		mat = _fins_mesh_node.get_surface_material(0)

	if not mat:
		if ResourceLoader.exists(EMISSIVE_TRESPATH):
			mat = load(EMISSIVE_TRESPATH)
		else:
			mat = SpatialMaterial.new()
			mat.emission_enabled = true

	if mat and not _mat_duplicated:
		mat = mat.duplicate()
		_fins_mesh_node.material_override = mat
		_mat_duplicated = true

	return mat

# --- SNAPSHOT SYSTEM (replay_sync) ---

func get_snapshot() -> Dictionary:
	var data: Dictionary = .get_snapshot()
	data["heat_level"] = heat_level
	return data

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	if data.has("heat_level"):
		set_heat_level(data["heat_level"])

# --- PROCEDURAL GEOMETRY GENERATION ---

func _update_geometry() -> void:
	_cache_nodes()
	if _frame_mesh_node:
		_frame_mesh_node.mesh = _generate_frame_mesh()
	if _fins_mesh_node:
		_fins_mesh_node.mesh = _generate_fins_mesh()

func _generate_frame_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var border: float = min(min(width, height) * 0.08, 0.06)

	# Frame Bezel (4 outer bars)
	_add_box(st, Vector3(0, (height - border) * 0.5, depth * 0.5), Vector3(width, border, depth))
	_add_box(st, Vector3(0, -(height - border) * 0.5, depth * 0.5), Vector3(width, border, depth))
	_add_box(st, Vector3(-(width - border) * 0.5, 0, depth * 0.5), Vector3(border, height - 2.0 * border, depth))
	_add_box(st, Vector3((width - border) * 0.5, 0, depth * 0.5), Vector3(border, height - 2.0 * border, depth))

	# Backing plate (wall heat shield)
	_add_box(st, Vector3(0, 0, 0.005), Vector3(width - 2.0 * border, height - 2.0 * border, 0.01))

	# Horizontal support rails
	var rail_h: float = 0.015
	var rail_d: float = 0.02
	_add_box(st, Vector3(0, (height * 0.5) - border - rail_h, depth * 0.5), Vector3(width - 2.0 * border, rail_h, rail_d))
	_add_box(st, Vector3(0, -(height * 0.5) + border + rail_h, depth * 0.5), Vector3(width - 2.0 * border, rail_h, rail_d))

	st.generate_normals()
	return st.commit()

func _generate_fins_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var border: float = min(min(width, height) * 0.08, 0.06)
	var inner_w: float = width - 2.0 * border
	var inner_h: float = height - 2.0 * border - 0.04
	var fin_w: float = min(inner_w / (fin_count * 2.5), 0.025)
	var fin_d: float = depth * 0.75
	var fin_center_z: float = depth * 0.45

	if fin_count <= 1:
		_add_box(st, Vector3(0, 0, fin_center_z), Vector3(fin_w, inner_h, fin_d))
	else:
		var start_x: float = -inner_w * 0.42
		var end_x: float = inner_w * 0.42
		for i in range(fin_count):
			var t: float = float(i) / float(fin_count - 1)
			var x_pos: float = lerp(start_x, end_x, t)
			_add_box(st, Vector3(x_pos, 0, fin_center_z), Vector3(fin_w, inner_h, fin_d))

	st.generate_normals()
	return st.commit()

static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	var min_p: Vector3 = center - h
	var max_p: Vector3 = center + h

	var v0 := Vector3(min_p.x, min_p.y, max_p.z)
	var v1 := Vector3(max_p.x, min_p.y, max_p.z)
	var v2 := Vector3(max_p.x, max_p.y, max_p.z)
	var v3 := Vector3(min_p.x, max_p.y, max_p.z)
	var v4 := Vector3(min_p.x, min_p.y, min_p.z)
	var v5 := Vector3(max_p.x, min_p.y, min_p.z)
	var v6 := Vector3(max_p.x, max_p.y, min_p.z)
	var v7 := Vector3(min_p.x, max_p.y, min_p.z)

	# Front (+Z)
	_add_quad(st, v0, v1, v2, v3, Vector3(0, 0, 1))
	# Back (-Z)
	_add_quad(st, v5, v4, v7, v6, Vector3(0, 0, -1))
	# Top (+Y)
	_add_quad(st, v3, v2, v6, v7, Vector3(0, 1, 0))
	# Bottom (-Y)
	_add_quad(st, v4, v5, v1, v0, Vector3(0, -1, 0))
	# Right (+X)
	_add_quad(st, v1, v5, v6, v2, Vector3(1, 0, 0))
	# Left (-X)
	_add_quad(st, v4, v0, v3, v7, Vector3(-1, 0, 0))

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	# Tri 1: a, b, c
	st.add_normal(normal)
	st.add_uv(Vector2(0, 1))
	st.add_vertex(a)

	st.add_normal(normal)
	st.add_uv(Vector2(1, 1))
	st.add_vertex(b)

	st.add_normal(normal)
	st.add_uv(Vector2(1, 0))
	st.add_vertex(c)

	# Tri 2: a, c, d
	st.add_normal(normal)
	st.add_uv(Vector2(0, 1))
	st.add_vertex(a)

	st.add_normal(normal)
	st.add_uv(Vector2(1, 0))
	st.add_vertex(c)

	st.add_normal(normal)
	st.add_uv(Vector2(0, 0))
	st.add_vertex(d)
