extends Node

# PlayerMovementV2.gd - Componente para movimiento horizontal suavizado

export(float) var acceleration := 20.0
export(float) var friction := 40.0
export(float) var move_speed := 5.0
export(float) var run_speed_multiplier := 1.8
export(float) var air_control_multiplier := 0.5  # Reducir aceleración en el aire
export(float) var stop_threshold := 0.1  # Threshold para forzar velocidad a cero

var horizontal_velocity := Vector3.ZERO
var wish_direction := Vector3.ZERO

func process_movement(dt: float, move_vec: Vector2, basis: Basis, sprint: bool, is_on_floor: bool) -> void:
	var target_speed = move_speed * (run_speed_multiplier if sprint else 1.0)
	
	var forward = -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var right = basis.x
	
	var wish_dir = forward * move_vec.y + right * move_vec.x
	wish_direction = wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO
	wish_dir = wish_direction * target_speed
	
	# Aplicar fricción más agresiva cuando no hay input
	var accel: float
	if wish_dir.length_squared() > 0.0:
		accel = acceleration
		# Reducir control en el aire
		if not is_on_floor:
			accel *= air_control_multiplier
	else:
		accel = friction
	
	horizontal_velocity = horizontal_velocity.move_toward(wish_dir, accel * dt)

	
	# Forzar a cero si está por debajo del threshold para evitar micro-movimientos
	if horizontal_velocity.length() < stop_threshold:
		horizontal_velocity = Vector3.ZERO

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity