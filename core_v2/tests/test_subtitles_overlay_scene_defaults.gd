extends GdUnitTestSuite

const SubtitlesOverlayScene = preload("res://core_v2/ui/retro/SubtitlesOverlay.tscn")


func test_subtitles_overlay_scene_keeps_script_defaults() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	assert_float(float(overlay.default_duration)).is_greater(0.0)
	assert_float(float(overlay.fade_in_sec)).is_greater_equal(0.0)
	assert_float(float(overlay.fade_out_sec)).is_greater(0.0)
	assert_float(float(overlay.clear_fade_out_sec)).is_greater(0.0)
	assert_float(float(overlay.stack_shift_sec)).is_greater_equal(0.0)
	assert_float(float(overlay.bottom_margin)).is_greater(0.0)
	assert_float(float(overlay.horizontal_margin)).is_greater(0.0)
	assert_float(float(overlay.line_spacing)).is_greater_equal(0.0)
	assert_float(float(overlay.max_width_ratio)).is_greater(0.0)
	assert_float(float(overlay.panel_alpha)).is_greater(0.0)

	overlay.queue_free()


func test_subtitles_overlay_builds_font_with_font_data() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	var font = overlay.call("_get_subtitle_font")
	assert_object(font).is_not_null()
	assert_object(font.font_data).is_not_null()

	overlay.queue_free()
