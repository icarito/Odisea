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
export(float, 0.0, 10.0) var base_emission_energy := 1.8

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

	if _mesh:
		var has_mat_override = (_mesh.material_override != null)
		var mat = _mesh.material_override if has_mat_override else _mesh.get_surface_material(0)
		
		if mat:
			if not mat.resource_local_to_scene and not Engine.editor_hint:
				mat = mat.duplicate()
				if has_mat_override:
					_mesh.material_override = mat
				else:
					_mesh.set_surface_material(0, mat)
					
			if mat is SpatialMaterial:
				mat.emission = light_color
				mat.emission_operator = SpatialMaterial.EMISSION_OP_ADD

	_update_visuals()

func _update_visuals() -> void:
	._update_visuals()

	# anim_progress 0.0 = Off, 1.0 = On (if starts_active is true)
	# However, InteractableBaseV2 logic:
	# is_active = true -> target_progress = 1.0
	# is_active = false -> target_progress = 0.0

	var current_energy = light_energy * anim_progress
	var target_emission = base_emission_energy * anim_progress * 3.0

	if flicker_enabled and anim_progress > 0.01:
		# Deterministic flicker using _time_acc
		# Use sine waves to create irregular looking but deterministic pattern
		var noise = sin(_time_acc * flicker_speed) * sin(_time_acc * flicker_speed * 0.79 + 1.23)
		# Add some high frequency noise
		noise += 0.5 * sin(_time_acc * flicker_speed * 3.14)

		# Normalize roughly to -1..1 range (it can exceed but we clamp or scale)
		# We want flicker to reduce energy occasionally.
		# Map noise to factor [1.0 - intensity, 1.0]

		# Simple approach: if noise > threshold, dim it.
		# Or continuous variation.

		var factor = 1.0 - (flicker_intensity * 0.5 * (1.0 + noise))
		factor = clamp(factor, 0.0, 1.2) # Allow slight over-brightness too?

		current_energy *= factor
		target_emission *= factor

	if _omni_light:
		_omni_light.light_energy = current_energy
	if _spot_light:
		_spot_light.light_energy = current_energy

	if _mesh:
		var has_mat_override = (_mesh.material_override != null)
		var mat = _mesh.material_override if has_mat_override else _mesh.get_surface_material(0)
		if mat is SpatialMaterial:
			mat.emission_energy = target_emission
			if target_emission > 0.1:
				var bright_albedo = light_color.linear_interpolate(Color.white, 0.5)
				mat.albedo_color = bright_albedo
			else:
				mat.albedo_color = Color(0.15, 0.15, 0.15)
		elif mat is ShaderMaterial:
			# PropDitherManager replaced SpatialMaterial with ShaderMaterial
			mat.set_shader_param("emission_enabled", target_emission > 0.01)
			mat.set_shader_param("emission_energy", target_emission)
			mat.set_shader_param("emission_color", light_color)
			if target_emission > 0.1:
				var bright_albedo = light_color.linear_interpolate(Color.white, 0.5)
				mat.set_shader_param("albedo", bright_albedo)
			else:
				mat.set_shader_param("albedo", Color(0.15, 0.15, 0.15))


func step(dt: float) -> void:
	.step(dt)
	_time_acc += dt
	# Always update visuals if flickering is enabled and we are active,
	# because flicker depends on time even if anim_progress is static at 1.0
	if flicker_enabled and anim_progress > 0.01:
		_update_visuals()

func _find_child_by_type(type_name: String, node: Node = self) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var res = _find_child_by_type(type_name, child)
		if res: return res
	return null
