extends GdUnitTestSuite

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")


func _setup_root() -> Node:
	var root := Spatial.new()
	root.name = "PlayerCrouchCollisionRoot"
	root.translation = Vector3(10000.0, 10000.0, 10000.0)
	get_tree().root.add_child(root)
	return root


func _teardown_root(root: Node) -> void:
	if root and is_instance_valid(root):
		root.queue_free()
	yield(get_tree(), "idle_frame")


func _setup_player(root: Node) -> KinematicBody:
	var player := KinematicBody.new()
	player.name = "Pilot"

	var collision := CollisionShape.new()
	collision.name = "CollisionShape"
	var capsule := CapsuleShape.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	collision.shape = capsule
	collision.transform.origin = Vector3(0, 1.0, 0)
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
	root.add_child(player)
	return player


func _spawn_ceiling(root: Node, y_center: float) -> StaticBody:
	var ceiling := StaticBody.new()
	ceiling.name = "LowCeiling"
	var shape := CollisionShape.new()
	shape.name = "CollisionShape"
	var box := BoxShape.new()
	box.extents = Vector3(1.0, 0.05, 1.0)
	shape.shape = box
	shape.transform.origin = Vector3(0, y_center, 0)
	ceiling.add_child(shape)
	root.add_child(ceiling)
	return ceiling


func test_crouch_reduces_player_capsule_height() -> void:
	var root = _setup_root()
	var player = _setup_player(root)
	yield(get_tree(), "idle_frame")

	var shape: CapsuleShape = player.get_node("CollisionShape").shape
	var collider: CollisionShape = player.get_node("CollisionShape")
	var standing_height: float = player._standing_capsule_height
	assert_bool(standing_height > 0.1).is_true()
	var standing_total = standing_height + (shape.radius * 2.0)
	var standing_bottom = collider.transform.origin.y - (standing_total * 0.5)

	player._apply_crouch_collision_state(true)
	assert_bool(shape.height < standing_height).is_true()
	assert_bool(abs(shape.height - player._crouched_capsule_height) < 0.0001).is_true()
	var crouched_total = shape.height + (shape.radius * 2.0)
	var crouched_bottom = collider.transform.origin.y - (crouched_total * 0.5)
	assert_bool(abs(crouched_bottom - standing_bottom) < 0.0001).is_true()

	player._apply_crouch_collision_state(false)
	assert_bool(abs(shape.height - standing_height) < 0.0001).is_true()
	var restored_bottom = collider.transform.origin.y - ((shape.height + (shape.radius * 2.0)) * 0.5)
	assert_bool(abs(restored_bottom - standing_bottom) < 0.0001).is_true()

	yield(_teardown_root(root), "completed")


func test_player_stays_crouched_without_headroom() -> void:
	var root = _setup_root()
	var player = _setup_player(root)
	yield(get_tree(), "idle_frame")

	player.is_crouching = true
	player._apply_crouch_collision_state(true)

	var ceiling = _spawn_ceiling(root, 2.2)
	yield(get_tree(), "physics_frame")

	assert_bool(player._has_headroom_to_stand()).is_false()
	assert_bool(player._resolve_crouch_state(false)).is_true()

	ceiling.queue_free()
	yield(get_tree(), "physics_frame")

	assert_bool(player._has_headroom_to_stand()).is_true()
	assert_bool(player._resolve_crouch_state(false)).is_false()

	yield(_teardown_root(root), "completed")
