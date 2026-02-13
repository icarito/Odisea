tool
extends PropBase
class_name SciFiBoxLight

# SciFiBoxLight.gd - A box-shaped light prop with spotlight and emissive floor grid.
# Ported from graphic_demo_3d box scene.

export(Color) var light_color := Color(1.0, 0.54, 0.18) setget set_light_color
export(float, 0.5, 10.0) var light_range := 5.0 setget set_light_range
export(float, 0.0, 8.0) var light_energy_max := 2.0

var _spot_light: SpotLight = null
var _omni_light: OmniLight = null
var _mesh: MeshInstance = null

func _ready():
	._ready()
	_spot_light = _find_child_by_type("SpotLight")
	_omni_light = _find_child_by_type("OmniLight")
	_mesh = _find_child_by_type("MeshInstance")
	_apply_color()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_color()

func set_light_range(v: float) -> void:
	light_range = v
	if _spot_light:
		_spot_light.spot_range = v
	if _omni_light:
		_omni_light.omni_range = v * 0.5

func _apply_color():
	if _spot_light:
		_spot_light.light_color = light_color
	if _omni_light:
		_omni_light.light_color = light_color
	if _mesh and _mesh.material_override is SpatialMaterial:
		_mesh.material_override.emission = light_color

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if _spot_light:
		_spot_light.light_energy = t * light_energy_max
	if _omni_light:
		_omni_light.light_energy = t * light_energy_max * 0.5
	if _mesh and _mesh.material_override:
		if _mesh.material_override is ShaderMaterial:
			_mesh.material_override.set_shader_param("intensity", t)
		elif _mesh.material_override is SpatialMaterial:
			_mesh.material_override.emission_energy = t * 3.0

func _find_child_by_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
	return null
