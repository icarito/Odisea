extends Reference


# Devuelve Vector2(valor, velocidad) para un spring critico exacto parametrizado por half-life.
static func critical_spring_step(value: float, velocity: float, goal: float, half_life: float, delta: float) -> Vector2:
	var y: float = (2.0 * log(2.0)) / max(half_life, 0.00001)
	var j0: float = value - goal
	var j1: float = velocity + j0 * y
	var decay: float = exp(-y * delta)
	return Vector2(decay * (j0 + j1 * delta) + goal, decay * (velocity - j1 * y * delta))


# Compensa el lag conocido del spring y se aproxima suavemente al limite angular.
static func predictive_lead(rate: float, half_life: float, extra_seconds: float, max_offset: float) -> float:
	if max_offset <= 0.0:
		return 0.0
	var prediction: float = half_life / log(2.0) + extra_seconds
	return max_offset * tanh(rate * prediction / max_offset)
