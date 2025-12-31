extends Node

# PlayerMovementV2.gd - Componente para movimiento horizontal suavizado

export(float) var acceleration := 10.0
export(float) var friction := 5.0
export(float) var move_speed := 5.0
export(float) var run_speed_multiplier := 1.8

var horizontal_velocity := Vector3.ZERO
var wish_direction := Vector3.ZERO

func process_movement(dt: float, move_vec: Vector2, basis: Basis, sprint: bool) -> void:
	var target_speed = move_speed * (run_speed_multiplier if sprint else 1.0)
	
	var forward = -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var right = basis.x
	
	var wish_dir = forward * move_vec.y + right * move_vec.x
	wish_direction = wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO
	wish_dir = wish_direction * target_speed
	
	var accel = acceleration if wish_dir.length_squared() > 0.0 else friction
	horizontal_velocity = horizontal_velocity.move_toward(wish_dir, accel * dt)

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity