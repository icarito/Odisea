extends GdUnitTestSuite

const SignagePanel = preload("res://core_v2/props/signage/SignagePanel.gd")
const SIGNAGE_SCENE = "res://core_v2/props/signage/SignagePanel.tscn"

func before():
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)

func test_presets_canonical_colors():
	assert_bool(SignagePanel.COLOR_PRESETS.get("warning") == Color("#FF8800")).is_true()
	assert_bool(SignagePanel.COLOR_PRESETS.get("danger") == Color("#FF2200")).is_true()
	assert_bool(SignagePanel.COLOR_PRESETS.get("info") == Color("#00FFFF")).is_true()
	assert_bool(SignagePanel.COLOR_PRESETS.get("terminal") == Color("#00FF88")).is_true()
	assert_bool(SignagePanel.COLOR_PRESETS.get("hologram") == Color("#00CCFF")).is_true()

func test_null_font_loads_default_syne_mono():
	var packed: PackedScene = load(SIGNAGE_SCENE)
	var panel: Node = packed.instance()
	add_child(panel)
	auto_free(panel)

	panel.font = null
	panel.update_text()

	assert_bool(File.new().file_exists("res://assets/fonts/SyneMono-Regular.ttf")).is_true()
	var mat: SpatialMaterial = panel.get_node("MeshInstance").material_override
	assert_object(mat).is_not_null()
	assert_object(mat.albedo_texture).is_not_null()

func test_autofit_text_fits_viewport_bounds():
	var packed: PackedScene = load(SIGNAGE_SCENE)
	var panel: Node = packed.instance()
	add_child(panel)
	auto_free(panel)

	var test_strings = [
		"SALIDA",
		"PELIGRO",
		"SOLO PERSONAL AUTORIZADO",
		"DESPRESURIZADO",
		"SECTOR EN CUARENTENA"
	]

	var check_font = DynamicFont.new()
	check_font.font_data = load("res://assets/fonts/SyneMono-Regular.ttf")

	for text_sample in test_strings:
		panel.font_size = 0
		panel.padding = 8.0
		panel.set_text(text_sample)

		var avail_w = panel.viewport_size.x - 2.0 * panel.padding
		var avail_h = panel.viewport_size.y - 2.0 * panel.padding

		var formatted_text = text_sample
		if panel.case_mode == 1:
			formatted_text = text_sample.to_upper()
		elif panel.case_mode == 2:
			formatted_text = text_sample.to_lower()

		var low: int = 1
		var high: int = int(avail_h)
		var best_size: int = 1
		while low <= high:
			var mid: int = (low + high) / 2
			check_font.size = mid
			var sz = panel._measure_string_size(check_font, formatted_text)
			if sz.x <= avail_w and sz.y <= avail_h:
				best_size = mid
				low = mid + 1
			else:
				high = mid - 1

		check_font.size = best_size
		var final_sz = panel._measure_string_size(check_font, formatted_text)
		assert_bool(final_sz.x <= avail_w).is_true()
		assert_bool(final_sz.y <= avail_h).is_true()

func test_setters_post_ready_no_crash_and_update_texture():
	var packed: PackedScene = load(SIGNAGE_SCENE)
	var panel: Node = packed.instance()
	add_child(panel)
	auto_free(panel)

	panel.set_text("NUEVO TEXTO PRUEBA")
	panel.set_color_preset("danger")
	panel.set_font_size(24)
	panel.set_alignment(Label.ALIGN_LEFT)
	panel.set_case_mode(1)
	panel.set_padding(12.0)
	panel.set_outline_size(2)
	panel.set_outline_color(Color.black)
	panel.set_border_enabled(true)
	panel.set_border_color(Color.red)
	panel.set_border_width(3.0)

	var mat: SpatialMaterial = panel.get_node("MeshInstance").material_override
	assert_object(mat).is_not_null()
	assert_object(mat.albedo_texture).is_not_null()
	assert_vector2(mat.albedo_texture.get_size()).is_equal(panel.viewport_size)

func test_interaction_area_configuration():
	var packed: PackedScene = load(SIGNAGE_SCENE)
	var panel: Node = packed.instance()
	add_child(panel)
	auto_free(panel)

	panel.set_is_interactive(false)
	var area: Area = panel.get_node("Area")
	assert_bool(area.monitoring).is_false()
	assert_bool(area.monitorable).is_false()

	panel.set_interaction_radius(3.5)
	panel.set_is_interactive(true)
	assert_bool(area.monitoring).is_true()
	assert_bool(area.monitorable).is_true()

	var col_shape: CollisionShape = area.get_node("CollisionShape")
	assert_object(col_shape.shape).is_not_null()
	assert_float(col_shape.shape.radius).is_equal(3.5)

func test_determinism_identical_config():
	var packed: PackedScene = load(SIGNAGE_SCENE)
	var panel1: Node = packed.instance()
	var panel2: Node = packed.instance()
	add_child(panel1)
	add_child(panel2)
	auto_free(panel1)
	auto_free(panel2)

	panel1.set_text("DETERMINISMO")
	panel1.set_color_preset("info")
	panel2.set_text("DETERMINISMO")
	panel2.set_color_preset("info")

	var mat1: SpatialMaterial = panel1.get_node("MeshInstance").material_override
	var mat2: SpatialMaterial = panel2.get_node("MeshInstance").material_override
	assert_vector2(mat1.albedo_texture.get_size()).is_equal(mat2.albedo_texture.get_size())
	assert_vector2(mat1.albedo_texture.get_size()).is_equal(Vector2(512, 307))
