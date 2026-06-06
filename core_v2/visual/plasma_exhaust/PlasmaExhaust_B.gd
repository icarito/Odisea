extends "res://core_v2/visual/plasma_exhaust/PlasmaExhaustBase.gd"

# Performance Cost: Low (Texture Fetch)
# LOD Support: Yes (Standard Godot Mesh LOD)

export(String, FILE, "*.png,*.jpg") var sprite_sheet_path := "res://assets/FX/particle_system_effects_Godot3/textures/sprites_16.png"
export(float) var animation_speed := 15.0
export(Color) var tint_color := Color(0.2, 0.6, 1.0, 1.0)
export(float) var emission_strength := 2.5
export(Vector2) var grid_size := Vector2(4.0, 4.0) # sprites_16.png likely 4x4 or 8x8. Defaulting to 4x4.

onready var mesh_instance = $MeshInstance

func _ready():
	_update_shader_params()
	if sprite_sheet_path != "":
		var tex = load(sprite_sheet_path)
		if tex and mesh_instance:
			var mat = mesh_instance.get_surface_material(0)
			if mat:
				mat.set_shader_param("flipbook_tex", tex)

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
			mat.set_shader_param("animation_speed", animation_speed)
			mat.set_shader_param("tint_color", tint_color)
			mat.set_shader_param("emission_strength", emission_strength)
			mat.set_shader_param("grid_size", grid_size)
