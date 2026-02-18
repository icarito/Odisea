extends SceneTree

const ConveyorScript = preload("res://core_v2/components/Conveyor.gd")

# Mock class extending the script to override physics queries
class TestConveyor extends ConveyorScript:
	var mock_bodies = []

	func get_overlapping_bodies():
		return mock_bodies

# Mock Physics Body
class MockBody extends Node:
	var external_velocity = Vector3.ZERO
	var external_source_static = true
	var on_floor = true
	var _name = "MockBody"

	func _init(p_name="MockBody"):
		_name = p_name

	func get_name():
		return _name

	func is_on_floor():
		return on_floor

	func set_external_velocity(v: Vector3):
		external_velocity = v

	func set_external_source_is_static(v: bool):
		external_source_static = v

	func has_method(m: String):
		return m in ["is_on_floor", "set_external_velocity", "set_external_source_is_static", "get_name"]

func _init():
	print("Running Conveyor Component Test...")

	# Run tests
	test_initialization()
	test_activation_logic()
	test_visual_logic()
	test_physics_interaction()
	test_snapshot_system()

	print("ALL CONVEYOR TESTS PASSED")
	quit()

func setup_conveyor():
	var conveyor = TestConveyor.new()
	conveyor.name = "Conveyor"

	# Create required child nodes structure as expected by Conveyor.gd

	# Belt MeshInstance with Material
	var belt = MeshInstance.new()
	belt.name = "Belt"
	conveyor.add_child(belt)

	var mat = ShaderMaterial.new()
	belt.material_override = mat
	# Assign a dummy mesh to avoid errors if surface_get_material is called (though override takes precedence)
	belt.mesh = CubeMesh.new()

	# CollisionShape
	var col = CollisionShape.new()
	col.name = "CollisionShape"
	col.shape = BoxShape.new()
	conveyor.add_child(col)

	# Ground/GroundCollision
	var ground = StaticBody.new()
	ground.name = "Ground"
	conveyor.add_child(ground)

	var ground_col = CollisionShape.new()
	ground_col.name = "GroundCollision"
	ground_col.shape = BoxShape.new()
	ground.add_child(ground_col)

	# Add to tree to trigger _ready and ensure is_inside_tree() returns true
	get_root().add_child(conveyor)

	return conveyor

func teardown_conveyor(conveyor):
	if is_instance_valid(conveyor):
		conveyor.free()

func assert_true(cond, msg):
	if not cond:
		print("FAIL: " + msg)
		quit(1)
	else:
		print("PASS: " + msg)

func assert_eq(actual, expected, msg):
	var equal = false
	if typeof(actual) == typeof(expected) and actual == expected:
		equal = true
	elif typeof(actual) == TYPE_VECTOR3 and typeof(expected) == TYPE_VECTOR3 and actual.is_equal_approx(expected):
		equal = true
	elif typeof(actual) == TYPE_COLOR and typeof(expected) == TYPE_COLOR and actual.is_equal_approx(expected):
		equal = true
	elif typeof(actual) == TYPE_REAL and typeof(expected) == TYPE_REAL and abs(actual - expected) < 0.001:
		equal = true

	if equal:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg + " Expected: " + str(expected) + " Got: " + str(actual))
		quit(1)

func test_initialization():
	print("\n--- Testing Initialization ---")
	var c = setup_conveyor()

	assert_eq(c.speed_x, 2.0, "Default speed_x is 2.0")
	assert_eq(c.is_active, true, "Default starts_active is true")
	assert_eq(c._internal_speed, 2.0, "Internal speed initialized to speed_x")

	# Check scaling applied in _ready
	var belt = c.get_node("Belt")
	# default length 8.0, width 2.0
	# belt scale: (length/8.0, 1.0, width/2.0) -> (1.0, 1.0, 1.0)
	assert_eq(belt.scale, Vector3(1, 1, 1), "Belt default scale correct")

	teardown_conveyor(c)

func test_activation_logic():
	print("\n--- Testing Activation Logic ---")
	var c = setup_conveyor()

	# 1. Deactivate
	c.set_active(false)
	assert_eq(c.is_active, false, "set_active(false) works")

	# Step to simulate deceleration
	# acceleration is 4.0. Current speed 2.0. Target 0.0.
	# dt = 0.1 -> speed should be 2.0 - 0.4 = 1.6
	c.step(0.1)
	assert_eq(c._internal_speed, 1.6, "Deceleration step 1 correct")

	c.step(0.4) # 1.6 - 1.6 = 0.0
	assert_eq(c._internal_speed, 0.0, "Deceleration to zero correct")

	# 2. Activate
	c.set_active(true)
	assert_eq(c.is_active, true, "set_active(true) works")

	c.step(0.1) # 0.0 + 0.4 = 0.4
	assert_eq(c._internal_speed, 0.4, "Acceleration step 1 correct")

	teardown_conveyor(c)

func test_visual_logic():
	print("\n--- Testing Visual Logic ---")
	var c = setup_conveyor()
	var belt = c.get_node("Belt")
	var mat = belt.material_override

	# Initial phase should be 0.0
	assert_eq(c._visual_phase, 0.0, "Initial visual phase is 0")

	# Step
	# visible_speed = (internal_speed * tiling / 8.0) * visual_speed_multiplier
	# speed=2.0, tiling=4.0 -> visible_speed = (2*4)/8 * 1 = 1.0
	c.step(0.5)
	assert_eq(c._visual_phase, 0.5, "Visual phase update correct")

	# Verify shader params
	assert_eq(mat.get_shader_param("phase"), 0.5, "Shader param 'phase' updated")
	# tiling default 4.0. Effective tiling = 4.0 * (8.0/8.0) = 4.0
	assert_eq(mat.get_shader_param("tiling"), 4.0, "Shader param 'tiling' correct")

	teardown_conveyor(c)

func test_physics_interaction():
	print("\n--- Testing Physics Interaction ---")
	var c = setup_conveyor()

	var body = MockBody.new("TestBody")
	c.mock_bodies = [body]

	# Default speed 2.0. Global transform identity.
	# world_push = global_transform.basis.x.normalized() * _internal_speed
	# basis.x is (1, 0, 0). So push is (2, 0, 0)

	c.step(0.1)
	assert_eq(body.external_velocity, Vector3(2, 0, 0), "Body receives correct velocity")
	assert_eq(body.external_source_static, false, "Body source static set to false")

	# Test require_on_floor
	c.require_on_floor = true
	body.on_floor = false
	body.external_velocity = Vector3.ZERO # Reset

	c.step(0.1)
	assert_eq(body.external_velocity, Vector3.ZERO, "Body ignored when not on floor if required")

	body.on_floor = true
	c.step(0.1)
	assert_eq(body.external_velocity, Vector3(2, 0, 0), "Body processed when on floor")

	teardown_conveyor(c)
	body.free()

func test_snapshot_system():
	print("\n--- Testing Snapshot System ---")
	var c = setup_conveyor()

	# Modify state
	c.speed_x = 5.0
	c.set_active(false) # sets is_active=false, target=0
	c._internal_speed = 3.0 # simulated intermediate state
	c._visual_phase = 10.5

	var snap = c.get_snapshot()

	# Create new conveyor and restore
	var c2 = setup_conveyor()
	c2.restore_snapshot(snap)

	# Verify
	assert_eq(c2.speed_x, 5.0, "Snapshot restored speed_x")
	assert_eq(c2.is_active, false, "Snapshot restored is_active")
	assert_eq(c2._internal_speed, 3.0, "Snapshot restored _internal_speed")
	assert_eq(c2._visual_phase, 10.5, "Snapshot restored _visual_phase")

	teardown_conveyor(c)
	teardown_conveyor(c2)
