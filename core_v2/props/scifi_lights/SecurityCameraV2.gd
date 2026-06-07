tool
extends "res://core_v2/props/scifi_lights/TrackerBase.gd"
class_name SecurityCameraV2

# SecurityCameraV2.gd - Non-light prop that tracks player with a blinking recording LED.

export(Color) var record_led_color := Color(1.0, 0.1, 0.1)   # red
export(float) var record_led_blink_speed := 1.5               # blinks per second
export(bool) var recording := true                             # starts recording by default
export(float) var record_led_energy := 3.0

var _record_led_mesh: MeshInstance = null
var _blink_timer := 0.0

func _ready():
	add_to_group("security_camera")
	_record_led_mesh = find_node("RecordLED", true, false)
	._ready()

func step(dt: float) -> void:
	.step(dt)

	if recording:
		_blink_timer += dt
		_update_blink()
	else:
		_blink_timer = 0.0
		_set_led_active(false, 0.2) # Solid dim red when not recording

func _update_blink():
	var period = 1.0 / record_led_blink_speed
	var phase = fmod(_blink_timer, period) / period
	var is_on = phase < 0.5
	_set_led_active(is_on, 1.0 if is_on else 0.1)

func _set_led_active(active: bool, energy_scale: float):
	if not _record_led_mesh: return
	var mat = _get_spatial_material(_record_led_mesh)
	if mat:
		mat.albedo_color = record_led_color
		mat.emission_enabled = true
		mat.emission = record_led_color
		mat.emission_energy = record_led_energy * energy_scale

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
