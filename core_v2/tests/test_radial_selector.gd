extends GdUnitTestSuite

# Covers the parts of RadialSelectorV2 with no visual tell when they break: which
# option an aim lands on, and — just as important — when an aim lands on nothing,
# which is what stops a click from picking a floor the player never pointed at.

const SelectorScene = preload("res://core_v2/ui/radial/RadialSelectorV2.tscn")
const SIZE := 1024.0
const CENTER := Vector2(SIZE / 2.0, SIZE / 2.0)


func _make(labels: Array) -> Control:
	var selector = auto_free(SelectorScene.instance())
	add_child(selector)
	selector.rect_size = Vector2(SIZE, SIZE)
	selector.set_options(labels)
	selector.open()
	return selector


func _aim(selector: Control, clock_hour: float, radius_ratio: float = 0.65) -> void:
	# Clock face to screen angle: 12 o'clock is straight up, hours run clockwise.
	var angle: float = (clock_hour / 12.0) * TAU - PI / 2.0
	selector.point_at(CENTER + Vector2(cos(angle), sin(angle)) * (SIZE / 2.0 * radius_ratio))


func test_three_stops_sit_at_six_three_and_twelve() -> void:
	# The dial spans the right half only — the side the OTS camera leaves clear —
	# so three stops land on the clock exactly.
	var selector = _make(["1", "2", "3"])
	_aim(selector, 6)
	assert_int(selector.get_hovered_index()).is_equal(0)
	_aim(selector, 3)
	assert_int(selector.get_hovered_index()).is_equal(1)
	_aim(selector, 12)
	assert_int(selector.get_hovered_index()).is_equal(2)


func test_the_left_half_is_not_used() -> void:
	var selector = _make(["1", "2", "3"])
	# 9 o'clock is off the arc entirely; it belongs to whichever end is nearer,
	# and must never be a hole.
	_aim(selector, 9)
	assert_int(selector.get_hovered_index()).is_not_equal(-1)


func test_the_needle_tracks_the_car_between_stops() -> void:
	var selector = _make(["1", "2", "3"])
	selector.set_level(0.0)
	var bottom: float = selector._angle_for_level(0.0)
	selector.set_level(2.0)
	var top: float = selector._angle_for_level(2.0)
	# Bottom stop at 6 o'clock, top at 12: half a turn apart.
	assert_float(abs(top - bottom)).is_equal_approx(PI, 0.001)
	# Halfway up the shaft the needle sits at 9 o'clock, between the two.
	assert_float(selector._angle_for_level(1.0)).is_equal_approx((bottom + top) / 2.0, 0.001)
	# And it is genuinely continuous, not snapped to a stop.
	assert_float(selector._angle_for_level(0.5)).is_equal_approx((bottom + top) / 4.0 + bottom / 2.0, 0.001)


func test_a_committed_pick_drops_the_focus_and_holds_it() -> void:
	var selector = _make(["1", "2", "3"])
	_aim(selector, 3)
	assert_int(selector.get_hovered_index()).is_equal(1)
	selector.suppress_focus()
	assert_bool(selector.has_selection()).is_false()
	# The aim has not moved, so the dial must not light the stop back up.
	_aim(selector, 3)
	assert_bool(selector.has_selection()).is_false()
	# Looking away releases the hold.
	selector.clear_pointer()
	_aim(selector, 3)
	assert_int(selector.get_hovered_index()).is_equal(1)


func test_no_heading_on_the_dial_leaves_you_empty_handed() -> void:
	# Sweeping the whole circle at any distance must always focus something: a
	# hole would read as the dial being broken rather than strict.
	var selector = _make(["1", "2", "3", "4", "5", "6"])
	for ratio in [0.15, 0.4, 0.65, 0.9]:
		for step in range(72):
			_aim(selector, step * 12.0 / 72.0, ratio)
			assert_int(selector.get_hovered_index()) \
				.override_failure_message("hole at hour %.2f, ratio %.2f" % [step * 12.0 / 72.0, ratio]) \
				.is_not_equal(-1)


func test_the_unused_half_snaps_to_whichever_end_is_nearer() -> void:
	var selector = _make(["1", "2", "3", "4"])
	# The dial runs 6 -> 3 -> 12; the left half holds no options, so an aim there
	# belongs to whichever end it is closer to.
	_aim(selector, 11.0)
	assert_int(selector.get_hovered_index()).is_equal(3)
	_aim(selector, 7.0)
	assert_int(selector.get_hovered_index()).is_equal(0)


func test_the_hub_holds_the_current_focus() -> void:
	var selector = _make(["1", "2", "3", "4", "5", "6"])
	_aim(selector, 3)
	var focused: int = selector.get_hovered_index()
	assert_int(focused).is_not_equal(-1)
	# Dead centre carries no heading, so it must hold rather than blank out.
	selector.point_at(CENTER)
	assert_int(selector.get_hovered_index()).is_equal(focused)


func test_confirm_is_swallowed_while_looking_away() -> void:
	var selector = _make(["1", "2", "3", "4"])
	selector.connect("option_selected", self, "_on_option_selected")
	_selected = -99
	selector.clear_pointer() # The owner reports the aim left the projection.
	selector.confirm()
	assert_int(_selected).is_equal(-99)


func test_confirm_reports_the_aimed_option() -> void:
	var selector = _make(["1", "2", "3"])
	selector.connect("option_selected", self, "_on_option_selected")
	_selected = -99
	_aim(selector, 3)
	selector.confirm()
	assert_int(_selected).is_equal(1)


func test_the_level_readout_ignores_the_aim() -> void:
	# The wedge and the lit number already say what is being pointed at; the
	# readout is the car's own level and must not mirror the aim.
	var selector = _make(["1", "2", "3"])
	selector.set_readout_text("2")
	_aim(selector, 12)
	assert_int(selector.get_hovered_index()).is_equal(2)
	assert_str(selector._readout_label.text).is_equal("2")


func test_opening_starts_with_nothing_selected() -> void:
	var selector = _make(["1", "2", "3", "4"])
	_aim(selector, 12)
	assert_bool(selector.has_selection()).is_true()
	selector.close()
	selector.open()
	assert_bool(selector.has_selection()).is_false()


func test_every_option_is_reachable_for_awkward_counts() -> void:
	for count in [2, 3, 5, 6, 7]:
		var labels := []
		for i in range(count):
			labels.append(str(i + 1))
		var selector = _make(labels)
		var reached := {}
		for i in range(count):
			var angle: float = selector._index_to_screen_angle(i)
			selector.point_at(CENTER + Vector2(cos(angle), sin(angle)) * (SIZE / 2.0 * 0.65))
			reached[selector.get_hovered_index()] = true
		assert_bool(reached.has(-1)) \
			.override_failure_message("count=%d aimed straight at an option and got nothing" % count) \
			.is_false()
		assert_int(reached.size()) \
			.override_failure_message("count=%d only reached %s" % [count, reached.keys()]) \
			.is_equal(count)


var _selected := -99


func _on_option_selected(index: int) -> void:
	_selected = index


func test_a_climb_scrolls_the_readout_downward() -> void:
	# The numbers behave like a strip painted inside the shaft: going up, the
	# strip runs down past the window, so the old floor leaves through the bottom
	# and the new one drops in from above. This was backwards once already.
	var selector = _make(["1", "2", "3"])
	selector.set_readout_text("1")
	var rest_y: float = selector._readout_label.rect_position.y
	var was_showing = selector._readout_label

	selector.announce_readout_text("2", 1)
	var arriving = selector._readout_label
	assert_object(arriving).is_not_same(was_showing)
	assert_float(arriving.rect_position.y) \
		.override_failure_message("climbing must bring the new floor in from above") \
		.is_less(rest_y)
	assert_str(arriving.text).is_equal("2")
	# And the one being replaced is on its way out the bottom.
	assert_float(was_showing.rect_position.y).is_less_equal(rest_y)


func test_a_descent_scrolls_the_readout_upward() -> void:
	var selector = _make(["1", "2", "3"])
	selector.set_readout_text("3")
	var rest_y: float = selector._readout_label.rect_position.y
	selector.announce_readout_text("2", -1)
	assert_float(selector._readout_label.rect_position.y) \
		.override_failure_message("descending must bring the new floor in from below") \
		.is_greater(rest_y)
