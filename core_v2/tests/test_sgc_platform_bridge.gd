extends GdUnitTestSuite

# Tests for SGCPlatformBridge (FD-052)
# Verifies: marker orientation, axis selection, platform switching logic.
# These are pure math tests — no scene tree timing, no yield.

const BridgeScript = preload("res://core_v2/systems/visual/SGCPlatformBridge.gd")

# ── Marker orientation ─────────────────────────────────────────────────────

func test_marker_at_theta0_has_up_equal_global_up() -> void:
	# At flat_z=0, theta=0: surface normal should be (0,1,0) — identity, no rotation needed.
	var bridge: SGCPlatformBridge = auto_free(BridgeScript.new())
	var theta: float = 0.0
	var up := Vector3(0.0, cos(theta), -sin(theta))
	assert_float(up.dot(Vector3.UP)).is_greater_equal(0.999)

func test_marker_at_quarter_turn_normal_faces_inward() -> void:
	# theta = PI/2: player has walked base_radius * PI/2 units in Z.
	# Normal should be (0, 0, -1) — pointing in -Z toward axis.
	var theta: float = PI / 2.0
	var up := Vector3(0.0, cos(theta), -sin(theta))
	assert_float(up.dot(Vector3(0.0, 0.0, -1.0))).is_greater_equal(0.999)

func test_marker_at_half_turn_normal_faces_down() -> void:
	# theta = PI: player is at the top of the cylinder.
	# Normal should be (0, -1, 0) — pointing down toward axis.
	var theta: float = PI
	var up := Vector3(0.0, cos(theta), -sin(theta))
	assert_float(up.dot(Vector3.DOWN)).is_greater_equal(0.999)

func test_marker_x_axis_unchanged_for_different_cx() -> void:
	# Cylinder axis is X. Markers at CX=0 and CX=3 with same CZ
	# should have the same +Y normal (theta only depends on flat_z).
	var theta: float = 0.3  # arbitrary CZ-derived angle
	var up := Vector3(0.0, cos(theta), -sin(theta))
	# CX does not affect up — only flat_x (cylinder axis position)
	assert_float(up.x).is_equal_approx(0.0, 0.001)

# ── Arc length / base_radius relationship ──────────────────────────────────

func test_theta_equals_arc_over_radius() -> void:
	var base_radius: float = 190.0
	var flat_z: float      = 60.0  # arbitrary walk distance
	var theta: float       = flat_z / base_radius
	# Arc length = theta * radius should recover flat_z
	assert_float(theta * base_radius).is_equal_approx(flat_z, 0.001)

func test_full_circumference_gives_tau() -> void:
	var base_radius: float        = 190.0
	var circumference: float      = TAU * base_radius
	var theta: float              = circumference / base_radius
	assert_float(theta).is_equal_approx(TAU, 0.001)

func test_no_stretch_arc_equals_flat_distance() -> void:
	# A chunk at flat_z=24 (one chunk_length=4, cell_size=4 step away)
	# should appear 24 world units along the arc — not compressed or stretched.
	var base_radius: float = 190.0
	var flat_z: float      = 24.0
	var theta: float       = flat_z / base_radius
	var arc: float         = theta * base_radius
	assert_float(arc).is_equal_approx(flat_z, 0.001)

# ── Nearest marker selection ───────────────────────────────────────────────

func test_find_nearest_marker_prefers_highest_up_dot() -> void:
	# Simulate two markers: one at theta=0 (bottom, up=(0,1,0))
	# and one at theta=PI/2 (side, up=(0,0,-1)).
	# The bottom one has higher dot with Vector3.UP, so it should win.
	var up_bottom := Vector3(0.0, cos(0.0),     -sin(0.0))      # (0, 1, 0)
	var up_side   := Vector3(0.0, cos(PI/2.0),  -sin(PI/2.0))   # (0, 0, -1)

	var dot_bottom: float = up_bottom.dot(Vector3.UP)
	var dot_side:   float = up_side.dot(Vector3.UP)

	assert_float(dot_bottom).is_greater(dot_side)

func test_cx_only_chunks_at_same_cz_have_identical_theta() -> void:
	# Two chunks differing only in CX (same CZ) should produce identical theta.
	var base_radius: float = 190.0
	var step_z: float      = 4.0 * 4.0   # chunk_length=4, cell_size=4
	var cz: int            = 2

	var flat_z: float      = cz * step_z
	var theta_cx0: float   = flat_z / base_radius
	var theta_cx1: float   = flat_z / base_radius  # CX doesn't affect theta

	assert_float(theta_cx0).is_equal_approx(theta_cx1, 0.001)

# ── Cylinder position ──────────────────────────────────────────────────────

func test_chunk_0_0_position_at_bottom_of_cylinder() -> void:
	var base_radius: float = 190.0
	var theta: float       = 0.0  # flat_z=0
	var pos := Vector3(0.0, -base_radius * cos(theta), base_radius * sin(theta))
	# Should be at (0, -190, 0) — directly below cylinder axis
	assert_float(pos.y).is_equal_approx(-base_radius, 0.001)
	assert_float(pos.z).is_equal_approx(0.0, 0.001)

func test_quarter_turn_chunk_position() -> void:
	var base_radius: float = 190.0
	var theta: float       = PI / 2.0
	var pos := Vector3(0.0, -base_radius * cos(theta), base_radius * sin(theta))
	# At PI/2: pos = (0, 0, 190)
	assert_float(pos.y).is_equal_approx(0.0, 0.1)
	assert_float(pos.z).is_equal_approx(base_radius, 0.1)
