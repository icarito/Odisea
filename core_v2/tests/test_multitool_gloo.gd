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
	static_body.global_transform.origin = _player.global_transform.origin + Vector3(0, 0, -2)
	
	yield(get_tree(), "idle_frame")
	
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
