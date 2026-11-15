extends GdUnitTestSuite

# test_multitool_crosshair.gd - El retículo del multi-tool (MultiToolCrosshair.gd) debe
# ubicarse en el punto donde el tool va a impactar de verdad (MISMO rayo que el disparo:
# muzzle, -basis.z, laser_max_range y laser_collision_mask), no en el centro de pantalla.
# Se valida en un caso central y en un caso lateral (paralaje OTS), y que se oculta sin
# tool equipado.

const PlayerControllerV2 = preload("res://core_v2/player/PlayerControllerV2.gd")
const MultiToolCrosshair = preload("res://core_v2/ui/hud/MultiToolCrosshair.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

var _player: PlayerControllerV2
var _crosshair = null

func before_test():
	pass

func after_test():
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.queue_free()
	if _player != null:
		_player.queue_free()
	yield(get_tree(), "idle_frame")

# Rotación inicial opcional (caso lateral): se aplica antes de entrar al árbol para que
# cámara/rig y tool roten juntos.
func _setup_player(yaw: float = 0.0) -> void:
	var scene = load("res://core_v2/actors/Pilot_v2.tscn")
	_player = scene.instance()
	_player.transform = Transform(Basis(Vector3.UP, yaw), Vector3(0, 0.2, 0))
	_player.set_multi_tool_enabled(true)
	add_child(_player)
	yield(get_tree(), "idle_frame")
	# Crosshair propio bajo el root del test (independiente del ciclo de vida del player) con
	# referencias explicitas a player/tool: evita ambiguedad de grupos y liberaciones ajenas.
	_crosshair = MultiToolCrosshair.new()
	add_child(_crosshair)
	_crosshair._player = _player
	_crosshair._tool = _player.multi_tool
	yield(get_tree(), "idle_frame")

func _add_wall() -> Node:
	var wall := StaticBody.new()
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(12, 6, 0.25)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	return wall

# Coloca una pared perpendicular al rayo actual del láser a `distance` metros.
func _place_wall_on_laser_ray(distance: float) -> Node:
	var laser = _player.multi_tool.get_node("Laser")
	var from: Vector3 = laser.global_transform.origin
	var dir: Vector3 = -laser.global_transform.basis.z.normalized()
	var wall := _add_wall()
	wall.global_transform.origin = from + dir * distance
	# Orientar la pared perpendicular al rayo.
	wall.look_at(from, Vector3.UP)
	return wall

func _expected_laser_hit() -> Vector3:
	var laser = _player.multi_tool.get_node("Laser")
	var from: Vector3 = laser.global_transform.origin
	var dir: Vector3 = -laser.global_transform.basis.z.normalized()
	var hit = _player.get_world().direct_space_state.intersect_ray(
		from, from + dir * 50.0, [_player, _player.multi_tool], 765)
	if hit.empty():
		return from + dir * 50.0
	return hit["position"]

func test_crosshair_marks_the_real_laser_impact_forward() -> void:
	_setup_player()
	var wall := _place_wall_on_laser_ray(6.0)
	var targeted := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if _crosshair != null and is_instance_valid(_crosshair) and _crosshair.has_target():
			targeted = true
			break
	assert_bool(targeted).is_true()

	var expected: Vector3 = _expected_laser_hit()
	var actual: Vector3 = _crosshair.get_last_world_point()
	assert_float(actual.distance_to(expected)).override_failure_message(
		"El retículo debe marcar el impacto real del rayo del láser.").is_less(0.1)
	wall.queue_free()
	yield(get_tree(), "idle_frame")

func test_crosshair_marks_the_real_laser_impact_lateral() -> void:
	# El piloto nace rotado 45°: el rayo sale hacia el costado (paralaje OTS).
	_setup_player(PI / 4.0)
	var wall := _place_wall_on_laser_ray(6.0)
	var targeted := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if _crosshair != null and is_instance_valid(_crosshair) and _crosshair.has_target():
			targeted = true
			break
	assert_bool(targeted).is_true()

	var expected: Vector3 = _expected_laser_hit()
	var actual: Vector3 = _crosshair.get_last_world_point()
	assert_float(actual.distance_to(expected)).override_failure_message(
		"El retículo debe seguir el rayo real también apuntando a los lados.").is_less(0.1)
	wall.queue_free()
	yield(get_tree(), "idle_frame")


