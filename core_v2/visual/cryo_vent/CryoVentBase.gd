extends Spatial
class_name CryoVentBase

# Performance Cost: - (Base Class)
# LOD Support: -

export(bool) var is_active := true setget set_active
export(float, 0.0, 1.0) var intensity := 1.0 setget set_intensity
export(float, 0.0, 1.0) var color_phase := 0.0 setget set_color_phase

func set_active(val: bool) -> void:
	is_active = val
	_update_active_state()

func set_intensity(val: float) -> void:
	intensity = clamp(val, 0.0, 1.0)
	_update_intensity()

func set_color_phase(val: float) -> void:
	color_phase = clamp(val, 0.0, 1.0)
	_update_color_phase()

func _update_active_state() -> void:
	visible = is_active

func _update_intensity() -> void:
	pass

func _update_color_phase() -> void:
	pass
