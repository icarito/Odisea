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


func test_subtitles_overlay_supports_distinct_hint_entries() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	overlay.show_hint("[Z] Focus Terminal")
	var layer = overlay.get_node_or_null("Layer")
	assert_object(layer).is_not_null()
	assert_int(layer.get_child_count()).is_equal(1)

	overlay.queue_free()


# Los subtitulos tapan la pantalla: como maximo 2 frases, ancho ~55-60 % y fondo tenue
# (la legibilidad la da el contorno de la fuente, no un panel opaco).
func test_subtitles_overlay_defaults_are_compact() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	assert_int(int(overlay.max_visible_lines)).is_equal(2)
	assert_bool(float(overlay.max_width_ratio) <= 0.62).is_true()
	assert_bool(float(overlay.max_width_ratio) >= 0.5).is_true()
	assert_bool(float(overlay.panel_alpha) <= 0.3).is_true()
	assert_bool(float(overlay.panel_alpha) > 0.0).is_true()

	overlay.queue_free()


# Una rafaga de frases no apila cuatro a la vez: se montan dos y el resto espera en la cola.
func test_subtitles_overlay_caps_visible_lines_and_queues_the_rest() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	for i in range(4):
		overlay.show_subtitle("frase %d" % i)

	var layer = overlay.get_node_or_null("Layer")
	assert_object(layer).is_not_null()
	assert_int(layer.get_child_count()).is_equal(2)
	assert_int(overlay.get("_pending").size()).is_equal(2)

	overlay.clear_subtitles(true)
	assert_int(overlay.get("_entries").size()).is_equal(0)
	assert_int(overlay.get("_pending").size()).is_equal(0)

	overlay.queue_free()


# El texto lleva contorno oscuro para leerse sobre fondos claros y oscuros sin panel opaco.
func test_subtitles_overlay_text_is_outlined() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	var font = overlay.call("_get_subtitle_font")
	assert_int(font.outline_size).is_greater(0)

	overlay.queue_free()


# Duracion proporcional al largo del texto y acotada por el tope.
func test_subtitles_overlay_duration_is_proportional_and_capped() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	var short_dur = overlay.call("_resolve_duration", "Anotado.", 8.0)
	var long_dur = overlay.call(
		"_resolve_duration",
		"Terminal de Flujo alcanzada. Gire la Valvula Maestra para sellar la purga termica y cerrar la Orden 0001.",
		8.0
	)
	assert_bool(float(short_dur) < float(long_dur)).is_true()
	assert_bool(float(long_dur) <= float(overlay.max_duration)).is_true()
	assert_bool(float(short_dur) >= float(overlay.min_duration)).is_true()

	overlay.queue_free()


# La escala de UI (UIScaleCompensator) tambien escala el subtitulo: a render_scale < 1 la
# fuente se encoge para que el tamaño en pantalla no cambie.
func test_subtitles_overlay_follows_ui_scale() -> void:
	var overlay = SubtitlesOverlayScene.instance()
	add_child(overlay)

	var before_scale: float = SettingsManager.render_scale
	SettingsManager.render_scale = 0.6
	overlay.set("_cached_font", null)
	var font_small = overlay.call("_get_subtitle_font")

	SettingsManager.render_scale = 1.0
	overlay.set("_cached_font", null)
	var font_full = overlay.call("_get_subtitle_font")

	SettingsManager.render_scale = before_scale
	SettingsManager.apply_render_resolution()

	assert_int(font_small.size).is_less(font_full.size)

	overlay.queue_free()
