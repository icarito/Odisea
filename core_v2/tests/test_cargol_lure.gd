extends GdUnitTestSuite

# test_cargol_lure.gd
# Tests defensive Cargol Lure attraction, DDC reaction, and touch-stun mechanics.

const CargolDefensive = preload("res://core_v2/actors/CargolDefensiveV1.gd")
const DDCDrone = preload("res://core_v2/actors/DDCDroneV2.gd")

func test_lure_deployment_and_attraction() -> void:
	var cargol = CargolDefensive.new()
	add_child(cargol)
	
	# Mock player
	var player = KinematicBody.new()
	player.add_to_group("player")
	add_child(player)
	player.global_transform.origin = Vector3(0, 0, 0)
	cargol.player_node = player
	
	# Create DDC drone in range of lure (e.g. 10m away)
	var ddc = DDCDrone.new()
	add_child(ddc)
	ddc.global_transform.origin = Vector3(10, 0, 0)
	ddc._player_ref = player
	
	# Deploy Lure at 15m away
	var target_pos = Vector3(15, 0, 0)
	cargol.deploy_lure(target_pos)
	
	# Cargol state should be LURE_DEPLOYED
	assert_int(cargol.state).is_equal(cargol.State.LURE_DEPLOYED)
	assert_float(cargol.lure_timer).is_equal(5.0)
	assert_float(cargol.cooldown_timer).is_equal(15.0)
	
	# Run physics/checks: Cargol moves to target pos
	cargol.step(0.1)
	assert_vector3(cargol.target_position).is_equal(target_pos)
	
	# DDC drone should check detection and attract to the Lure
	# The lure is at distance global_transform.origin.distance_to(cargol.global_transform.origin)
	# which is 10m. This is within lure_range (20m).
	ddc._check_detection(0.1)
	
	# DDC drone should enter ALERT state due to Lure presence
	assert_int(ddc.current_state).is_equal(4) # State.ALERT
	assert_vector3(ddc._last_seen_player_pos).is_equal(cargol.global_transform.origin)
	
	cargol.free()
	player.free()
	ddc.free()

func test_lure_touch_stun_and_return() -> void:
	var cargol = CargolDefensive.new()
	add_child(cargol)
	
	var player = KinematicBody.new()
	player.add_to_group("player")
	add_child(player)
	player.global_transform.origin = Vector3(0, 0, 0)
	cargol.player_node = player
	
	# Deploy Lure
	var target_pos = Vector3(10, 0, 0)
	cargol.deploy_lure(target_pos)
	
	# Move Cargol to target
	cargol.global_transform.origin = target_pos
	
	# Create a DDC drone touching Cargol (distance 0.5m < 1.2m)
	var ddc = DDCDrone.new()
	add_child(ddc)
	ddc.global_transform.origin = target_pos + Vector3(0.5, 0, 0)
	
	# Step Cargol: should detect touch and get STUNNED
	cargol.step(0.1)
	assert_int(cargol.state).is_equal(cargol.State.STUNNED)
	assert_float(cargol.stun_timer).is_equal(6.0)
	
	# Step through STUNNED state (6.0s)
	cargol.step(6.1)
	
	# After stun, state should be RETURNING
	assert_int(cargol.state).is_equal(cargol.State.RETURNING)
	
	# Move Cargol back near player to recover
	cargol.global_transform.origin = player.global_transform.origin + Vector3(1.0, 1.5, 0.0) # 1m away (in follow range)
	cargol.step(0.1)
	
	# Back to IDLE (or EMP_COOLDOWN since cooldown 15s is still active)
	assert_int(cargol.state).is_equal(cargol.State.EMP_COOLDOWN)
	
	cargol.free()
	player.free()
	ddc.free()
