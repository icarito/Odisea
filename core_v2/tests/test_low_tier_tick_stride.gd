extends GdUnitTestSuite

# test_low_tier_tick_stride.gd — FD-299: los sistemas ambientales se espacian solo en tier LOW.

const StrideScript = preload("res://core_v2/systems/LowTierTickStride.gd")

func test_outside_low_tier_every_tick_passes_its_own_delta():
	var gate = get_node("/root/GLES3VendorGate")
	var previous: bool = gate.force_gate
	gate.force_gate = false
	var owner = auto_free(Node.new())
	add_child(owner)
	var stride = StrideScript.new(owner, 3)
	for i in 5:
		assert_float(stride.step(1.0 / 60.0)).is_equal(1.0 / 60.0)
	gate.force_gate = previous

func test_low_tier_skips_ticks_and_hands_over_the_accumulated_delta():
	var gate = get_node("/root/GLES3VendorGate")
	var previous: bool = gate.force_gate
	gate.force_gate = true
	var owner = auto_free(Node.new())
	add_child(owner)
	var stride = StrideScript.new(owner, 3)
	assert_float(stride.step(0.1)).is_equal(-1.0)
	assert_float(stride.step(0.1)).is_equal(-1.0)
	assert_float(stride.step(0.1)).is_equal_approx(0.3, 0.0001)
	assert_float(stride.step(0.1)).is_equal(-1.0)
	gate.force_gate = previous
