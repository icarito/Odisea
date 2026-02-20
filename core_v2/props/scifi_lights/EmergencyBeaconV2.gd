tool
extends PropBaseV2
class_name EmergencyBeaconV2

# EmergencyBeaconV2.gd - Rotating emergency beacon with pulsing light.
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
var _lens_mesh: MeshInstance = null
var _omni_light: OmniLight = null
var _sfx_alarm: SFXComponentV2 = null
var _time_accumulator := 0.0

func _ready():
	._ready()
	_dome_mesh = get_node_or_null("DomeMesh")
	_base_mesh = get_node_or_null("BaseMesh")
	_lens_mesh = get_node_or_null("DomeMesh/Lens")
	_omni_light = get_node_or_null("OmniLight")
	_sfx_alarm = get_node_or_null("SFX Alarm")
	_apply_color()
	
	# Initial sound state check (skip in editor)
	if not Engine.editor_hint and is_active and _sfx_alarm:
		_sfx_alarm.play_sfx()

func set_beacon_color(v: Color) -> void:
	beacon_color = v
	if is_inside_tree():
		_apply_color()

func set_light_range(v: float) -> void:
	light_range = v
	if _omni_light:
		_omni_light.omni_range = v

func set_active(value: bool, immediate: bool = false) -> void:
	var was_active = is_active
	.set_active(value, immediate)
	
	if Engine.editor_hint:
		return
	
	if _sfx_alarm:
		if value and not was_active:
			_sfx_alarm.play_sfx()
		elif not value and was_active:
			_sfx_alarm.stop_sfx()

func _apply_color():
	if _omni_light:
		_omni_light.light_color = beacon_color
	if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
		_dome_mesh.material_override.emission = beacon_color
	if _lens_mesh and _lens_mesh.material_override is SpatialMaterial:
		_lens_mesh.material_override.emission = beacon_color

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
	# When off (anim_progress near 0), dim the light significantly
	if _omni_light:
		# When fully off (t < 0.1), turn off light completely
		if t < 0.1:
			_omni_light.light_energy = 0.0
		else:
			_omni_light.light_energy = t * light_energy_max
	if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
		# When fully off (t < 0.1), dim emission significantly
		if t < 0.1:
			_dome_mesh.material_override.emission_energy = 0.1
		else:
			_dome_mesh.material_override.emission_energy = t * 3.0

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["beacon_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("beacon_time", 0.0)
