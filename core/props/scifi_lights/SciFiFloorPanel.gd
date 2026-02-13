tool
extends PropBase
class_name SciFiFloorPanel

# SciFiFloorPanel.gd - Reflective floor panel with glowing grid lines.
# Simplified: no external textures, just a reflective dark floor with emission grid.

export(Color) var grid_color := Color(0.1, 0.4, 0.8) setget set_grid_color

var _mesh: MeshInstance = null

func _ready():
	._ready()
	_mesh = get_node_or_null("MeshInstance")
	_apply_color()

func set_grid_color(v: Color) -> void:
	grid_color = v
	if is_inside_tree():
		_apply_color()

func _apply_color():
	if _mesh and _mesh.material_override is ShaderMaterial:
		_mesh.material_override.set_shader_param("grid_color", grid_color)

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if _mesh and _mesh.material_override is ShaderMaterial:
		_mesh.material_override.set_shader_param("intensity", t)
