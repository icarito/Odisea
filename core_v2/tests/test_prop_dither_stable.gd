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


func test_ios_no_convierte_props_al_shader_de_oclusion() -> void:
	# Los props convertidos son los que no se dibujan en el dispositivo; apagado en iOS
	# conservan su SpatialMaterial original.
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("iOS")).is_false()
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("Android")).is_true()
	assert_bool(PropDitherManagerScript._wants_occlusion_dither("X11")).is_true()
