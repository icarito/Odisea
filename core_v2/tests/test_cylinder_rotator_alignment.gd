extends GdUnitTestSuite

const RotatorScript = preload("res://core_v2/systems/visual/CylinderRotator.gd")
const StreamScript = preload("res://core_v2/systems/ScaffoldStreamController.gd")

func test_expected_up_matches_predicted_chunk_up_across_chunk_samples() -> void:
	var rotator: CylinderRotator = auto_free(RotatorScript.new())
	var stream: ScaffoldStreamController = auto_free(StreamScript.new())
	rotator.base_radius = 190.0
	stream.chunk_height = 6
	stream.chunk_length = 4
	stream.cell_size = 4.0
	rotator._stream = stream

	for sample in _samples():
		var debug: Dictionary = rotator.get_chunk_debug_at_global(sample)
		assert_str(String(debug.get("chunk_name", ""))).override_failure_message("Missing chunk debug for sample %s" % [str(sample)]).is_not_empty()
		assert_float(float(debug.get("alignment", -1.0))).override_failure_message(
			"Chunk normal misaligned at sample %s. debug=%s" % [str(sample), str(debug)]
		).is_greater_equal(0.999)

func test_positions_inside_same_chunk_share_same_expected_up() -> void:
	var rotator: CylinderRotator = auto_free(RotatorScript.new())
	var stream: ScaffoldStreamController = auto_free(StreamScript.new())
	rotator.base_radius = 190.0
	stream.chunk_height = 6
	stream.chunk_length = 4
	stream.cell_size = 4.0
	rotator._stream = stream

	var a: Vector3 = Vector3(2.0, 0.0, 2.0)
	var b: Vector3 = Vector3(10.0, 0.0, 6.0)
	var up_a: Vector3 = rotator.get_expected_up_at_global(a)
	var up_b: Vector3 = rotator.get_expected_up_at_global(b)

	assert_float(up_a.dot(up_b)).is_greater_equal(0.9999)

func test_crossing_chunk_boundary_changes_expected_up_to_neighbor_chunk() -> void:
	var rotator: CylinderRotator = auto_free(RotatorScript.new())
	var stream: ScaffoldStreamController = auto_free(StreamScript.new())
	rotator.base_radius = 190.0
	stream.chunk_height = 6
	stream.chunk_length = 4
	stream.cell_size = 4.0
	rotator._stream = stream

	var left: Vector3 = Vector3(10.0, 0.0, 6.0)
	var right: Vector3 = Vector3(26.0, 0.0, 6.0)
	var up_left: Vector3 = rotator.get_expected_up_at_global(left)
	var up_right: Vector3 = rotator.get_expected_up_at_global(right)

	assert_float(up_left.dot(up_right)).is_less(0.9999)
	assert_float(up_right.dot(Vector3(-sin(34.0 / 190.0), cos(34.0 / 190.0), 0.0))).is_greater_equal(0.9999)

func _samples() -> Array:
	return [
		Vector3(2.0, 0.0, 2.0),
		Vector3(10.0, 0.0, 6.0),
		Vector3(16.0, 0.0, 6.0),
		Vector3(-8.0, 0.0, 6.0)
	]
