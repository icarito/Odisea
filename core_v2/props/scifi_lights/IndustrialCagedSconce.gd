extends Spatial
class_name IndustrialCagedSconce

export(bool) var starts_active := true
export(Color) var light_color := Color(1.0, 0.78, 0.48, 1.0)
export(float, 0.0, 8.0) var light_energy := 2.2

var _light: OmniLight = null
var _bulb: GeometryInstance = null
var _sound: AudioStreamPlayer3D = null
var _active := false

func _ready() -> void:
	_light = get_node_or_null("Light") as OmniLight
	_bulb = get_node_or_null("Bulb") as GeometryInstance
	_sound = get_node_or_null("Sound") as AudioStreamPlayer3D
	set_active(starts_active, false)

func set_active(value: bool, play_sound := true) -> void:
	_active = value
	if _light:
		_light.visible = value
		_light.light_energy = light_energy if value else 0.0
	if _bulb:
		_bulb.visible = value
	if value and play_sound and _sound and not _sound.playing:
		_sound.play()

func is_active() -> bool:
	return _active
