extends "res://core_v2/visual/cryo_vent/CryoVentBase.gd"

# Performance Cost: Low (a few camera-facing quads, texture fetch)
# LOD Support: Yes (Standard Godot Mesh LOD)

# Several stacked axis-billboard quads sharing one flipbook. Each layer keeps its
# own phase_offset / depth_offset / wobble (authored per-material in the .tscn)
# so they give the plume depth instead of looking like a single flat sprite.

export(String, FILE, "*.png,*.jpg") var sprite_sheet_path := "res://core_v2/props/exhaust/plasma_flipbook_8x8.png"
export(float) var animation_speed := 15.0
export(Color) var tint_color := Color(0.2, 0.6, 1.0, 1.0) setget set_tint_color
export(float) var emission_strength := 2.5
export(Vector2) var grid_size := Vector2(8.0, 8.0) # plasma_flipbook_8x8.png is an 8x8 sheet.

func _ready():
	_update_shader_params()
	if sprite_sheet_path != "":
		var tex = load(sprite_sheet_path)
		if tex:
			for mat in _mats():
				mat.set_shader_param("flipbook_tex", tex)

func _planes() -> Array:
	var out := []
	for c in get_children():
		if c is MeshInstance:
			out.append(c)
	return out

func _mats() -> Array:
	var out := []
	for mi in _planes():
		var mat = mi.get_surface_material(0)
		if mat:
			out.append(mat)
	return out

func set_tint_color(val: Color):
	tint_color = val
	for mat in _mats():
		mat.set_shader_param("tint_color", tint_color)

func _update_intensity():
	for mat in _mats():
		mat.set_shader_param("intensity", intensity)

func _update_color_phase():
	for mat in _mats():
		mat.set_shader_param("color_phase", color_phase)

func _update_shader_params():
	# Only the layer-shared params; phase_offset/depth_offset/wobble/taper stay
	# as authored per-material so the layers differ.
	for mat in _mats():
		mat.set_shader_param("animation_speed", animation_speed)
		mat.set_shader_param("tint_color", tint_color)
		mat.set_shader_param("grid_size", grid_size)
