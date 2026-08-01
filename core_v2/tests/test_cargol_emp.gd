extends GdUnitTestSuite

# test_cargol_emp.gd
# Tests defensive Cargol EMP functionality and DDC stunning.

const CargolDefensive = preload("res://core_v2/actors/CargolDefensiveV1.gd")
const DDCDrone = preload("res://core_v2/actors/DDCDroneV2.gd")

func test_initial_state_and_follow() -> void:
	var cargol = CargolDefensive.new()
	add_child(cargol)
	
	# Initial state should be IDLE
	assert_int(cargol.state).is_equal(cargol.State.IDLE)
	
	# Mock player
	var player = KinematicBody.new()
	player.add_to_group("player")
	add_child(player)
	player.global_transform.origin = Vector3(10, 0, 10)
	
	cargol._find_player()
	assert_object(cargol.player_node).is_equal(player)
	
	# Follow should approach player (shoulder height 1.5m, follow distance 2m)
	cargol.step(0.1)
	assert_bool(cargol.global_transform.origin.distance_to(player.global_transform.origin) < 15.0).is_true()
	
	cargol.free()
	player.free()

func test_emp_state_sequence_and_stun() -> void:
	var cargol = CargolDefensive.new()
	add_child(cargol)
	
	var ddc_in_range = DDCDrone.new()
	ddc_in_range.name = "DDC_In_Range"
	add_child(ddc_in_range)
	ddc_in_range.global_transform.origin = cargol.global_transform.origin + Vector3(2, 0, 0) # 2m (in range)
	
	var ddc_out_range = DDCDrone.new()
	ddc_out_range.name = "DDC_Out_Range"
	add_child(ddc_out_range)
	ddc_out_range.global_transform.origin = cargol.global_transform.origin + Vector3(10, 0, 0) # 10m (out of range)

	# Trigger EMP
	cargol.fire_emp()
	assert_int(cargol.state).is_equal(cargol.State.EMP_CHARGING)
	assert_float(cargol.emp_charging_timer).is_greater(0.0)
	
	# Step through EMP_CHARGING (0.3s)
	cargol.step(0.35)
	
	# Should trigger blast and transition to EMP_FIRING
	assert_int(cargol.state).is_equal(cargol.State.EMP_FIRING)
	assert_float(cargol.cooldown_timer).is_equal(8.0)
	
	# Verify DDC stunning
	# DDC in range should be STUNNED (current_state 8)
	assert_int(ddc_in_range.current_state).is_equal(8) # State.STUNNED
	
	# DDC out of range should NOT be STUNNED
	assert_int(ddc_out_range.current_state).is_not_equal(8)
	
	# Step through EMP_FIRING (0.2s)
	cargol.step(0.25)
	assert_int(cargol.state).is_equal(cargol.State.EMP_COOLDOWN)
	
	cargol.free()
	ddc_in_range.free()
	ddc_out_range.free()
