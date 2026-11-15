extends GdUnitTestSuite

# test_multitool_gloo_parity.gd - El retículo del multi-tool predice la caída del gloo; esa
# predicción debe coincidir con el proyectil real (MultiToolGlooProjectile), no divergir.
# Regresión del review P2: la predicción reutiliza el MISMO paso balístico
# (step_ballistic) y el MISMO orden de consultas (rayo extendido + barrido de esfera con
# punto de contacto, sweep_sphere) que el proyectil. Casos: obstáculo de borde, obstáculo
# fino e impacto lateral (donde el rayo central falla y la esfera sí golpea).

const MultiToolScene = preload("res://core_v2/player/MultiToolV2.tscn")
const MultiToolCrosshairScript = preload("res://core_v2/ui/hud/MultiToolCrosshair.gd")

var _tool = null
var _crosshair = null


func before_test() -> void:
	_tool = auto_free(MultiToolScene.instance())
	add_child(_tool)
	yield(get_tree(), "idle_frame")
	# Equipar GLOO y orientar el disparo hacia -Z de forma determinista.
	_tool.set_equipped(2)
	_tool.gloo_fire_cooldown = 0.0
	_tool.global_transform = Transform(Basis(), Vector3(0, 1.2, 0))

	# Cámara propia (el crosshair necesita una para proyectar; no afecta la física).
	var cam := Camera.new()
	cam.name = "ParityCam"
	add_child(cam)
	cam.global_transform = Transform(Basis(), Vector3(0.2, 1.8, 2.0))
	cam.look_at(Vector3(0.2, 0.9, -4.0), Vector3.UP)
	cam.current = true

	_crosshair = auto_free(MultiToolCrosshairScript.new())
	add_child(_crosshair)
	_crosshair._tool = _tool
	_crosshair._player = null
	yield(get_tree(), "idle_frame")


func after_test() -> void:
	if _tool != null:
		_tool.queue_free()
	if _crosshair != null:
		_crosshair.queue_free()
	yield(get_tree(), "idle_frame")


func _wall(extents: Vector3, pos: Vector3) -> StaticBody:
	var wall := StaticBody.new()
	var cs := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = extents
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_transform = Transform(Basis(), pos)
	return wall


# Listón fino en el borde de la trayectoria (el radio de colisión decide el impacto).
func _add_edge_obstacle() -> StaticBody:
	return _wall(Vector3(0.6, 0.05, 0.05), Vector3(0.2, 0.92, -4.0))


# Pared muy fina (2 cm) perpendicular a la trayectoria.
func _add_thin_wall() -> StaticBody:
	return _wall(Vector3(0.8, 0.6, 0.01), Vector3(0.2, 0.95, -3.0))


# Barra fina al costado: el rayo central (x=0.2) falla, el cuerpo del proyectil (r=0.09)
# la roza (cara cercana en x=0.28).
func _add_side_bar() -> StaticBody:
	return _wall(Vector3(0.02, 0.5, 0.5), Vector3(0.30, 0.95, -3.0))


# Predice, dispara el proyectil real y devuelve ambos impactos. Sincrónico (sin yields):
# el proyectil se avanza a mano con el mismo dt de la física.
func _predict_and_fire() -> Dictionary:
	# En el test la pared se agrega después de que el crosshair ya venía simulando: se fuerza
	# un recálculo para partir del estado actual (en juego el obstáculo ya está en el mundo).
	_crosshair._gloo_sim_valid = false
	_crosshair._refresh_target()
	var predicted: Vector3 = _crosshair.get_last_world_point()
	var has_target: bool = _crosshair.has_target()

	_tool.fire_gloo()
	var projectile = _tool._active_gloo_projectiles.back()
	# Mismo dt que la predicción (fallback 60 si el entorno de test no reporta physics FPS).
	var dt := 1.0 / 60.0
	var stuck := false
	for _i in range(300):
		if not is_instance_valid(projectile):
			break
		projectile.step(dt)
		if projectile._is_stuck:
			stuck = true
			break
	var actual := Vector3.ZERO
	if is_instance_valid(projectile):
		actual = projectile.global_transform.origin
		projectile.queue_free()
	return {"predicted": predicted, "actual": actual, "stuck": stuck, "has_target": has_target, "dt": dt}


func _settle() -> void:
	for _i in range(3):
		yield(get_tree(), "physics_frame")


func test_prediction_matches_projectile_at_edge_obstacle() -> void:
	var wall: StaticBody = _add_edge_obstacle()
	yield(_settle(), "completed")
	var r: Dictionary = _predict_and_fire()
	assert_bool(r["has_target"]).override_failure_message("El retículo de gloo no tiene objetivo.").is_true()
	assert_bool(r["stuck"]).override_failure_message("El proyectil de gloo no impactó el listón.").is_true()
	assert_float(r["predicted"].distance_to(r["actual"])).override_failure_message(
		"La predicción debe coincidir con la caída real del gloo en el borde.").is_less(0.25)
	wall.queue_free()
	yield(get_tree(), "idle_frame")


func test_prediction_does_not_tunnel_a_thin_obstacle() -> void:
	var wall: StaticBody = _add_thin_wall()
	yield(_settle(), "completed")
	var r: Dictionary = _predict_and_fire()
	assert_bool(r["stuck"]).override_failure_message("El proyectil de gloo atravesó la pared fina.").is_true()
	assert_float(r["predicted"].distance_to(r["actual"])).override_failure_message(
		"La predicción debe impactar la pared fina en el mismo punto que el proyectil.").is_less(0.25)
	wall.queue_free()
	yield(get_tree(), "idle_frame")


func test_prediction_matches_projectile_on_lateral_impact() -> void:
	var wall: StaticBody = _add_side_bar()
	yield(_settle(), "completed")
	var r: Dictionary = _predict_and_fire()
	assert_bool(r["stuck"]).override_failure_message("El proyectil de gloo no golpeó la barra lateral.").is_true()
	assert_float(r["predicted"].distance_to(r["actual"])).override_failure_message(
		"La predicción debe coincidir con el impacto lateral (barrido de esfera).").is_less(0.25)
	# El punto guardado es el de CONTACTO en la superficie, no el centro de la esfera.
	assert_float(_crosshair.get_last_world_point().x).override_failure_message(
		"El impacto lateral debe quedar sobre la barra (x≈0.28), no en el eje del disparo.").is_greater(0.22)
	wall.queue_free()
	yield(get_tree(), "idle_frame")
