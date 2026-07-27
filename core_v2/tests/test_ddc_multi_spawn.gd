extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# test_ddc_multi_spawn.gd
# Unit tests for the DDCSpawner system.

const DDCSpawner = preload("res://core_v2/systems/DDCSpawner.gd")
const DDCContainment = preload("res://core_v2/actors/DDCContainmentV1.gd")

func test_spawner_progressive_limit_and_intervals() -> void:
	var spawner = DDCSpawner.new()
	
	# Create mock spawn gates as children BEFORE adding spawner to the tree,
	# so that _ready() automatically discovers it correctly!
	var gate1 = Position3D.new()
	gate1.name = "Gate1"
	gate1.translation = Vector3(10, 0, 0)
	spawner.add_child(gate1)
	
	add_child(spawner)
	
	# Set configuration
	spawner.spawn_interval = 2.0
	spawner.max_simultaneous_ddc = 3
	spawner.progressive_limit = true
	spawner.progressive_escalation_interval = 5.0
	spawner.active = true
	
	# Initially, 1 active drone limit, and list is empty -> should spawn 1 DDC immediately
	# since active count is 0 and _spawn_timer is reset.
	spawner._physics_process(0.1)
	
	var active_ddcs = spawner.get_active_ddcs()
	assert_int(active_ddcs.size()).is_equal(1)
	assert_bool(is_instance_valid(active_ddcs[0])).is_true()
	assert_vector3(active_ddcs[0].global_transform.origin).is_equal(Vector3(10, 0, 0))
	
	# Step by 3.0s (past spawn_interval), but limit is still 1! So it should NOT spawn a second one.
	spawner._physics_process(3.0)
	assert_int(spawner.get_active_ddcs().size()).is_equal(1)
	
	# Step by another 2.1s (total 5.2s, past progressive_escalation_interval = 5.0s)
	# The limit should now scale up to 2.
	# Since there is only 1 active drone and spawn_timer was reset, 
	# spawn_timer should advance and spawn when it hits spawn_interval (2.0s).
	# Let's step and verify it spawns a second drone.
	spawner._physics_process(2.1)
	assert_int(spawner.get_active_ddcs().size()).is_equal(2)
	
	# Queue free/destroy one of the spawned drones to check cleanup
	var first_drone = active_ddcs[0]
	first_drone.free()
	
	# Step physics process -> spawner should detect freed drone and clean up active array
	spawner._physics_process(0.1)
	assert_int(spawner.get_active_ddcs().size()).is_equal(1)
	
	# Cleanup remaining drones and spawner
	for ddc in spawner.get_active_ddcs():
		if is_instance_valid(ddc):
			ddc.free()
	spawner.free()
