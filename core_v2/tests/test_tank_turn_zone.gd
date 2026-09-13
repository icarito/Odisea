extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const PlayerMovementV2 = preload("res://core_v2/player/PlayerMovementV2.gd")
const PilotScene = preload("res://core_v2/actors/Pilot_v2.tscn")

func test_tank_lateral_input_inside_zone() -> void:
	# Inside turn zone (0 .. zone_end): lateral input must be strictly 0.0
	var res_zero := PlayerMovementV2.tank_lateral_input(0.0, 0.75, 0.75)
	assert_float(res_zero).is_equal_approx(0.0, 0.0001)

	var res_half := PlayerMovementV2.tank_lateral_input(0.5, 0.75, 0.75)
	assert_float(res_half).is_equal_approx(0.0, 0.0001)

	var res_edge := PlayerMovementV2.tank_lateral_input(0.75, 0.75, 0.75)
	assert_float(res_edge).is_equal_approx(0.0, 0.0001)

	var res_neg_half := PlayerMovementV2.tank_lateral_input(-0.5, 0.75, 0.75)
	assert_float(res_neg_half).is_equal_approx(0.0, 0.0001)

func test_tank_lateral_input_outside_zone_ramp() -> void:
	# Outside turn zone (zone_end .. 1.0): linear ramp 0 -> (1 - blend)
	# Full stick positive: x = 1.0, zone = 0.75, blend = 0.75 -> 1.0 * 1.0 * (1 - 0.75) = 0.25
	var res_full := PlayerMovementV2.tank_lateral_input(1.0, 0.75, 0.75)
	assert_float(res_full).is_equal_approx(0.25, 0.0001)

	# Full stick negative: x = -1.0, zone = 0.75, blend = 0.75 -> -0.25
	var res_full_neg := PlayerMovementV2.tank_lateral_input(-1.0, 0.75, 0.75)
	assert_float(res_full_neg).is_equal_approx(-0.25, 0.0001)

	# Midpoint outer ramp: x = 0.875 (halfway between 0.75 and 1.0) -> ramp = 0.5, lateral = 0.5 * 0.25 = 0.125
	var res_mid_ramp := PlayerMovementV2.tank_lateral_input(0.875, 0.75, 0.75)
	assert_float(res_mid_ramp).is_equal_approx(0.125, 0.0001)

func test_tank_lateral_input_compatibility_default_zero() -> void:
	# zone_end = 0.0 (default code value): continuous blend x * (1 - blend)
	var res_half := PlayerMovementV2.tank_lateral_input(0.5, 0.0, 0.75)
	assert_float(res_half).is_equal_approx(0.125, 0.0001)

	var res_full := PlayerMovementV2.tank_lateral_input(1.0, 0.0, 0.75)
	assert_float(res_full).is_equal_approx(0.25, 0.0001)

func test_tank_lateral_input_binary_mode_one() -> void:
	# zone_end = 1.0 (core_v1 binary mode): zero lateral input across entire stick
	var res_half := PlayerMovementV2.tank_lateral_input(0.5, 1.0, 0.75)
	assert_float(res_half).is_equal_approx(0.0, 0.0001)

	var res_full := PlayerMovementV2.tank_lateral_input(1.0, 1.0, 0.75)
	assert_float(res_full).is_equal_approx(0.0, 0.0001)

	var res_full_neg := PlayerMovementV2.tank_lateral_input(-1.0, 1.0, 0.75)
	assert_float(res_full_neg).is_equal_approx(0.0, 0.0001)

func test_player_movement_strafe_mode_regression() -> void:
	var movement: PlayerMovementV2 = auto_free(PlayerMovementV2.new())
	add_child(movement)

	movement.tank_turn_zone_end = 0.75
	movement.tank_strafe_blend = 0.75

	# 1. When in tank turn mode with x=0.5 (inside 0.75 zone), wish_direction lateral component should be 0
	movement.is_tank_turn_mode = true
	movement.process_movement(0.016, Vector2(0.5, 0.0), Basis.IDENTITY, false, true, false)
	assert_float(movement.wish_direction.x).is_equal_approx(0.0, 0.0001)

	# 2. When in strafe mode (is_tank_turn_mode = false), lateral input is full move_vec.x regardless of zone
	movement.is_tank_turn_mode = false
	movement.process_movement(0.016, Vector2(0.5, 0.0), Basis.IDENTITY, false, true, false)
	assert_float(movement.wish_direction.x).is_greater(0.0)

func test_stationary_turn_speed_multiplier() -> void:
	var movement: PlayerMovementV2 = auto_free(PlayerMovementV2.new())
	add_child(movement)
	movement.tank_turn_speed = 2.0
	movement.tank_strafe_blend = 0.95
	movement.diagonal_turn_blend = 0.9
	movement.stationary_turn_speed_multiplier = 0.6
	movement.tank_turn_stationary_axis_deadzone = 0.5

	assert_float(abs(movement.get_tank_yaw_delta(1.0, Vector2.RIGHT))).is_equal_approx(1.14, 0.0001)
	assert_float(abs(movement.get_tank_yaw_delta(1.0, Vector2(1.0, 0.49)))).is_equal_approx(1.14, 0.0001)
	assert_float(abs(movement.get_tank_yaw_delta(1.0, Vector2(1.0, 0.51)))).is_equal_approx(1.8, 0.0001)
	assert_float(abs(movement.get_tank_yaw_delta(1.0, Vector2(1.0, -1.0)))).is_equal_approx(1.8, 0.0001)
	assert_float(PlayerMovementV2.tank_lateral_input(0.85, 0.85, 0.95)).is_equal_approx(0.0, 0.0001)
	assert_float(PlayerMovementV2.tank_lateral_input(1.0, 0.85, 0.95)).is_equal_approx(0.05, 0.0001)

func test_tank_strafe_keeps_the_filtered_analog_magnitude() -> void:
	var movement: PlayerMovementV2 = auto_free(PlayerMovementV2.new())
	add_child(movement)
	movement.move_speed = 2.0
	movement.run_speed_multiplier = 3.5
	movement.tank_turn_zone_end = 0.85
	movement.tank_strafe_blend = 0.95
	movement.is_tank_turn_mode = true

	movement.process_movement(1.0, Vector2(1.0, 0.004), Basis.IDENTITY, true, true)
	assert_float(movement.get_horizontal_velocity().length()).is_equal_approx(0.3511, 0.0001)

func test_pilot_tank_calibration() -> void:
	var pilot: Node = auto_free(PilotScene.instance())
	var movement: PlayerMovementV2 = pilot.get_node("Logic/Movement")
	assert_float(movement.tank_strafe_blend).is_equal_approx(0.95, 0.0001)
	assert_float(movement.tank_turn_zone_end).is_equal_approx(0.85, 0.0001)
	assert_float(movement.stationary_turn_speed_multiplier).is_equal_approx(0.8, 0.0001)
	assert_float(movement.tank_turn_stationary_axis_deadzone).is_equal_approx(0.7, 0.0001)
