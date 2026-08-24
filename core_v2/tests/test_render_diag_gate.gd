extends GdUnitTestSuite

# El panel de diagnostico no debe aparecer encima del juego fuera de iOS, aunque la
# instancia de Dome_Intro quede con enabled=true mientras dure la investigacion.

const RenderDiagScript = preload("res://core_v2/levels/diag/RenderDiag.gd")


func test_solo_ios_con_la_instancia_encendida() -> void:
	assert_bool(RenderDiagScript._wants_diag("iOS", true, "")).is_true()
	assert_bool(RenderDiagScript._wants_diag("Android", true, "")).is_false()
	assert_bool(RenderDiagScript._wants_diag("X11", true, "")).is_false()


func test_apagado_en_la_instancia_no_se_enciende_ni_en_ios() -> void:
	assert_bool(RenderDiagScript._wants_diag("iOS", false, "")).is_false()


func test_el_env_manda_en_cualquier_plataforma() -> void:
	# Es la unica via para tomar la linea base de escritorio.
	assert_bool(RenderDiagScript._wants_diag("X11", false, "1")).is_true()
	assert_bool(RenderDiagScript._wants_diag("Android", false, "on")).is_true()
