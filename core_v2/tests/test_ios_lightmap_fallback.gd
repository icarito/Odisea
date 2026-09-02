extends GdUnitTestSuite

# El fallback manual de lightmap era el camino por defecto de iOS cuando el proyecto
# corria GLES2 ahi (el motor ataba su lightmap a la unidad max-4 = 4 y la colision con
# las texturas del material era silenciosa). La salida definitiva fue cambiar de
# renderer: iOS corre GLES3, donde el lightmap nativo si se dibuja. Este gate queda
# como opt-in de diagnostico A/B (ODISEA_MANUAL_LIGHTMAP=1), nunca como default.

const IOSLightmapFallbackScript = preload("res://core_v2/systems/IOSLightmapFallback.gd")


func test_sin_variable_ninguna_plataforma_cae_al_camino_manual() -> void:
	assert_bool(IOSLightmapFallbackScript._wants_fallback("iOS", "")).is_false()
	assert_bool(IOSLightmapFallbackScript._wants_fallback("Android", "")).is_false()
	assert_bool(IOSLightmapFallbackScript._wants_fallback("X11", "")).is_false()


func test_la_variable_de_entorno_fuerza_el_camino_manual_en_cualquier_os() -> void:
	assert_bool(IOSLightmapFallbackScript._wants_fallback("iOS", "1")).is_true()
	assert_bool(IOSLightmapFallbackScript._wants_fallback("X11", "true")).is_true()
	assert_bool(IOSLightmapFallbackScript._wants_fallback("Android", " ON ")).is_true()


func test_valores_apagados_de_la_variable_no_fuerzan_nada() -> void:
	assert_bool(IOSLightmapFallbackScript._wants_fallback("iOS", "0")).is_false()
	assert_bool(IOSLightmapFallbackScript._wants_fallback("iOS", " OFF ")).is_false()
	assert_bool(IOSLightmapFallbackScript._wants_fallback("X11", "false")).is_false()
