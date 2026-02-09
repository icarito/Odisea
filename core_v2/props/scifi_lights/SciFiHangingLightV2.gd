tool
extends PropBaseV2
class_name SciFiHangingLightV2

# SciFiHangingLightV2.gd - A pendant light hanging from ceiling with cable and gentle sway.

export(Color) var light_color := Color(0.9, 0.85, 0.7) setget set_light_color
export(float, 0.5, 10.0) var light_range := 4.0 setget set_light_range
export(float, 0.0, 5.0) var light_energy_max := 2.0
export(float, 0.0, 0.5) var sway_amplitude := 0.05 # How much the light sways
export(float, 0.5, 5.0) var sway_speed := 1.0 # Speed of swaying

var _lamp_pivot: Spatial = null
var _omni_light: OmniLight = null
var _lamp_mesh: MeshInstance = null
var _time_accumulator := 0.0

func _ready():
	._ready()
	_lamp_pivot = get_node_or_null("LampPivot")
	if _lamp_pivot:
		_omni_light = _lamp_pivot.get_node_or_null("OmniLight")
		_lamp_mesh = _lamp_pivot.get_node_or_null("LampMesh")
	_apply_color()

func set_light_color(v: Color) -> void:
	light_color = v
	if is_inside_tree():
		_apply_color()

func set_light_range(v: float) -> void:
	light_range = v
	if _omni_light:
		_omni_light.omni_range = v

func _apply_color():
	if _omni_light:
		_omni_light.light_color = light_color
	if _lamp_mesh and _lamp_mesh.material_override is SpatialMaterial:
		_lamp_mesh.material_override.emission = light_color

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	_time_accumulator += delta
	
	# Gentle sway when active
	if _lamp_pivot and sway_amplitude > 0.001:
		var sway_x = sin(_time_accumulator * sway_speed) * sway_amplitude
		var sway_z = cos(_time_accumulator * sway_speed * 0.7) * sway_amplitude * 0.5
		_lamp_pivot.rotation.x = sway_x
		_lamp_pivot.rotation.z = sway_z

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if _omni_light:
		_omni_light.light_energy = t * light_energy_max
	if _lamp_mesh and _lamp_mesh.material_override is SpatialMaterial:
		_lamp_mesh.material_override.emission_energy = t * 3.0

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["hanging_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("hanging_time", 0.0)
