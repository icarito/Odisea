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


# El presupuesto de varyings es lo que rompio iOS en silencio: el shader tuvo 2 hasta
# 23a32022, que subio a 4 para use_world_uv, y desde entonces las superficies que el
# manager convierte no se dibujaban en el dispositivo. iOS/PowerVR GLES2 solo garantiza
# 8 varying vectors y scene.glsl ya se come casi todos. card_parallax y
# seam_road_lines_pbr, con MAS samplers y tambien con discard, se dibujan bien con 2.
const MAX_VARYINGS := 2
const SHADERS := [
	"res://shaders/prop_dither_occlusion.gdshader",
	"res://shaders/prop_dither_occlusion_double_sided.gdshader",
	"res://shaders/prop_dither_occlusion_unshaded.gdshader",
]

func test_los_shaders_de_oclusion_no_se_pasan_del_presupuesto_de_varyings() -> void:
	for path in SHADERS:
		var f := File.new()
		assert_int(f.open(path, File.READ)).is_equal(OK)
		var code := f.get_as_text()
		f.close()
		var n := 0
		for line in code.split("\n"):
			if line.strip_edges().begins_with("varying "):
				n += 1
		assert_int(n).override_failure_message(
			"%s declara %d varyings; el maximo seguro en iOS GLES2 es %d" % [path, n, MAX_VARYINGS]
		).is_less_equal(MAX_VARYINGS)


func test_las_mascaras_de_canales_cubren_mrao_y_arm() -> void:
	assert_bool(PropDitherManagerScript._channel_mask(0) == Color(1, 0, 0, 0)).is_true()
	assert_bool(PropDitherManagerScript._channel_mask(1) == Color(0, 1, 0, 0)).is_true()
	assert_bool(PropDitherManagerScript._channel_mask(2) == Color(0, 0, 1, 0)).is_true()


func test_double_sided_no_protege_caras_internas_como_piso() -> void:
	var f := File.new()
	assert_int(f.open(SHADERS[1], File.READ)).is_equal(OK)
	var code := f.get_as_text()
	f.close()
	assert_bool(code.find("bool floor_under   = FRONT_FACING &&") >= 0).is_true()
	assert_bool(code.find("bool ceiling_above = FRONT_FACING &&") >= 0).is_true()
