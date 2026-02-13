tool
extends PropBase
class_name EmergencyBeacon

# EmergencyBeacon.gd - Rotating emergency beacon with pulsing light.
# Inspired by graphic_demo_3d parts/border lights.
# Adjustable color, rotation speed, and pulse rate.

export(Color) var beacon_color := Color(1.0, 0.3, 0.0) setget set_beacon_color
export(float, 0.1, 20.0) var rotation_speed := 3.0 # Rotations per second
export(float, 0.1, 10.0) var pulse_speed := 2.0 # Pulse frequency
export(float, 0.5, 15.0) var light_range := 5.0 setget set_light_range
export(float, 0.0, 8.0) var light_energy_max := 3.0
export(float, 0.0, 1.0) var pulse_min := 0.3 # Minimum pulse brightness (0 = fully off)

var _dome_mesh: MeshInstance = null
var _base_mesh: MeshInstance = null
var _omni_light: OmniLight = null
var _time_accumulator := 0.0

func _ready():
	._ready()
	_dome_mesh = get_node_or_null("DomeMesh")
	_base_mesh = get_node_or_null("BaseMesh")
	_omni_light = get_node_or_null("OmniLight")
	_apply_color()

func set_beacon_color(v: Color) -> void:
	beacon_color = v
	if is_inside_tree():
		_apply_color()

func set_light_range(v: float) -> void:
	light_range = v
	if _omni_light:
		_omni_light.omni_range = v

func _apply_color():
	if _omni_light:
		_omni_light.light_color = beacon_color
	if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
		_dome_mesh.material_override.emission = beacon_color

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	if is_active:
		_time_accumulator += delta
		
		# Rotate the dome
		if _dome_mesh:
			_dome_mesh.rotation.y = _time_accumulator * rotation_speed * TAU
		
		# Pulse the light energy
		if _omni_light:
			var pulse = lerp(pulse_min, 1.0, (sin(_time_accumulator * pulse_speed * TAU) + 1.0) * 0.5)
			_omni_light.light_energy = pulse * light_energy_max * anim_progress
		
		# Pulse dome emission
		if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
			var pulse = lerp(pulse_min, 1.0, (sin(_time_accumulator * pulse_speed * TAU) + 1.0) * 0.5)
			_dome_mesh.material_override.emission_energy = pulse * 3.0 * anim_progress

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	if not is_active and _dome_mesh:
		# When off, stop rotation at current angle
		pass
	if _omni_light:
		_omni_light.light_energy = t * light_energy_max
	if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
		_dome_mesh.material_override.emission_energy = t * 3.0

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["beacon_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("beacon_time", 0.0)
