extends "res://core_v2/systems/visual/CylinderRotator.gd"

# Bahía radial (FD-322): extensión del `CylinderRotator` compartido que
# REORIENTA la geometría entre los dos modos de la nave.
#
# El `CylinderRotator` puro solo proyecta los chunks sobre el arco del cilindro
# (modo centrífugo, `spiral_blend = 1`). El cambio de modo de la bahía (consola
# del jugador, `BayGravityMount`) necesita que el MISMO nivel se lea como piso
# axial (propulsión, `spiral_blend = 0`) o como anillo centrífugo (spin,
# `spiral_blend = 1`), tal como `TerraceSpiral`/`Platforms` hacen con su
# `manual_blend`. Este script:
#
#   1. Expone `spiral_blend` (0 = axial/flat, 1 = centrífugo/arco) y lo consume
#      al proyectar cada chunk: interpola entre la posición plana y la
#      proyectada sobre el cilindro.
#   2. Se registra en `GravityWorld` (`register_rotator`) para que
#      `GravityWorld.set_spiral_blend(...)`/`set_gravity_blend(...)` — que ya
#      llaman `BayGravityMount` y `BayModeConsole` — lleguen a la geometría real
#      y no solo al estado del autoload.
#
# Determinismo: es una transformación visual derivada del estado de modo (no un
# reloj, sin RNG). El registro/desregistro sigue el patrón de `WorldRotator`.

export(float, 0.0, 1.0) var spiral_blend := 1.0 setget _set_spiral_blend

func _ready() -> void:
	._ready()
	call_deferred("_register_mode_driver")

func _exit_tree() -> void:
	var gw = get_node_or_null("/root/GravityWorld")
	if gw != null and gw.has_method("unregister_rotator"):
		gw.unregister_rotator(self)

# Adopta el modo que `BayGravityMount` ya empujó a GravityWorld antes de
# registrarse, y recién después se registra: así `register_rotator` (que lee
# `spiral_blend`) no pisa el estado del montaje.
func _register_mode_driver() -> void:
	var gw = get_node_or_null("/root/GravityWorld")
	if gw == null:
		return
	if gw.has_method("get_gravity_blend"):
		spiral_blend = clamp(float(gw.get_gravity_blend()), 0.0, 1.0)
	if gw.has_method("register_rotator"):
		gw.register_rotator(self)
	if is_inside_tree():
		_reposition_all_chunks()

func get_spiral_blend() -> float:
	return spiral_blend

func _set_spiral_blend(value: float) -> void:
	var clamped := clamp(value, 0.0, 1.0)
	if abs(clamped - spiral_blend) < 0.0001:
		return
	spiral_blend = clamped
	if is_inside_tree():
		_reposition_all_chunks()

# Blend de la proyección de un chunk: `spiral_blend = 1` es el arco del cilindro
# (centrífugo) y `spiral_blend = 0` el tendido plano (axial/propulsión). Los dos
# extremos coinciden exactamente con las transformaciones conocidas.
func _cylindrical_transform_at(flat: Vector3, local_pivot: Vector3, player_local_x: float) -> Transform:
	if spiral_blend <= 0.001:
		return Transform(Basis.IDENTITY, flat)
	var cylindrical := ._cylindrical_transform_at(flat, local_pivot, player_local_x)
	if spiral_blend >= 0.999:
		return cylindrical
	var flat_transform := Transform(Basis.IDENTITY, flat)
	var pos: Vector3 = flat_transform.origin.linear_interpolate(cylindrical.origin, spiral_blend)
	var basis: Basis = flat_transform.basis.slerp(cylindrical.basis, spiral_blend)
	return Transform(basis, pos)

# Proyección publica de un punto del plano del stream (flat) a la pose del mundo
# en el modo vigente. La usa la capa de contenido curado (atajos, sala de
# control, baliza) para quedar montada SOBRE la geometría proyectada del stream
# y seguir la reorientación del modo. El punto es rígido: su origen es el pivote.
func project_flat_point(flat: Vector3) -> Transform:
	return _cylindrical_transform_at(flat, Vector3.ZERO, _get_player_local_x())
