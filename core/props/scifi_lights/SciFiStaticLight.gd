tool
extends PropBase
class_name SciFiStaticLight

# SciFiStaticLight.gd - A simple static capsule light prop.
# Extends PropBase so it follows the interactable contract (on/off).

export(Color) var light_color := Color(0.639, 1.0, 0.114) setget set_light_color
export(float, 0.0, 5.0) var light_energy_max := 2.0

var _omni_light: OmniLight = null
var _mesh: MeshInstance = null

func _ready():
	._ready()
	for child in get_children():
		if child is OmniLight and not _omni_light:
			_omni_light = child
		elif child is MeshInstance and not _mesh:
			_mesh = child
	_apply_color()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_color()

func _apply_color():
	if _omni_light:
		_omni_light.light_color = light_color
	if _mesh and _mesh.material_override is SpatialMaterial:
		_mesh.material_override.emission = light_color

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if _omni_light:
		_omni_light.light_energy = t * light_energy_max
	if _mesh and _mesh.material_override is SpatialMaterial:
		_mesh.material_override.emission_energy = t * 3.0
