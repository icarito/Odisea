extends "res://core_v2/visual/plasma_exhaust/PlasmaExhaustBase.gd"

# Performance Cost: Medium (Procedural Noise in Fragment)
# LOD Support: Yes (Standard Godot Mesh LOD)

export(float) var color_cycle_speed := 1.0
export(float) var noise_scale := 2.0
export(float) var distortion_amount := 0.5
export(float) var brightness := 2.0
export(float) var pulse_frequency := 1.0

onready var mesh_instance = $MeshInstance

func _ready():
	_update_shader_params()

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
