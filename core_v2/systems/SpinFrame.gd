extends Reference
class_name SpinFrame

# FD-321 — SpinFrame (v1)
#
# Marco rotante canónico de Odisea: eje Z, origen en el centro de la nave,
# geometría estática, |z| <= 4000 m. Clase pura (funciones estáticas, sin
# estado ni nodo) para que física, cámara y tests compartan exactamente la
# misma matemática. Godot 3 / GDScript 1.x, sin aleatoriedad.
#
# Convenciones:
#   - r_perp(p) es la proyección de p sobre el plano XY (el cilindro gira
#     alrededor de Z, así que la coordenada Z es axial y queda libre).
#   - "up" apunta hacia el eje (-r_hat): el suelo es la pared interior del
#     cilindro y la gravedad artificial empuja hacia afuera (+r_hat).
#   - omega > 0 gira en sentido antihorario visto desde +Z.
#
# Integración: step_free_flight usa Strang con el flujo homogéneo exacto
# (centrífugo + Coriolis resueltos en forma cerrada). No es Euler: conserva
# la integral de Jacobi ante empuje externo nulo.

const DEFAULT_G_REF := 9.8
const DEFAULT_R_REF := 240.0
const DEFAULT_R_EPS := 1e-3

# omega = sqrt(g_ref / r_ref). Referencia v1: 9.8 / 240 -> ~0.2021 rad/s
# (~1.93 rpm), velocidad de suelo ~48.5 m/s.
static func omega_for(g_ref: float = DEFAULT_G_REF, r_ref: float = DEFAULT_R_REF) -> float:
	if r_ref <= 0.0 or g_ref <= 0.0:
		return 0.0
	return sqrt(g_ref / r_ref)

# Componente radial (plano XY) del vector posición.
static func r_perp(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y, 0.0)

# Vector "arriba" local: hacia el eje. Cerca del eje (|r_perp| < r_eps) la
# dirección radial no está definida y se conserva fallback_up normalizado.
static func up(p: Vector3, fallback_up: Vector3 = Vector3.UP, r_eps: float = DEFAULT_R_EPS) -> Vector3:
	var radial: Vector3 = r_perp(p)
	if radial.length() < r_eps:
		if fallback_up.length_squared() < 1e-12:
			return Vector3.UP
		return fallback_up.normalized()
	return -radial.normalized()

# Aceleración centrífuga en el marco rotante: omega^2 * r_perp (hacia afuera).
static func a_centrif(p: Vector3, omega: float) -> Vector3:
	return (omega * omega) * r_perp(p)

# Aceleración de Coriolis: -2 * omega_hat_z x v.
static func a_coriolis(v: Vector3, omega: float) -> Vector3:
	return -2.0 * Vector3(0.0, 0.0, omega).cross(v)

# Rotación exacta de v alrededor de Z por -2*omega*dt. Es el operador de
# Coriolis sin aproximación de Euler y conserva |v| exactamente.
static func rotate_coriolis(v: Vector3, omega: float, dt: float) -> Vector3:
	return _rotate_z(v, -2.0 * omega * dt)

# Paso fijo determinista de vuelo libre. El flujo homogéneo (centrífugo +
# Coriolis) se integra en forma cerrada; extra_accel (propulsores, en el
# marco rotante) entra con medio kick al inicio y al final (Strang). Con
# extra_accel = ZERO no inyecta energía: la integral de Jacobi se conserva.
# Devuelve {"position": Vector3, "velocity": Vector3}.
static func step_free_flight(p: Vector3, v: Vector3, omega: float, dt: float, extra_accel: Vector3 = Vector3.ZERO) -> Dictionary:
	if dt <= 0.0:
		return {"position": p, "velocity": v}

	var v_kick: Vector3 = v + (0.5 * dt) * extra_accel
	var state: Dictionary = _free_flight_exact(p, v_kick, omega, dt)
	var p_next: Vector3 = state["position"]
	var v_next: Vector3 = state["velocity"]
	v_next = v_next + (0.5 * dt) * extra_accel
	return {"position": p_next, "velocity": v_next}

# Integral de Jacobi del marco rotante: 0.5|v|^2 - 0.5*omega^2*|r_perp|^2.
static func jacobi(p: Vector3, v: Vector3, omega: float) -> float:
	return 0.5 * v.length_squared() - 0.5 * (omega * omega) * r_perp(p).length_squared()

# Posición rotante -> inercial (los marcos coinciden en t = 0).
static func to_inertial_position(p: Vector3, omega: float, t: float) -> Vector3:
	return _rotate_z(p, omega * t)

# Posición inercial -> rotante (los marcos coinciden en t = 0).
static func from_inertial_position(p: Vector3, omega: float, t: float) -> Vector3:
	return _rotate_z(p, -omega * t)

# ---------------------------------------------------------------------------
# Helpers internos puros
# ---------------------------------------------------------------------------

# Rotación de un vector alrededor del eje Z.
static func _rotate_z(v: Vector3, angle: float) -> Vector3:
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)

# Solución cerrada de dp/dt = v, dv/dt = -2*omega_hat_z x v + omega^2*r_perp.
# Se resuelve pasando al marco inercial (donde la partícula va en línea recta)
# y volviendo al marco rotante: p(t) = R(-omega*t) * (p0 + V0*t),
# v(t) = R(-omega*t) * V0 - omega_hat_z x p(t), con V0 = v0 + omega_hat_z x p0.
static func _free_flight_exact(p: Vector3, v: Vector3, omega: float, dt: float) -> Dictionary:
	var omega_vec: Vector3 = Vector3(0.0, 0.0, omega)
	var v_inertial: Vector3 = v + omega_vec.cross(p)
	var p_inertial: Vector3 = p + v_inertial * dt
	var p_next: Vector3 = _rotate_z(p_inertial, -omega * dt)
	var v_next: Vector3 = _rotate_z(v_inertial, -omega * dt) - omega_vec.cross(p_next)
	return {"position": p_next, "velocity": v_next}
