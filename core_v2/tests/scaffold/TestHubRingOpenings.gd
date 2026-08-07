extends Node
# Rail openings on a ScaffoldHubRing.
#
# The ring punches gaps in its outer rail so walkways and the elevator can dock.
# Each gap is authored as an angular range and clipped against every polygon
# sector, which is what lets a single face carry more than one opening and lets a
# wide opening carry on across a corner. Both cases are live in Dome_Intro: the
# top floor takes the spiral walkway and the elevator on the same octagon face.

const RING_SCRIPT = preload("res://core_v2/props/scaffold/ScaffoldHubRing.gd")

const SIDES := 8
const OUTER_RADIUS := 13.0

var _passed := 0
var _failed := 0

func _ready() -> void:
	var ring = RING_SCRIPT.new()
	ring.sides = SIDES
	ring.outer_radius = OUTER_RADIUS
	ring.opening_width = 2.0

	_test_single_opening(ring)
	_test_two_openings_on_one_face(ring)
	_test_opening_across_a_corner(ring)
	_test_untouched_faces_keep_full_rail(ring)
	_test_spans_are_the_complement_of_the_gaps(ring)

	ring.free()
	print("[HubRingOpenings] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# A lone narrow range still opens opening_width metres, centred on the angle.
func _test_single_opening(ring) -> void:
	var gaps: Array = _gaps(ring, 2, [Vector2(112.0, 113.0)])
	_check(gaps.size() == 1, "single opening lands on exactly one gap, got %d" % gaps.size())
	_check_near(_metres(gaps[0]), ring.opening_width, 0.01, "narrow range widens to opening_width")

# Regression: the walkway and the elevator both fall inside face 2 on the top
# floor. Claiming the face for whichever opening matched first silently dropped
# the elevator's gap, so arriving by lift left you facing a solid rail.
func _test_two_openings_on_one_face(ring) -> void:
	var gaps: Array = _gaps(ring, 2, [Vector2(93.0, 95.0), Vector2(108.957, 121.163)])
	_check(gaps.size() == 2, "both openings survive on one face, got %d" % gaps.size())
	if gaps.size() == 2:
		_check(gaps[0].y <= gaps[1].x + 0.001, "the two gaps stay disjoint")
		_check_near(_metres(gaps[1]), 2.78, 0.05, "the elevator gap keeps its authored width")

# An opening centred near a polygon vertex has to keep going on the next face
# instead of being cut off at the corner.
func _test_opening_across_a_corner(ring) -> void:
	var ranges := [Vector2(86.022, 94.820)]
	var left: Array = _gaps(ring, 1, ranges)
	var right: Array = _gaps(ring, 2, ranges)
	_check(left.size() == 1 and right.size() == 1, "the corner opening reaches both faces")
	if left.size() == 1 and right.size() == 1:
		_check_near(left[0].y, 1.0, 0.001, "it runs to the end of the left face")
		_check_near(right[0].x, 0.0, 0.001, "and starts at the beginning of the right one")
		_check(_metres(left[0]) + _metres(right[0]) > ring.opening_width,
			"the two halves together clear more than a single-face gap")

func _test_untouched_faces_keep_full_rail(ring) -> void:
	var ranges := [Vector2(108.957, 121.163)]
	for index in [0, 3, 4, 5, 6, 7]:
		_check(_gaps(ring, index, ranges).empty(), "face %d keeps its rail" % index)
	var spans: Array = ring._rail_spans([])
	_check(spans.size() == 1 and spans[0] == Vector2(0.0, 1.0), "no gaps means one unbroken rail")

func _test_spans_are_the_complement_of_the_gaps(ring) -> void:
	var spans: Array = ring._rail_spans([Vector2(0.6, 0.7), Vector2(0.2, 0.3)])
	_check(spans.size() == 3, "two gaps leave three stretches of rail, got %d" % spans.size())
	if spans.size() == 3:
		_check_near(spans[0].y, 0.2, 0.001, "rail stops at the first gap")
		_check_near(spans[1].x, 0.3, 0.001, "and resumes after it")
		_check_near(spans[2].y, 1.0, 0.001, "the last stretch runs to the end")
	var merged: Array = ring._rail_spans([Vector2(0.2, 0.5), Vector2(0.4, 0.8)])
	_check(merged.size() == 2, "overlapping gaps merge into one hole, got %d" % merged.size())

func _gaps(ring, face_index: int, ranges: Array) -> Array:
	var sector: float = TAU / float(SIDES)
	return ring._edge_gaps(sector * (float(face_index) + 0.5), sector, _chord(), ranges)

func _chord() -> float:
	var sector: float = TAU / float(SIDES)
	return 2.0 * (OUTER_RADIUS / cos(sector * 0.5)) * sin(sector * 0.5)

func _metres(gap: Vector2) -> float:
	return (gap.y - gap.x) * _chord()

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("[HubRingOpenings] FAIL: %s" % label)

func _check_near(value: float, expected: float, tolerance: float, label: String) -> void:
	_check(abs(value - expected) <= tolerance, "%s (got %.4f, expected %.4f)" % [label, value, expected])
