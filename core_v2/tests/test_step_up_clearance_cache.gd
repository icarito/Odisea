extends GdUnitTestSuite

# Regresion del cache de sondeo de _try_step_up (PlayerControllerV2): el primer
# sondeo certifica el tramo hacia adelante como libre y no se repite mientras el
# jugador siga dentro de ese tramo y no cambie de direccion. La verificacion
# end-to-end del escalon real es el replay determinista (user://replay_*.json).

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")

const PLAYER_START_Y := 0.02


func _free_node(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()
	yield (get_tree(), "idle_frame")


func _make_static_box(center: Vector3, extents: Vector3) -> StaticBody:
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = extents
	cs.shape = box
	cs.transform.origin = center
	body.add_child(cs)
	return body


func _build_player() -> KinematicBody:
	var player := KinematicBody.new()
	player.name = "Pilot"

	var camera_rig := Spatial.new()
	camera_rig.name = "CameraRig"
	player.add_child(camera_rig)

	var yaw := Spatial.new()
	yaw.name = "Yaw"
	camera_rig.add_child(yaw)

	var pitch := Spatial.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)

	var spring_arm := SpringArm.new()
	spring_arm.name = "SpringArm"
	pitch.add_child(spring_arm)

	var camera := Camera.new()
	camera.name = "Camera"
	spring_arm.add_child(camera)

	var visual := Spatial.new()
	visual.name = "Visual"
	player.add_child(visual)

	var pivot := Spatial.new()
	pivot.name = "Pivot"
	visual.add_child(pivot)

	var collision := CollisionShape.new()
	collision.name = "CollisionShape"
	var capsule := CapsuleShape.new()
	capsule.radius = 0.35
	capsule.height = 1.2
	collision.shape = capsule
	collision.transform.origin = Vector3(0, 0.6, 0)
	player.add_child(collision)

	player.set_script(PlayerControllerScript)
	player.collision_layer = 1
	player.collision_mask = 1
	return player


func _build_flat_world() -> Node:
	var root := Node.new()
	root.name = "StepUpCacheRoot"
	get_tree().root.add_child(root)
	root.add_child(_make_static_box(Vector3(0, -0.5, 0), Vector3(10, 0.5, 10)))

	var player := _build_player()
	player.set_physics_process(false)
	root.add_child(player)
	player.translation = Vector3(0, PLAYER_START_Y, 0)
	return root


func _settle_physics() -> void:
	# El SessionManager autoload toma al jugador del grupo "player" y lo reposiciona en
	# su _physics_process; apagarlo para que el test controle la pose.
	var sm = get_node_or_null("/root/SessionManager")
	if sm:
		sm.set_physics_process(false)
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "physics_frame")
	yield (get_tree(), "physics_frame")


func test_flat_ground_certifies_clearance_and_skips_reprobe() -> void:
	var root = _build_flat_world()
	var player: KinematicBody = root.get_node("Pilot")
	yield (_settle_physics(), "completed")

	var first: Dictionary = player._try_step_up(Vector3(0, 0, -1))
	assert_bool(first.stepped).is_false()
	assert_float(player._step_clear_dist).is_greater(0.0)

	var cached_dist: float = player._step_clear_dist
	var second: Dictionary = player._try_step_up(Vector3(0, 0, -1))
	assert_bool(second.stepped).is_false()
	assert_float(player._step_clear_dist).is_equal(cached_dist)

	yield (_free_node(root), "completed")


func test_direction_change_forces_reprobe() -> void:
	var root = _build_flat_world()
	var player: KinematicBody = root.get_node("Pilot")
	yield (_settle_physics(), "completed")

	player._try_step_up(Vector3(0, 0, -1))
	assert_float(player._step_clear_dir.dot(Vector3(0, 0, -1))).is_greater(0.99)

	# Otra direccion: el cache viejo no vale; se re-sondea y se re-certifica.
	player._try_step_up(Vector3(1, 0, 0))
	assert_float(player._step_clear_dir.dot(Vector3(1, 0, 0))).is_greater(0.99)

	yield (_free_node(root), "completed")
