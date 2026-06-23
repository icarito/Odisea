extends Spatial

export(float) var rotation_speed: float = 15.0
export(bool) var is_active: bool = true

func _physics_process(delta: float) -> void:
	if is_active:
		rotate_y(rotation_speed * delta)
