extends GdUnitTestSuite

# El dither estable (matriz de Bayer) existe porque el hash IGN se degrada en el
# mediump de los fragment shaders GLES2 moviles. Estaba atado a "Android" solo y iOS
# corria por la rama rota, con los props del manager desapareciendo en el dispositivo.

const PropDitherManagerScript = preload("res://core_v2/autoloads/PropDitherManager.gd")


func test_stable_dither_covers_every_mobile_gles2() -> void:
	assert_bool(PropDitherManagerScript._wants_stable_dither("iOS")).is_true()
	assert_bool(PropDitherManagerScript._wants_stable_dither("Android")).is_true()


func test_desktop_keeps_the_cheaper_hash() -> void:
	# En escritorio no hay mediump: el IGN es mas barato y no tiene el problema.
	assert_bool(PropDitherManagerScript._wants_stable_dither("X11")).is_false()
	assert_bool(PropDitherManagerScript._wants_stable_dither("Windows")).is_false()
	assert_bool(PropDitherManagerScript._wants_stable_dither("OSX")).is_false()


func test_el_dither_no_depende_de_la_plataforma() -> void:
	# El gate por plataforma (iOS = false) existia por un sintoma cuya causa real era el
	# lightmap del motor atado a la unidad de textura 4, ya arreglada en
	# IOSLightmapFallback. Con el gate puesto, en iOS los andamios nunca se volvian
	# translucidos y los props sin hornear no pasaban por el shader de oclusion.
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("", true)).is_true()
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("", false)).is_false()


func test_la_variable_de_entorno_manda_sobre_la_opcion() -> void:
	# Para comparar A/B en el dispositivo sin depender del menu ni de otro build.
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("0", true)).is_false()
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("off", true)).is_false()
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("1", false)).is_true()
	assert_bool(PropDitherManagerScript._wants_occlusion_dither(" ON ", false)).is_true()
