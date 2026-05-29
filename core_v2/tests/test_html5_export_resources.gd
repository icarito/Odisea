extends GdUnitTestSuite

const EXPORT_PRESETS_PATH := "res://export_presets.cfg"

func test_html5_export_preset_declares_a_supported_resource_filter() -> void:
	var file := File.new()
	assert_int(file.open(EXPORT_PRESETS_PATH, File.READ)).is_equal(OK)
	var text := file.get_as_text()
	file.close()

	var html5_start := text.find("\n[preset.3]\n")
	assert_int(html5_start).is_greater(-1)
	var html5_options := text.find("\n[preset.3.options]\n")
	assert_int(html5_options).is_greater(html5_start)

	var preset_text := text.substr(html5_start, html5_options - html5_start)
	var uses_all_resources := preset_text.find("export_filter=\"all_resources\"") != -1
	var uses_selected_resources := preset_text.find("export_filter=\"resources\"") != -1
	assert_bool(uses_all_resources or uses_selected_resources).is_true()
