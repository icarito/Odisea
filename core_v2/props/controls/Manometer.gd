extends Spatial
class_name Manometer
tool

# Manometer.gd - Decorative indicator with a rotating needle.
# Updates visuals based on pressure_value.

# --- EXPORTED TUNING ---
export(float, 0.0, 1.0) var pressure_value: float = 0.0 setget set_pressure_value
export(float) var update_speed: float = 2.0

# --- INTERNAL STATE ---
var _needle: Spatial
var _indicator_mat: SpatialMaterial
var _target_value: float = 0.0
var _current_value: float = 0.0

func set_pressure_value(v: float) -> void:
	pressure_value = clamp(v, 0.0, 1.0)
	_target_value = pressure_value
	if not is_inside_tree() or Engine.editor_hint:
		_current_value = _target_value
		_update_visuals()

func _ready():
	_needle = get_node_or_null("Needle")
	var mesh = get_node_or_null("Face")
	if mesh and mesh is MeshInstance:
		_indicator_mat = mesh.get_surface_material(0)
		if _indicator_mat:
			_indicator_mat = _indicator_mat.duplicate()
			mesh.set_surface_material(0, _indicator_mat)

	_current_value = pressure_value
	_target_value = pressure_value
	_update_visuals()

func _process(delta):
	if Engine.editor_hint:
		return

	if abs(_current_value - _target_value) > 0.001:
		_current_value = lerp(_current_value, _target_value, update_speed * delta)
		_update_visuals()

func _update_visuals():
	if not _needle:
		_needle = get_node_or_null("Needle")

	if _needle:
		# Needle rotation: -135 to +135 degrees (270 degree sweep)
		var angle = lerp(-deg2rad(135), deg2rad(135), _current_value)
		_needle.rotation.z = -angle # Rotate around Z for a face-on dial

	if _indicator_mat:
		# Color from green (0) to red (1)
		var color_low = Color(0, 1, 0)
		var color_high = Color(1, 0, 0)
		var current_color = color_low.linear_interpolate(color_high, _current_value)
		_indicator_mat.emission = current_color

# Logic Circuit System Integration
func set_active(value: bool):
	set_pressure_value(1.0 if value else 0.0)

func activate():
	set_pressure_value(1.0)

func deactivate():
	set_pressure_value(0.0)
