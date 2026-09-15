extends GdUnitTestSuite

# UIScaleCompensator con reference_height: por debajo de esa altura interna la UI se encoge en la
# misma proporcion (a 640x480 los controles tactiles ocupaban un 25% mas que a 800x600); por
# encima no crece.

const Compensator = preload("res://core_v2/ui/UIScaleCompensator.gd")


func test_reference_height_shrinks_below_but_never_grows() -> void:
	var before_scale: float = SettingsManager.render_scale
	SettingsManager.render_scale = 1.0
	var target := Control.new()
	var compensator = Compensator.new()
	compensator.reference_height = 600.0
	target.add_child(compensator)
	add_child(target)
	var height: float = compensator.get_viewport().get_visible_rect().size.y
	compensator.apply()
	assert_float(target.rect_scale.x).is_equal_approx(min(1.0, height / 600.0), 0.001)
	# La UI sigue cubriendo el viewport entero en su espacio nominal.
	assert_float(target.rect_size.y * target.rect_scale.y).is_equal_approx(height, 0.01)

	compensator.reference_height = height * 2.0
	compensator.apply()
	assert_float(target.rect_scale.x).is_equal_approx(0.5, 0.001)
	compensator.reference_height = height / 2.0
	compensator.apply()
	assert_float(target.rect_scale.x).is_equal_approx(1.0, 0.001)

	SettingsManager.render_scale = before_scale
	target.free()


# Con una pantalla abierta sobre el mundo (Opciones, modo HUD) se dibuja a escala 1.0 y la UI no
# se compensa; al cerrar TODAS vuelve la escala elegida.
func test_full_resolution_hold_while_any_screen_is_open() -> void:
	var before_scale: float = SettingsManager.render_scale
	SettingsManager.render_scale = 0.6
	var probe := Node.new()
	add_child(probe)
	var options := Reference.new()
	var hud := Reference.new()
	assert_float(SettingsManager.effective_render_scale()).is_equal_approx(0.6, 0.001)

	SettingsManager.hold_full_resolution_ui(options, true)
	SettingsManager.hold_full_resolution_ui(hud, true)
	assert_float(Compensator.scale_for(probe)).is_equal_approx(1.0, 0.001)
	SettingsManager.hold_full_resolution_ui(options, false)
	assert_float(SettingsManager.effective_render_scale()).is_equal_approx(1.0, 0.001)
	SettingsManager.hold_full_resolution_ui(hud, false)
	assert_float(Compensator.scale_for(probe)).is_equal_approx(0.6, 0.001)

	SettingsManager.render_scale = before_scale
	SettingsManager.apply_render_resolution()
	probe.free()
