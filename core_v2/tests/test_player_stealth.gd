extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const PlayerStealth = preload("res://core_v2/player/PlayerStealth.gd")

func test_crouch_visibility_reduction() -> void:
	var stealth = PlayerStealth.new()
	add_child(stealth)
	
	stealth.is_crouching = false
	assert_float(stealth.get_visibility_score()).is_equal(1.0)
	
	stealth.is_crouching = true
	assert_float(stealth.get_visibility_score()).is_equal(0.5)
	
	stealth.free()

func test_cover_visibility_reduction() -> void:
	var stealth = PlayerStealth.new()
	add_child(stealth)
	
	stealth.in_cover = true
	assert_int(stealth.current_state).is_equal(PlayerStealth.State.HIDDEN)
	assert_float(stealth.get_visibility_score()).is_equal(0.1)
	
	stealth.in_cover = false
	assert_int(stealth.current_state).is_equal(PlayerStealth.State.VISIBLE)
	assert_float(stealth.get_visibility_score()).is_equal(1.0)
	
	stealth.free()
