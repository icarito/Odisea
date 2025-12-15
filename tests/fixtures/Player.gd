extends KinematicBody

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("forward"):
		move_and_slide(Vector3(0, 0, -1) * 10 * delta, Vector3.UP)
