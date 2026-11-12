extends GdUnitTestSuite

# FD-320: un brazo rigido (balancin sobre HingeJoint) debe LANZAR al jugador parado en el:
# cuando el brazo frena en seco, el jugador conserva el momentum y sale volando.

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")
const MachinePart = preload("res://core_v2/props/machines/MachinePart.gd")
const MachineHinge = preload("res://core_v2/props/machines/MachineHinge.gd")

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
	var arm := MachinePart.new()
	arm.name = "Arm"
	arm.size = Vector3(ARM_HALF * 2.0, 0.2, 1.6)
	arm.density = 20.0
	arm.translation = Vector3(0, PIVOT_Y, 0)
	# Arranca inclinado: extremo -X (jugador) abajo, extremo +X (contrapeso) arriba.
	arm.rotation.z = asin(PIVOT_Y / ARM_HALF)
	root.add_child(arm)
	var hinge := MachineHinge.new()
	hinge.name = "Hinge"
	hinge.translation = Vector3(0, PIVOT_Y, 0)
	hinge.body_a_path = NodePath("../Arm")
	root.add_child(hinge)
	return arm


func _spawn_weight(root: Spatial, held: bool) -> RigidBody:
	var weight := MachinePart.new()
	weight.name = "Weight"
	weight.size = Vector3(1, 1, 1)
	weight.density = 400.0
	weight.held = held
	weight.translation = Vector3(ARM_HALF - 0.9, PIVOT_Y + 7.0, 0)
	root.add_child(weight)
	return weight


func _settle(frames: int) -> void:
	for _i in range(frames):
		yield(get_tree(), "physics_frame")


func test_seesaw_launches_player() -> void:
	var root := _setup_root()
	_build_seesaw(root)
	# El jugador en el extremo -X; el contrapeso retenido sobre el extremo +X.
	var player := _setup_player(root, Vector3(-ARM_HALF + 0.9, 1.0, 0))
	var weight: RigidBody = _spawn_weight(root, true)
	yield(_settle(40), "completed")
	var rest_y: float = player.translation.y
	assert_float(weight.translation.y).is_equal_approx(PIVOT_Y + 7.0, 0.01)  # retenido: no cae
	weight.release()
	var max_y := rest_y
	for _i in range(240):
		yield(get_tree(), "physics_frame")
		max_y = max(max_y, player.translation.y)
	# El extremo del brazo sube ~2.4 m: superar eso con holgura solo es posible volando.
	prints("[machine_launch] rest_y", rest_y, "max_y", max_y)
	assert_bool(max_y - rest_y > 5.0).is_true()
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_hinge_limit_stops_arm() -> void:
	var root := _setup_root()
	var arm := MachinePart.new()
	arm.name = "Arm"
	arm.size = Vector3(4, 0.2, 1)
	# Brazo en voladizo: cuelga del extremo, la gravedad lo quiere llevar a -90 grados.
	arm.translation = Vector3(2, 5, 0)
	root.add_child(arm)
	var hinge := MachineHinge.new()
	hinge.translation = Vector3(0, 5, 0)
	hinge.body_a_path = NodePath("../Arm")
	hinge.use_limit = true
	hinge.limit_lower_deg = -30.0
	hinge.limit_upper_deg = 30.0
	root.add_child(hinge)
	yield(_settle(180), "completed")
	prints("[machine_launch] limit arm rot", arm.rotation_degrees.z)
	assert_float(abs(arm.rotation_degrees.z)).is_between(20.0, 40.0)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_hinge_motor_spins_when_active() -> void:
	var root := _setup_root()
	var arm := MachinePart.new()
	arm.name = "Arm"
	arm.size = Vector3(4, 0.2, 1)
	arm.translation = Vector3(0, 5, 0)  # balanceado sobre el eje
	root.add_child(arm)
	var hinge := MachineHinge.new()
	hinge.translation = Vector3(0, 5, 0)
	hinge.body_a_path = NodePath("../Arm")
	hinge.motor_speed = 3.0
	root.add_child(hinge)
	yield(_settle(60), "completed")
	assert_float(abs(arm.angular_velocity.z)).is_less(0.2)  # apagado: quieto
	hinge.set_active(true)
	yield(_settle(120), "completed")
	prints("[machine_launch] motor ang vel", arm.angular_velocity)
	assert_float(abs(arm.angular_velocity.z)).is_between(2.0, 4.0)
	root.queue_free()
	yield(get_tree(), "idle_frame")
