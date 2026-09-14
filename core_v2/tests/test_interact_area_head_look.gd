extends GdUnitTestSuite

# La zona interactuable del jugador sigue parcialmente a la cabeza de Elias (head-look del animator):
# a los costados y arriba/abajo, girando a la altura de la cabeza.

const PlayerScript = preload("res://core_v2/player/PlayerControllerV2.gd")
const SHAPE_ORIGIN := Vector3(0.0, 1.5, 0.5) # como en Pilot_v2.tscn


class FakeAnimator extends Spatial:
	var look := Vector2.ZERO
	func get_head_look() -> Vector2:
		return look


func _player_with_area() -> Array:
	var player = PlayerScript.new() # sin arbol: no corre _ready ni sus onready
	var animator = FakeAnimator.new()
	var area := Area.new()
	var shape := CollisionShape.new()
	shape.transform.origin = SHAPE_ORIGIN
	area.add_child(shape)
	animator.add_child(area)
	player.animator = animator
	player._interact_area = area
	player._remember_interact_area_rest()
	return [player, animator, area]


func _shape_center(area: Area) -> Vector3:
	return area.transform.xform(SHAPE_ORIGIN)


func test_the_interact_area_turns_and_tilts_with_the_head() -> void:
	var parts: Array = _player_with_area()
	var player = parts[0]
	var animator = parts[1]
	var area: Area = parts[2]
	player.interact_follows_head = 1.0

	# Mirando a la derecha (yaw positivo, el modelo mira hacia +Z): la zona se va hacia +X.
	animator.look = Vector2(deg2rad(45.0), 0.0)
	player._aim_interact_area()
	assert_float(_shape_center(area).x).is_greater(0.3)
	# Gira a la altura de la cabeza: ese punto no se mueve.
	assert_vector3(area.transform.xform(Vector3(0.0, 1.5, 0.0))).is_equal_approx(Vector3(0.0, 1.5, 0.0), Vector3.ONE * 0.001)

	# Mirando arriba: la zona sube delante de la cabeza, sin hundirse.
	animator.look = Vector2(0.0, deg2rad(30.0))
	player._aim_interact_area()
	assert_float(_shape_center(area).y).is_greater(1.7)
	assert_float(_shape_center(area).x).is_equal_approx(0.0, 0.001)

	# Parcial: con 0 no sigue a la cabeza.
	player.interact_follows_head = 0.0
	player._aim_interact_area()
	assert_vector3(_shape_center(area)).is_equal_approx(SHAPE_ORIGIN, Vector3.ONE * 0.001)

	# Empujando queda al frente del cuerpo aunque la cabeza gire.
	player.interact_follows_head = 1.0
	player.is_pushing = true
	animator.look = Vector2(deg2rad(45.0), deg2rad(20.0))
	player._aim_interact_area()
	assert_vector3(_shape_center(area)).is_equal_approx(SHAPE_ORIGIN, Vector3.ONE * 0.001)

	animator.free()
	player.free()
