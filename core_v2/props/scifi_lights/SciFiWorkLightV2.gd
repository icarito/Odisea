tool
extends PropBaseV2
class_name SciFiWorkLightV2

# SciFiWorkLightV2.gd - Industrial reflector/work light with SpotLight.

func _init():
	starts_active = true

export(Color) var light_color := Color(1.0, 0.9, 0.7) setget set_light_color
export(float, 0.0, 10.0) var light_energy_max := 4.0
export(float, 1.0, 100.0) var light_range := 15.0 setget set_light_range
export(float, 1.0, 90.0) var spot_angle := 45.0 setget set_spot_angle
export(float, -90.0, 90.0) var head_tilt := 0.0 setget set_head_tilt
export(bool) var enable_shadows := true setget set_enable_shadows

export(Color) var albedo_color_on := Color(1.0, 1.0, 1.0)
export(Color) var albedo_color_off := Color(0.3, 0.3, 0.3)
export(Color) var indicator_color_on := Color(0.0, 1.0, 0.0) # Green when ON
export(Color) var indicator_color_off := Color(1.0, 0.4, 0.0) # Orange when OFF

var _spot_light: SpotLight = null
var _omni_light: OmniLight = null
var _bulb_mesh: GeometryInstance = null
var _indicator_mesh: GeometryInstance = null
var _head_node: Spatial = null

func _ready():
	_spot_light = _find_child_by_type("SpotLight")
	_omni_light = _find_child_by_type("OmniLight")
	_bulb_mesh = get_node_or_null("Bulb")
	if not _bulb_mesh:
		_bulb_mesh = find_node("Bulb", true, false)
	
	_indicator_mesh = get_node_or_null("Indicator")
	if not _indicator_mesh:
		_indicator_mesh = find_node("Indicator", true, false)

	_head_node = get_node_or_null("Head")
	if not _head_node:
		_head_node = find_node("Head", true, false)
	._ready()
	_apply_settings()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_settings()

func set_light_range(v: float) -> void:
	light_range = v
	if _spot_light:
		_spot_light.spot_range = v
	if _omni_light:
		_omni_light.omni_range = max(1.0, v * 0.35)

func set_spot_angle(v: float) -> void:
	spot_angle = v
	if _spot_light:
		_spot_light.spot_angle = v

func set_head_tilt(v: float) -> void:
	head_tilt = v
	if _head_node:
		var rot = _head_node.rotation_degrees
		rot.x = v
		_head_node.rotation_degrees = rot

func set_enable_shadows(v: bool) -> void:
	enable_shadows = v
	if _spot_light:
		_spot_light.shadow_enabled = v
	if _omni_light:
		_omni_light.shadow_enabled = false

func _apply_settings():
	if _spot_light:
		_spot_light.light_color = light_color
		_spot_light.spot_range = light_range
		_spot_light.spot_angle = spot_angle
		_spot_light.shadow_enabled = enable_shadows
	if _omni_light:
		_omni_light.light_color = light_color
		_omni_light.omni_range = max(1.0, light_range * 0.35)
		_omni_light.shadow_enabled = false
	
	if _head_node:
		var rot = _head_node.rotation_degrees
		rot.x = head_tilt
		_head_node.rotation_degrees = rot
	
	if _bulb_mesh:
		var mat = _bulb_mesh.material_override
		if mat == null and _bulb_mesh.get_surface_material_count() > 0:
			mat = _bulb_mesh.get_surface_material(0)
		
		if mat:
			if not mat.resource_local_to_scene:
				mat = mat.duplicate()
				mat.resource_local_to_scene = true
				if _bulb_mesh.material_override:
					_bulb_mesh.material_override = mat
				else:
					_bulb_mesh.set_surface_material(0, mat)
			
			if mat is SpatialMaterial:
				mat.emission = light_color
	
	_update_visuals()

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if _spot_light:
		_spot_light.light_energy = t * light_energy_max
	if _omni_light:
		_omni_light.light_energy = t * light_energy_max * 0.45
	
	if _bulb_mesh:
		var mat = _get_spatial_material(_bulb_mesh)
		if mat:
			mat.emission_energy = t * 4.0
			mat.albedo_color = albedo_color_off.linear_interpolate(albedo_color_on, t)

	if _indicator_mesh:
		var mat = _get_spatial_material(_indicator_mesh)
		if mat == null:
			# Create a new local material if none exists
			mat = SpatialMaterial.new()
			mat.resource_local_to_scene = true
			_indicator_mesh.material_override = mat
		
		if mat:
			var led_col = indicator_color_off.linear_interpolate(indicator_color_on, t)
			mat.albedo_color = led_col
			mat.emission_enabled = true
			mat.emission = led_col
			mat.emission_energy = 2.0

func _get_spatial_material(node: GeometryInstance) -> SpatialMaterial:
	if not node: return null
	var mat = node.material_override
	if not mat and node is MeshInstance and node.get_surface_material_count() > 0:
		mat = node.get_surface_material(0)
	
	if mat and mat is SpatialMaterial:
		if not mat.resource_local_to_scene:
			mat = mat.duplicate()
			mat.resource_local_to_scene = true
			node.material_override = mat
		return mat
	return null

func _find_child_by_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
		var nested = _find_child_by_type_recursive(child, type_name)
		if nested:
			return nested
	return null

func _find_child_by_type_recursive(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var nested = _find_child_by_type_recursive(child, type_name)
		if nested:
			return nested
	return null
