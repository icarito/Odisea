extends GdUnitTestSuite

# test_multitool_gloo_parity.gd - El retículo del multi-tool predice la caída del gloo; esa
# predicción debe coincidir con el proyectil real (MultiToolGlooProjectile), no divergir.
# Regresión del review P2: el proyectil aplica la gravedad ANTES de avanzar y extiende el
# rayo por max(_current_radius, collision_radius); la predicción reutiliza el mismo paso
# (MultiToolGlooProjectile.step_ballistic). Se cubre un obstáculo de BORDE: un listón fino
# que la trayectoria roza, donde el radio de colisión decide si hay impacto.

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


# Listón fino en el borde de la trayectoria: sin el radio de colisión la predicción (y el
# proyectil) pasarían de largo; con él, ambos impactan. Deben coincidir.
func _add_edge_obstacle() -> StaticBody:
	var wall := StaticBody.new()
	var cs := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.6, 0.05, 0.05)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	# El spawn del gloo queda ~3.5 m de este listón; la caída del arco ronda esa altura.
	wall.global_transform = Transform(Basis(), Vector3(0.2, 0.92, -4.0))
	return wall


func test_prediction_matches_projectile_at_edge_obstacle() -> void:
	var wall: StaticBody = _add_edge_obstacle()
	for _i in range(3):
		yield(get_tree(), "physics_frame")

	# Predicción del retículo (mismo paso que el proyectil).
	_crosshair._refresh_target()
	var predicted: Vector3 = _crosshair.get_last_world_point()
	assert_bool(_crosshair.has_target()).override_failure_message("El retículo de gloo no tiene objetivo.").is_true()

	# Proyectil real.
	_tool.fire_gloo()
	var projectile = _tool._active_gloo_projectiles.back()
	assert_bool(is_instance_valid(projectile)).is_true()
	var dt := 1.0 / max(1.0, float(Engine.iterations_per_second))
	var stuck := false
	for _i in range(120):
		if not is_instance_valid(projectile):
			break
		projectile.step(dt)
		if projectile._is_stuck:
			stuck = true
			break

	assert_bool(stuck).override_failure_message("El proyectil de gloo no impacto el listón.").is_true()
	var actual: Vector3 = projectile.global_transform.origin
	assert_float(predicted.distance_to(actual)).override_failure_message(
		"La predicción del crosshair debe coincidir con la caída real del gloo en el borde del obstáculo.").is_less(0.2)

	wall.queue_free()
	yield(get_tree(), "idle_frame")
