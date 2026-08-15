extends "res://core_v2/visual/cryo_vent/CryoVentBase.gd"

# Performance Cost: Medium (Procedural Noise in Fragment)
# LOD Support: Yes (Standard Godot Mesh LOD)

export(float) var color_cycle_speed := 1.0
export(float) var noise_scale := 3.0
export(float) var distortion_amount := 1.2
export(float) var brightness := 2.0
export(float) var pulse_frequency := 1.0
export(float) var flame_sharpness := 0.5 setget set_flame_sharpness
export(Color) var base_color := Color(0.0, 0.5, 1.0, 1.0) setget set_base_color
export(Color) var hot_color := Color(0.5, 0.8, 1.0, 1.0) setget set_hot_color

onready var mesh_instance = $MeshInstance

func _ready():
	_update_shader_params()

func _mat():
	return mesh_instance.get_surface_material(0) if mesh_instance else null

func set_flame_sharpness(val: float):
	flame_sharpness = val
	var mat = _mat()
	if mat: mat.set_shader_param("flame_sharpness", flame_sharpness)

func set_base_color(val: Color):
	base_color = val
	var mat = _mat()
	if mat: mat.set_shader_param("base_color", base_color)

func set_hot_color(val: Color):
	hot_color = val
	var mat = _mat()
	if mat: mat.set_shader_param("hot_color", hot_color)

func _process(delta):
	if is_active:
		# Option A can have its own internal cycle if needed
		pass

func _update_intensity():
	if mesh_instance:
		var mat = mesh_instance.get_surface_material(0)
		if mat:
			mat.set_shader_param("intensity", intensity)

func _update_color_phase():
	if mesh_instance:
		var mat = mesh_instance.get_surface_material(0)
		if mat:
			mat.set_shader_param("color_phase", color_phase)

func _update_shader_params():
	if mesh_instance:
		var mat = mesh_instance.get_surface_material(0)
		if mat:
			mat.set_shader_param("noise_scale", noise_scale)
			mat.set_shader_param("distortion_amount", distortion_amount)
			mat.set_shader_param("brightness", brightness)
			mat.set_shader_param("pulse_frequency", pulse_frequency)
			mat.set_shader_param("speed", color_cycle_speed)
			mat.set_shader_param("flame_sharpness", flame_sharpness)
			mat.set_shader_param("base_color", base_color)
			mat.set_shader_param("hot_color", hot_color)
