extends Node

class_name ExternalVelocity

# @export_range(0.0, 10.0, 0.1) var decay_rate := 6.0  # decaimiento por segundo
export var decay_rate := 6.0

var velocity := Vector3.ZERO

func set_external_velocity(v: Vector3) -> void:
	"""API pública: llamada por plataformas/conveyors."""
	velocity = v

func integrate(delta: float) -> Vector3:
	"""Llamar cada frame: aplica decaimiento y devuelve velocity a aplicar este frame."""
	if velocity.length() < 0.001:
		velocity = Vector3.ZERO
		return Vector3.ZERO
	velocity = velocity.linear_interpolate(Vector3.ZERO, decay_rate * delta)
	return velocity