extends GdUnitTestSuite

# test_multitool_laser.gd

const PlayerControllerV2 = preload("res://core_v2/player/PlayerControllerV2.gd")
const MultiToolLaser = preload("res://core_v2/player/MultiToolLaser.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

var _player: PlayerControllerV2
var _laser: MultiToolLaser

func before_test():
	var scene = load("res://core_v2/actors/Pilot_v2.tscn")
	_player = scene.instance()
	_player.set_multi_tool_enabled(true)
	add_child(_player)
	
	# Wait for setup
	yield(get_tree(), "idle_frame")
	_laser = _player.multi_tool.get_node("Laser")

func after_test():
	_player.queue_free()

func test_laser_firing_state():
	var input = InputDataV2.new()
	
	# Initial state: not firing
	assert_bool(_laser.visible).is_false()
	
	# Fire laser
	input.tool_fire_primary = true
	_player.multi_tool.step(1.0/60.0, input)
	
	assert_bool(_laser.visible).is_true()
	assert_bool(_laser._raycast.enabled).is_true()
	
	# Stop firing
	input.tool_fire_primary = false
	_player.multi_tool.step(1.0/60.0, input)
	
	assert_bool(_laser.visible).is_false()
	assert_bool(_laser._raycast.enabled).is_false()

func test_laser_raycast_collision():
	# Create a static body to collide with
	var static_body = StaticBody.new()
	var collision_shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(10, 10, 1)
	collision_shape.shape = box
	static_body.add_child(collision_shape)
	add_child(static_body)
	var visual_forward = _player.get_node("Visual/Pivot").global_transform.basis.z.normalized()
	static_body.global_transform.origin = _player.global_transform.origin + visual_forward * 5.0
	
	yield(get_tree(), "idle_frame")
	
	var input = InputDataV2.new()
	input.tool_fire_primary = true
	
	# Step player and multi-tool
	_player.step(1.0/60.0, input)
	_laser._physics_process(1.0/60.0) # Explicit call since it might be throttled or not running in test env same way
	
	assert_bool(_laser._raycast.is_colliding()).is_true()
	assert_bool(_laser._impact_particles.emitting).is_true()
	
	# Check beam mesh scale (it should be roughly distance to collision)
	var expected_len = _laser.global_transform.origin.distance_to(_laser._raycast.get_collision_point())
	assert_float(_laser._beam_mesh.scale.z).is_between(expected_len - 0.1, expected_len + 0.1)
	
	static_body.queue_free()
