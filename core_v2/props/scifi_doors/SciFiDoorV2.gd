tool
extends PropBaseV2
class_name SciFiDoorV2

# SciFiDoorV2.gd - Modular door mechanism for sideways and vertical doors.
# Inherits deterministic animation and auto-wiring from PropBaseV2.

export(NodePath) var panel_left_path
export(NodePath) var panel_right_path
export(Vector3) var open_offset_left := Vector3(-2, 0, 0)
export(Vector3) var open_offset_right := Vector3(2, 0, 0)

export(Array, NodePath) var indicator_light_paths = []
export(Color) var color_closed := Color.red
export(Color) var color_open := Color.green
export(Color) var color_moving := Color.orange
export(float, 0.0, 8.0) var light_energy_closed := 0.45
export(float, 0.0, 8.0) var light_energy_open := 1.25
export(float, 0.0, 8.0) var light_energy_moving := 1.8

var _panel_left: Spatial = null
var _panel_right: Spatial = null
var _indicator_lights: Array = []

var _start_pos_left: Vector3
var _start_pos_right: Vector3

func _ready():
	._ready()
	_panel_left = get_node_or_null(panel_left_path)
	_panel_right = get_node_or_null(panel_right_path)
	
	if _panel_left: _start_pos_left = _panel_left.transform.origin
	if _panel_right: _start_pos_right = _panel_right.transform.origin
	
	_indicator_lights.clear()
	for p in indicator_light_paths:
		var l = get_node_or_null(p)
		if l: _indicator_lights.append(l)
	
	_update_visuals()

func _update_visuals() -> void:
	._update_visuals() # Handles particle emission if any
	
	# Interpolate panel positions
	if _panel_left:
		_panel_left.transform.origin = _start_pos_left + (open_offset_left * anim_progress)
		_force_panel_transform_update(_panel_left)
	if _panel_right:
		_panel_right.transform.origin = _start_pos_right + (open_offset_right * anim_progress)
		_force_panel_transform_update(_panel_right)
	
	# Update indicator lights
	var target_color = color_moving
	var target_energy = light_energy_moving
	if anim_progress >= 0.99:
		target_color = color_open
		target_energy = light_energy_open
	elif anim_progress <= 0.01:
		target_color = color_closed
		target_energy = light_energy_closed
		
	for l in _indicator_lights:
		if l is OmniLight or l is SpotLight:
			l.light_color = target_color
			l.light_energy = target_energy
		elif l is MeshInstance:
			var mat = l.material_override
			if mat == null and l.get_surface_material_count() > 0:
				mat = l.get_surface_material(0)
			if mat and not mat.resource_local_to_scene:
				mat = mat.duplicate(true)
				mat.resource_local_to_scene = true
				if l.material_override:
					l.material_override = mat
				else:
					l.set_surface_material(0, mat)
			if mat is SpatialMaterial:
				mat.emission = target_color
				mat.emission_energy = target_energy
			elif mat is ShaderMaterial:
				mat.set_shader_param("emission", target_color)
				mat.set_shader_param("emission_energy", target_energy)

func _force_panel_transform_update(panel: Spatial) -> void:
	if panel is CollisionObject or panel is CSGShape:
		panel.force_update_transform()
