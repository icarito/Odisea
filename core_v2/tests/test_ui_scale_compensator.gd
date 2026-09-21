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


# El perfil LOW (flat) default a 0.75: a 0.6 el texto de UI sin resolucion completa no se
# lee en 640x480. La eleccion explicita del jugador (Opciones) pisa el default.
func test_low_end_default_render_scale_is_075() -> void:
	var before_scale: float = SettingsManager.render_scale
	var before_user: bool = SettingsManager._render_scale_user_set
	var before_forced: bool = SettingsManager.low_end_forced

	SettingsManager.low_end_forced = true
	SettingsManager._render_scale_user_set = false
	SettingsManager.render_scale = 1.0
	SettingsManager._apply_profile_render_scale_default()
	assert_float(SettingsManager.render_scale).is_equal_approx(0.75, 0.001)

	# Elegir a mano (Opciones) queda como la del jugador, aunque sea mas bajo: el default
	# del perfil no lo vuelve a pisar.
	SettingsManager.set_render_scale(0.6)
	assert_bool(SettingsManager._render_scale_user_set).is_true()
	SettingsManager._apply_profile_render_scale_default()
	assert_float(SettingsManager.render_scale).is_equal_approx(0.6, 0.001)

	SettingsManager.low_end_forced = before_forced
	SettingsManager._render_scale_user_set = before_user
	SettingsManager.render_scale = before_scale
	SettingsManager.apply_render_resolution()
