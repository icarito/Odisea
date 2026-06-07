tool
extends "res://core_v2/props/scifi_lights/TrackerBase.gd"
class_name SearchLightV2

# SearchLightV2.gd - Rotating searchlight with SpotLight and volumetric effect.

export(float) var light_range := 40.0 setget set_light_range
export(float) var spot_angle := 60.0 setget set_spot_angle
export(Color) var light_color := Color(1.0, 0.95, 0.8) setget set_light_color
export(float) var light_energy_max := 8.0
export(bool) var volumetric := false setget set_volumetric
export(float) var bulb_emission_energy := 4.0
export(Color) var albedo_color_on := Color(1.0, 1.0, 1.0)
export(Color) var albedo_color_off := Color(0.3, 0.3, 0.3)
export(bool) var enable_shadows := false setget set_enable_shadows

var _spot_light: SpotLight = null
var _bulb_mesh: MeshInstance = null
var _indicator_mesh: MeshInstance = null
var _volumetric_cone: MeshInstance = null

func _ready():
	_spot_light = find_node("SpotLight", true, false)
	_bulb_mesh = find_node("Bulb", true, false)
	_indicator_mesh = find_node("Indicator", true, false)
	_volumetric_cone = find_node("VolumetricCone", true, false)

	._ready()
	_apply_settings()

func set_light_range(v: float) -> void:
	light_range = v
	if _spot_light:
		_spot_light.spot_range = v
	if _volumetric_cone:
		_update_volumetric_size()

func set_spot_angle(v: float) -> void:
	spot_angle = v
	if _spot_light:
		_spot_light.spot_angle = v
	if _volumetric_cone:
		_update_volumetric_size()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_settings()

func set_volumetric(v: bool) -> void:
	volumetric = v
	if _volumetric_cone:
		_volumetric_cone.visible = volumetric and anim_progress > 0.01

func set_enable_shadows(v: bool) -> void:
	enable_shadows = v
	if _spot_light:
		_spot_light.shadow_enabled = v

func _apply_settings():
	if _spot_light:
		_spot_light.light_color = light_color
		_spot_light.spot_range = light_range
		_spot_light.spot_angle = spot_angle
		_spot_light.shadow_enabled = enable_shadows

	if _bulb_mesh:
		var mat = _get_spatial_material(_bulb_mesh)
		if mat:
			mat.emission = light_color

	if _volumetric_cone:
		var mat = _volumetric_cone.material_override
		if mat and mat is ShaderMaterial:
			mat.set_shader_param("color", light_color)
		_update_volumetric_size()

	_update_visuals()

func _update_volumetric_size():
	if not _volumetric_cone: return
	# Simple cone mesh scaling
	# In Godot 3, a CylinderMesh can be used as a cone by setting top_radius to 0.
	# We'll assume the cone is aligned with -Z.
	var radius = light_range * tan(deg2rad(spot_angle * 0.5))
	_volumetric_cone.scale = Vector3(radius, radius, light_range)

func _update_visuals():
	._update_visuals()
	var t = anim_progress
	var active = t > 0.01

	if _spot_light:
		_spot_light.light_energy = t * light_energy_max
		_spot_light.visible = active

	if _volumetric_cone:
		_volumetric_cone.visible = volumetric and active
		var mat = _volumetric_cone.material_override
		if mat and mat is ShaderMaterial:
			mat.set_shader_param("alpha_multiplier", t)

	if _bulb_mesh:
		var mat = _get_spatial_material(_bulb_mesh)
		if mat:
			mat.emission_energy = t * bulb_emission_energy
			mat.albedo_color = albedo_color_off.linear_interpolate(albedo_color_on, t)

	if _indicator_mesh:
		var mat = _get_spatial_material(_indicator_mesh)
		if mat:
			var led_col = Color.red.linear_interpolate(Color.green, t)
			mat.albedo_color = led_col
			mat.emission_enabled = true
			mat.emission = led_col
			mat.emission_energy = 2.0

func _get_spatial_material(node: GeometryInstance) -> SpatialMaterial:
	if not node: return null
	var mat = node.material_override
	if not mat and node is MeshInstance and node.get_surface_material_count() > 0:
		mat = node.get_surface_material(0)
	if not mat and node is MeshInstance and node.mesh and node.mesh.get_surface_count() > 0:
		mat = node.mesh.surface_get_material(0)

	if mat and mat is SpatialMaterial:
		if not mat.resource_local_to_scene:
			mat = mat.duplicate()
			mat.resource_local_to_scene = true
			node.material_override = mat
		return mat
	return null
