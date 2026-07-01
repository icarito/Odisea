extends GdUnitTestSuite

# Regression: a standalone (zero-G maze) airlock latches the exit door open (timer < 0)
# so the player can walk out. Since the maze disables AirlockZoneV2, nothing was resetting
# the controller afterwards, so it stayed stuck in EXIT_OPEN and could not be traversed the
# other way. The controller must auto-return to IDLE once the player leaves the chamber.

const AirlockControllerScript = preload("res://core_v2/components/AirlockControllerV2.gd")

class FakeDoor:
	extends Spatial
	var is_active := false
	func set_active(value: bool, _immediate: bool = false) -> void:
		is_active = value

class FakePlayer:
	extends KinematicBody
	func _init() -> void:
		add_to_group("player")

# Chamber Area whose overlap set we drive by hand (get_overlapping_bodies would need the
# physics server to flush; we override it so the test is deterministic).
class FakeChamberZone:
	extends Area
	var _bodies := []
	func set_bodies(bodies: Array) -> void:
		_bodies = bodies
	func get_overlapping_bodies() -> Array:
		return _bodies

func _make_standalone_airlock():
	var airlock = AirlockControllerScript.new()
	airlock.standalone_cycle = true
	airlock.pressurize_time = 0.5
	airlock.reset_time = 0.5

	var outer := FakeDoor.new()
	var inner := FakeDoor.new()
	var zone := FakeChamberZone.new()
	airlock.add_child(outer)
	airlock.add_child(inner)
	airlock.add_child(zone)
	add_child(airlock)

	# Bypass path resolution: wire the internal refs directly.
	airlock._outer_door = outer
	airlock._inner_door = inner
	airlock._chamber_zone = zone
	return airlock

func test_standalone_airlock_returns_to_idle_after_player_exits_chamber() -> void:
	var airlock = _make_standalone_airlock()
	var zone = airlock._chamber_zone
	var player = auto_free(FakePlayer.new())
	add_child(player)

	# Enter from the outer side and pressurize through to the latched EXIT_OPEN.
	airlock.start_cycle(true)  # cycling in from outer
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)

	# Player is in the chamber while pressurizing.
	zone.set_bodies([player])
	for i in range(20):
		airlock.step(0.1)
		if airlock.state == AirlockControllerV2.State.EXIT_OPEN:
			break

	assert_int(airlock.state).is_equal(AirlockControllerV2.State.EXIT_OPEN)

	# Player is still inside right after the exit door latches open.
	airlock.step(0.1)
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.EXIT_OPEN)

	# Player walks out of the chamber -> controller must reset to IDLE.
	zone.set_bodies([])
	airlock.step(0.1)
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.IDLE)

	# And the airlock is cyclable again (traverse the other direction).
	assert_bool(airlock.start_cycle(false)).is_true()
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)

	airlock.queue_free()

func test_standalone_airlock_stays_open_while_player_in_chamber() -> void:
	var airlock = _make_standalone_airlock()
	var zone = airlock._chamber_zone
	var player = auto_free(FakePlayer.new())
	add_child(player)

	airlock.start_cycle(true)
	zone.set_bodies([player])
	for i in range(20):
		airlock.step(0.1)
		if airlock.state == AirlockControllerV2.State.EXIT_OPEN:
			break
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.EXIT_OPEN)

	# Player lingers in the chamber: the exit door stays latched open, no premature reset.
	for i in range(10):
		airlock.step(0.1)
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.EXIT_OPEN)

	airlock.queue_free()
