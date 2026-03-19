tool
extends PropBaseV2
class_name SciFiPathMarkerV2

# SciFiPathMarkerV2.gd - Low-profile floor marker with pulse effect.

export(Color) var marker_color := Color(0.0, 0.8, 1.0) setget set_marker_color
export(float, 0.0, 5.0) var light_energy_max := 1.5
export(float, 0.5, 8.0) var light_range := 1.5 setget set_light_range
export(bool) var pulse_enabled := true
export(float, 0.1, 5.0) var pulse_speed := 1.5

var _omni_light: OmniLight = null
var _marker_mesh: MeshInstance = null
var _time_acc := 0.0

func _ready():
	_omni_light = _find_child_by_type("OmniLight")
	_marker_mesh = get_node_or_null("MarkerMesh")
	._ready()
	_apply_settings()

func set_marker_color(v: Color) -> void:
	marker_color = v
	if is_inside_tree():
		_apply_settings()

func set_light_range(v: float) -> void:
	light_range = v
	if _omni_light:
		_omni_light.omni_range = v

func _apply_settings():
	if _omni_light:
		_omni_light.light_color = marker_color
		_omni_light.omni_range = light_range
	
	if _marker_mesh:
		var mat = _marker_mesh.material_override
		if mat == null and _marker_mesh.get_surface_material_count() > 0:
			mat = _marker_mesh.get_surface_material(0)
		
		if mat:
			if not mat.resource_local_to_scene:
				mat = mat.duplicate()
				mat.resource_local_to_scene = true
				if _marker_mesh.material_override:
					_marker_mesh.material_override = mat
				else:
					_marker_mesh.set_surface_material(0, mat)
			
			if mat is SpatialMaterial:
				mat.emission = marker_color
	
	_update_visuals()

func step(dt: float) -> void:
	.step(dt)
	if pulse_enabled and anim_progress > 0.01:
		_time_acc += dt
		_update_visuals()

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	
	var pulse_factor = 1.0
	if pulse_enabled and not Engine.editor_hint:
		pulse_factor = 0.7 + 0.3 * sin(_time_acc * PI * pulse_speed)
	
	var final_energy = t * light_energy_max * pulse_factor
	
	if _omni_light:
		_omni_light.light_energy = final_energy
	
	if _marker_mesh:
		var mat = _marker_mesh.material_override
		if mat == null and _marker_mesh.get_surface_material_count() > 0:
			mat = _marker_mesh.get_surface_material(0)
		if mat is SpatialMaterial:
			mat.emission_energy = final_energy * 2.0

func _find_child_by_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
	return null
