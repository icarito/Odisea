tool
extends PropBaseV2
class_name FluorescentLight

# FluorescentLight.gd - A tubular fluorescent light prop with optional flickering.
# Extends PropBaseV2 for compatibility with Logic Circuit System and interactions.

export(Color) var light_color := Color(0.8, 0.9, 1.0) setget set_light_color
export(float, 0.0, 10.0) var light_energy := 1.0 setget set_light_energy
export(float, 0.0, 20.0) var light_range := 10.0 setget set_light_range
export(bool) var flicker_enabled := false
export(float, 0.1, 20.0) var flicker_speed := 10.0
export(float, 0.0, 1.0) var flicker_intensity := 0.5

var _omni_light: OmniLight = null
var _spot_light: SpotLight = null # Optional support for spotlight too
var _mesh: MeshInstance = null
var _time_acc: float = 0.0

func _ready():
	._ready()
	_omni_light = _find_child_by_type("OmniLight")
	_spot_light = _find_child_by_type("SpotLight")
	_mesh = _find_child_by_type("MeshInstance")
	_apply_settings()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_settings()

func set_light_energy(v: float) -> void:
	light_energy = v
	if is_inside_tree():
		_update_visuals()

func set_light_range(v: float) -> void:
	light_range = v
	if is_inside_tree():
		if _omni_light:
			_omni_light.omni_range = v
		if _spot_light:
			_spot_light.spot_range = v

func _apply_settings():
	if _omni_light:
		_omni_light.light_color = light_color
		_omni_light.omni_range = light_range
	if _spot_light:
		_spot_light.light_color = light_color
		_spot_light.spot_range = light_range

	if _mesh and _mesh.material_override:
		if not _mesh.material_override.resource_local_to_scene:
			_mesh.material_override = _mesh.material_override.duplicate()
		if _mesh.material_override is SpatialMaterial:
			_mesh.material_override.emission = light_color

	_update_visuals()

func _update_visuals() -> void:
	._update_visuals()

	var current_energy = light_energy * anim_progress

	if flicker_enabled and anim_progress > 0.01:
		var noise = sin(_time_acc * flicker_speed) * sin(_time_acc * flicker_speed * 0.79 + 1.23)
		noise += 0.5 * sin(_time_acc * flicker_speed * 3.14)
		var factor = 1.0 - (flicker_intensity * 0.5 * (1.0 + noise))
		factor = clamp(factor, 0.0, 1.2)
		current_energy *= factor

	if _omni_light:
		_omni_light.light_energy = current_energy
	if _spot_light:
		_spot_light.light_energy = current_energy

	if _mesh and _mesh.material_override:
		if _mesh.material_override is SpatialMaterial:
			_mesh.material_override.emission_energy = current_energy

func step(dt: float) -> void:
	.step(dt)
	_time_acc += dt

	if flicker_enabled and anim_progress > 0.01:
		_update_visuals()

func _find_child_by_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
	return null
