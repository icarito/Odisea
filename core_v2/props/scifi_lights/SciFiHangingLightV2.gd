tool
extends PropBaseV2
class_name SciFiHangingLightV2

# SciFiHangingLightV2.gd - A pendant light hanging from ceiling with cable and gentle sway.

export(Color) var light_color := Color(0.9, 0.85, 0.7) setget set_light_color
export(float, 0.5, 12.0) var light_range := 7.0 setget set_light_range
export(float, 0.0, 8.0) var light_energy_max := 2.4
export(float, 0.0, 0.5) var sway_amplitude := 0.05 # How much the light sways
export(float, 0.5, 5.0) var sway_speed := 1.0 # Speed of swaying
export(int, 1, 4) var visual_tick_interval_frames := 2

var _lamp_pivot: Spatial = null
var _omni_light: OmniLight = null
var _lamp_mesh: MeshInstance = null
var _time_accumulator := 0.0
var _visual_tick_countdown := 0
var _visual_tick_accumulator := 0.0

func _ready():
	._ready()
	_lamp_pivot = get_node_or_null("LampPivot")
	if _lamp_pivot:
		_omni_light = _lamp_pivot.get_node_or_null("OmniLight")
		_lamp_mesh = _lamp_pivot.get_node_or_null("LampMesh")
	_apply_color()
	if _omni_light:
		_omni_light.omni_range = light_range
	_update_visuals()

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
	var mat = _get_lamp_material()
	if mat is SpatialMaterial:
		mat.emission = light_color

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	var visual_dt = _consume_visual_tick(delta)
	if visual_dt < 0.0:
		return
	_time_accumulator += visual_dt
	
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
	var mat = _get_lamp_material()
	if mat is SpatialMaterial:
		mat.emission_energy = t * 3.6

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["hanging_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("hanging_time", 0.0)

func _consume_visual_tick(delta: float) -> float:
	_visual_tick_accumulator += max(0.0, delta)
	if visual_tick_interval_frames <= 1:
		var dt = _visual_tick_accumulator
		_visual_tick_accumulator = 0.0
		return dt
	if _visual_tick_countdown > 0:
		_visual_tick_countdown -= 1
		return -1.0
	_visual_tick_countdown = visual_tick_interval_frames - 1
	var sampled_dt = _visual_tick_accumulator
	_visual_tick_accumulator = 0.0
	return sampled_dt

func _get_lamp_material() -> Material:
	if not _lamp_mesh:
		return null
	if _lamp_mesh.material_override:
		return _lamp_mesh.material_override
	return _lamp_mesh.get_surface_material(0)
