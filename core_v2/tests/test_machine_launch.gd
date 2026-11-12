extends GdUnitTestSuite

# FD-320: un brazo rigido (balancin sobre HingeJoint) debe LANZAR al jugador parado en el:
# cuando el brazo frena en seco, el jugador conserva el momentum y sale volando.

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")

const ARM_HALF := 3.0
const PIVOT_Y := 1.2


func _setup_root() -> Spatial:
	var root := Spatial.new()
	root.name = "MachineLaunchRoot"
	root.translation = Vector3(5000.0, 5000.0, 5000.0)
	get_tree().root.add_child(root)
	return root


func _box_body(body: PhysicsBody, extents: Vector3, at: Vector3) -> PhysicsBody:
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = extents
	shape.shape = box
	body.add_child(shape)
	body.translation = at
	return body


func _setup_player(root: Node, at: Vector3) -> KinematicBody:
	var player := KinematicBody.new()
	player.name = "Pilot"
	var collision := CollisionShape.new()
	collision.name = "CollisionShape"
	var capsule := CapsuleShape.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	collision.shape = capsule
	# La capsula de Godot 3 va acostada sobre Z: se para con una rotacion en X.
	collision.transform = Transform(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.5, 0))
	player.add_child(collision)
	var camera_rig := Spatial.new()
	camera_rig.name = "CameraRig"
	player.add_child(camera_rig)
	var visual := Spatial.new()
	visual.name = "Visual"
	player.add_child(visual)
	var pivot := Spatial.new()
	pivot.name = "Pivot"
	visual.add_child(pivot)
	player.set_script(PlayerControllerScript)
	player.translation = at
	player.collision_layer = 2
	root.add_child(player)
	return player


func _build_seesaw(root: Spatial) -> RigidBody:
	root.add_child(_box_body(StaticBody.new(), Vector3(20, 0.5, 20), Vector3(0, -0.5, 0)))
	var arm := RigidBody.new()
	arm.name = "Arm"
	arm.mass = 40.0
	_box_body(arm, Vector3(ARM_HALF, 0.1, 0.8), Vector3(0, PIVOT_Y, 0))
	# Arranca inclinado: extremo -X (jugador) abajo, extremo +X (contrapeso) arriba.
	arm.rotation.z = asin(PIVOT_Y / ARM_HALF)
	root.add_child(arm)
	var hinge := HingeJoint.new()
	hinge.translation = Vector3(0, PIVOT_Y, 0)
	root.add_child(hinge)
	# Box3D no ancla joints al mundo: siempre dos cuerpos, el pivote es un StaticBody.
	var post := _box_body(StaticBody.new(), Vector3(0.1, PIVOT_Y * 0.45, 0.1), Vector3(0, PIVOT_Y * 0.45, 0))
	post.name = "Post"
	root.add_child(post)
	hinge.set_node_a(hinge.get_path_to(arm))
	hinge.set_node_b(hinge.get_path_to(post))
	return arm


func test_seesaw_launches_player() -> void:
	var root := _setup_root()
	var arm := _build_seesaw(root)
	# El jugador en el extremo -X; el contrapeso cae sobre el extremo +X.
	var player := _setup_player(root, Vector3(-ARM_HALF + 0.9, 1.0, 0))
	# Excepcion unilateral (desde la pieza): el solver rigido deja de ver al jugador
	# (kinematic = masa infinita que frena el brazo), pero el move_and_slide del jugador
	# sigue viendo la pieza y se para encima.
	arm.add_collision_exception_with(player)
	for _i in range(40):
		yield(get_tree(), "physics_frame")
	var rest_y: float = player.translation.y
	var weight := RigidBody.new()
	weight.name = "Weight"
	weight.mass = 400.0
	_box_body(weight, Vector3(0.5, 0.5, 0.5), Vector3(ARM_HALF - 0.9, PIVOT_Y + 7.0, 0))
	root.add_child(weight)
	var max_y := rest_y
	for _i in range(240):
		yield(get_tree(), "physics_frame")
		max_y = max(max_y, player.translation.y)
	# El extremo del brazo sube ~2.4 m: superar eso con holgura solo es posible volando.
	prints("[machine_launch] rest_y", rest_y, "max_y", max_y)
	assert_bool(max_y - rest_y > 5.0).is_true()
	root.queue_free()
	yield(get_tree(), "idle_frame")
