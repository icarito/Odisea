extends GdUnitTestSuite

# test_multitool_gloo.gd

const PlayerControllerV2 = preload("res://core_v2/player/PlayerControllerV2.gd")
const MultiToolV2 = preload("res://core_v2/player/MultiToolV2.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

var _player: PlayerControllerV2
var _multi_tool: MultiToolV2

func before_test():
	var scene = load("res://core_v2/actors/Pilot_v2.tscn")
	_player = scene.instance()
	_player.set_multi_tool_enabled(true)
	add_child(_player)
	
	# Wait for setup
	yield(get_tree(), "idle_frame")
	_multi_tool = _player.multi_tool
	
	# Switch to Gloo mode
	var input = InputDataV2.new()
	input.tool_next_mode = true
	_multi_tool.step(1.0/60.0, input)
	assert_int(_multi_tool.current_mode).is_equal(1) # GLOO

func after_test():
	_player.queue_free()

func test_gloo_firing():
	var initial_projectiles = _multi_tool._active_gloo_projectiles.size()
	
	_multi_tool.fire_gloo()
	
	assert_int(_multi_tool._active_gloo_projectiles.size()).is_equal(initial_projectiles + 1)
	
	var projectile = _multi_tool._active_gloo_projectiles.back()
	assert_bool(is_instance_valid(projectile)).is_true()
	assert_bool(projectile.get_parent() != null).is_true()

func test_gloo_max_count():
	_multi_tool.gloo_fire_cooldown = 0.0
	var max_count = _multi_tool.max_gloo_projectiles
	
	for i in range(max_count + 2):
		_multi_tool.fire_gloo()
		yield(get_tree(), "idle_frame")
		
	assert_int(_multi_tool._active_gloo_projectiles.size()).is_equal(max_count)

func test_gloo_sticking():
	# Create a static body to stick to
	var static_body = StaticBody.new()
	var collision_shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(10, 10, 1)
	collision_shape.shape = box
	static_body.add_child(collision_shape)
	add_child(static_body)
	var visual_forward = _player.get_node("Visual/Pivot").global_transform.basis.z.normalized()
	static_body.global_transform.origin = _player.global_transform.origin + visual_forward * 2.0
	
	yield(get_tree(), "idle_frame")
	
	_player.step(1.0/60.0, InputDataV2.new())
	_multi_tool.fire_gloo()
	var projectile = _multi_tool._active_gloo_projectiles.back()
	
	# Wait for it to fly and hit (it's only 2m away at 15m/s)
	for i in range(10):
		projectile._physics_process(1.0/60.0)
		if projectile._is_stuck:
			break
			
	assert_bool(projectile._is_stuck).is_true()
	assert_vector3(projectile.velocity).is_equal(Vector3.ZERO)
	
	static_body.queue_free()

func test_gloo_does_not_stick_to_player():
	var projectile = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	add_child(projectile)
	
	assert_bool(projectile._should_stick_to(_player)).is_false()
	
	projectile.queue_free()

func test_gloo_uses_pin_joint_for_bridged_bodies():
	var projectile = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var a := RigidBody.new()
	var b := StaticBody.new()
	add_child(a)
	add_child(b)
	add_child(projectile)
	
	projectile._create_glue_joint(a, b)
	
	assert_int(projectile._glue_joints.size()).is_equal(1)
	assert_bool(projectile._glue_joints[0] is PinJoint).is_true()
	assert_bool(projectile._glue_joints[0].get("collision/exclude_nodes")).is_false()
	assert_int(a.mode).is_equal(RigidBody.MODE_RIGID)
	
	projectile.queue_free()
	a.queue_free()
	b.queue_free()

func test_gloo_does_not_duplicate_pin_joint_for_same_pair():
	var projectile_a = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var projectile_b = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var a := RigidBody.new()
	var b := RigidBody.new()
	add_child(a)
	add_child(b)
	add_child(projectile_a)
	add_child(projectile_b)
	
	projectile_a._create_glue_joint(a, b)
	projectile_b._create_glue_joint(a, b)
	
	assert_int(projectile_a._glue_joints.size()).is_equal(1)
	assert_int(projectile_b._glue_joints.size()).is_equal(0)
	
	projectile_a.queue_free()
	projectile_b.queue_free()
	a.queue_free()
	b.queue_free()

func test_gloo_attached_to_dynamic_body_has_no_solid_collision():
	var projectile = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var body := RigidBody.new()
	add_child(body)
	add_child(projectile)
	
	projectile._stick_at(body, body.global_transform.origin, Vector3.UP)
	
	assert_int(projectile.collision_layer).is_equal(0)
	assert_int(projectile.collision_mask).is_equal(0)
	assert_bool(projectile._collision_shape.disabled).is_true()
	
	projectile.queue_free()
	body.queue_free()

func test_gloo_attached_to_static_body_collides_with_player_layer():
	var projectile = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var body := StaticBody.new()
	add_child(body)
	add_child(projectile)
	
	projectile._stick_at(body, body.global_transform.origin, Vector3.UP)
	
	assert_int(projectile.collision_layer).is_equal(64)
	assert_bool((projectile.collision_mask & 2) != 0).is_true()
	assert_bool(projectile._collision_shape.disabled).is_false()
	
	projectile.queue_free()
	body.queue_free()

func test_gloo_laser_heat_spreads_to_nearby_blob():
	var projectile_a = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var projectile_b = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	add_child(projectile_a)
	add_child(projectile_b)
	projectile_a.global_transform.origin = Vector3.ZERO
	projectile_b.global_transform.origin = Vector3(0.2, 0.0, 0.0)
	projectile_a.laser_heat_spread_radius = 0.5
	
	projectile_a.laser_hit()
	
	assert_bool(projectile_a._is_laser_heating).is_true()
	assert_bool(projectile_b._is_laser_heating).is_true()
	
	projectile_a.queue_free()
	projectile_b.queue_free()

func test_gloo_merges_nearby_blob_on_same_anchor():
	var projectile_a = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var projectile_b = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	var body := StaticBody.new()
	add_child(body)
	add_child(projectile_a)
	add_child(projectile_b)
	projectile_a.global_transform.origin = Vector3.ZERO
	projectile_b.global_transform.origin = Vector3(0.1, 0.0, 0.0)
	projectile_a._anchor_collider = body
	projectile_b._anchor_collider = body
	projectile_a.blob_radius = 0.35
	projectile_b.blob_radius = 0.35
	projectile_a.merge_distance = 0.25
	
	projectile_a._try_merge_nearby_gloo()
	
	assert_bool(projectile_a.blob_radius > 0.35).is_true()
	assert_bool(projectile_b.is_queued_for_deletion()).is_true()
	
	projectile_a.queue_free()
	body.queue_free()

# ---------------------------------------------------------------------------
# Puente / escalera: el gloo ENDURECIDO debe sostener al jugador.
# Estos tests dejan caer un Pilot_v2 real (su propio gravity + move_and_slide) sobre
# gloo curado, asi que fallan si el gloo deja de colisionar contra el jugador.

func _add_static_slab(slab: StaticBody, extents: Vector3, origin: Vector3) -> void:
	var cs := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = extents
	cs.shape = box
	slab.add_child(cs)
	add_child(slab)
	slab.global_transform.origin = origin

func _add_cured_gloo_on(anchor, pos: Vector3, normal: Vector3):
	var gloo = load("res://core_v2/player/MultiToolGloo.tscn").instance()
	add_child(gloo)
	yield(get_tree(), "idle_frame")
	gloo._stick_at(anchor, pos, normal)
	gloo.cure_time = 0.01
	gloo.step(0.05)
	return gloo

func test_gloo_cured_blob_supports_player_as_bridge() -> void:
	# Puente a ras de piso: el jugador real (su propio gravity/move_and_slide) se para
	# sobre el gloo curado, no sobre el piso.
	var slab := StaticBody.new()
	_add_static_slab(slab, Vector3(6, 0.05, 6), Vector3(100, 0, 0))
	var gloo = yield(_add_cured_gloo_on(slab, Vector3(100, 0.05, 0), Vector3.UP), "completed")

	var player = load("res://core_v2/actors/Pilot_v2.tscn").instance()
	add_child(player)
	player.global_transform.origin = Vector3(100, 2.0, 0)
	yield(get_tree(), "idle_frame")
	for _i in range(150):
		yield(get_tree(), "physics_frame")

	# El piso esta a y=0.05; el gloo curado suma ~0.43 de alto. Pararse en el piso
	# daria y<=0.05: exigir mas prueba que el jugador quedo SOBRE el gloo.
	print("BRIDGE_PLAYER y=", player.global_transform.origin.y)
	assert_float(player.global_transform.origin.y).is_greater(0.25)

	player.queue_free()
	gloo.queue_free()
	slab.queue_free()

func test_gloo_cured_blobs_support_player_as_ladder() -> void:
	# Escalera: 3 blobs curados en altura sobre un pedestal ancho. El jugador debe
	# quedar apoyado sobre el blob mas alto, no sobre el pedestal.
	var heights := [0.0, 0.7, 1.4]
	var gloo_blobs := []
	var slabs := []
	for h in heights:
		var slab := StaticBody.new()
		_add_static_slab(slab, Vector3(6, 0.05, 6), Vector3(200, float(h), 0))
		slabs.append(slab)
		var gloo = yield(_add_cured_gloo_on(slab, Vector3(200, float(h) + 0.05, 0), Vector3.UP), "completed")
		gloo_blobs.append(gloo)

	var top_h: float = 1.4
	var player = load("res://core_v2/actors/Pilot_v2.tscn").instance()
	add_child(player)
	player.global_transform.origin = Vector3(200, top_h + 2.2, 0)
	yield(get_tree(), "idle_frame")
	for _i in range(180):
		yield(get_tree(), "physics_frame")

	# Tope del blob superior ~= 1.45 + 0.08 + 0.35 = 1.88. Exigir mas que el pedestal
	# pelado (1.45) confirma que se apoya en el gloo mas alto.
	print("LADDER_PLAYER y=", player.global_transform.origin.y, " top_blob_top=1.88")
	assert_float(player.global_transform.origin.y).is_greater(1.6)

	player.queue_free()
	for gloo in gloo_blobs:
		if gloo != null:
			gloo.queue_free()
	for slab in slabs:
		slab.queue_free()
