extends PropBaseV2
class_name IndustrialFan

# IndustrialFan.gd
# Deterministic fan that pushes objects in its forward direction (-Z).

export(float) var rotation_speed := 15.0 # Radians per second
export(float) var wind_force := 10.0

var _blade: Spatial
var _area: Area

func _ready():
	_blade = get_node_or_null("BladeMount/Blade")
	_area = get_node_or_null("WindArea")
	if _blade and "rotation_speed" in _blade:
		_blade.rotation_speed = rotation_speed
	if _area and "wind_velocity" in _area:
		_area.wind_velocity = Vector3(0.0, 0.0, -wind_force)
	_update_visuals()

func _update_visuals():
	if _blade and "is_active" in _blade:
		_blade.is_active = is_active
	if _area and _area.has_method("set_active"):
		_area.set_active(is_active)

func _wants_continuous_step() -> bool:
	return is_active
