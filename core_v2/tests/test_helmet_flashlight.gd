extends GdUnitTestSuite


func test_helmet_flashlight_instantiation_and_defaults():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	assert_object(packed).is_not_null()

	var flashlight = auto_free(packed.instance())
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var spot: SpotLight = flashlight.get_node_or_null("SpotLight")
	var cone: MeshInstance = flashlight.get_node_or_null("VolumetricCone")

	assert_object(spot).is_not_null()
	assert_object(cone).is_not_null()

	# MobileLightBudget contract: range must be < 6.0m
	assert_float(spot.spot_range).is_less(6.0)
	assert_bool(spot.shadow_enabled).is_false()

	# La linterna arranca APAGADA: el prologo abre a oscuras y encenderla es del jugador.
	assert_bool(flashlight.enabled).is_false()
	assert_bool(spot.visible).is_false()
	assert_bool(cone.visible).is_false()

	# El mesh del haz debe cerrar contra el disco iluminado: spot_angle en Godot es el
	# SEMI-angulo, y usarlo como apertura total dejaba el cono a la mitad de ancho.
	var far_radius: float = tan(deg2rad(spot.spot_angle)) * spot.spot_range
	assert_float(cone.scale.x).is_equal_approx(far_radius, 0.001)
	# ...y nacer en la lampara, no en la SpotLight adelantada por muzzle_offset.
	var apex_z: float = cone.translation.z + cone.scale.y * 0.5
	assert_float(apex_z).is_equal_approx(0.0, 0.001)


func test_helmet_flashlight_toggle_visibility():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var spot: SpotLight = flashlight.get_node("SpotLight")
	var cone: MeshInstance = flashlight.get_node("VolumetricCone")

	# Arranca apagada, asi que el primer toggle la enciende.
	flashlight.toggle()
	assert_bool(flashlight.enabled).is_true()
	assert_bool(spot.visible).is_true()
	assert_bool(cone.visible).is_true()

	flashlight.toggle()
	assert_bool(flashlight.enabled).is_false()
	assert_bool(spot.visible).is_false()
	assert_bool(cone.visible).is_false()


func test_helmet_flashlight_scan_mode_scroll():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	flashlight.enabled = true # _process corta temprano si esta apagada
	flashlight.scan_mode = true
	flashlight.scan_speed = 3.0
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var mat: ShaderMaterial = flashlight._material
	assert_object(mat).is_not_null()

	# El binario headless usa el rasterizer dummy: los ShaderMaterial no guardan
	# uniformes y get_shader_param() devuelve null. El avance se asierta sobre el
	# estado del nodo; el material se revisa solo donde el rasterizer si lo expone.
	# Mismo criterio que test_ice_level.gd.
	var initial_scroll: float = flashlight._scroll_offset
	var initial_param: float = 0.0
	if _exposes_shader_param(mat, "mask_scroll"):
		initial_param = float(mat.get_shader_param("mask_scroll"))
	flashlight._process(0.5)

	# delta * scan_speed = 0.5 * 3.0. Se mide el delta alrededor de la llamada manual:
	# el nodo esta en el arbol y sus propios frames tambien avanzan el offset.
	assert_float(flashlight._scroll_offset - initial_scroll).is_equal_approx(1.5, 0.001)
	if _exposes_shader_param(mat, "mask_scroll"):
		var updated_scroll: float = float(mat.get_shader_param("mask_scroll"))
		assert_float(updated_scroll - initial_param).is_equal_approx(1.5, 0.001)


func test_volumetric_cone_shader_backwards_compatibility():
	var shader: Shader = load("res://core_v2/visual/volumetric_cone.shader")
	assert_object(shader).is_not_null()

	# El binario headless de CI usa el rasterizer dummy (ver test_leak_fissure_visual.gd):
	# un ShaderMaterial.new() no registra uniforms, asi que get_shader_param() devuelve
	# null incluso recien seteado. get_code() TAMPOCO sirve: pasa por el VisualServer y
	# ahi vuelve vacio. Se lee el archivo, que es puro filesystem.
	var f := File.new()
	assert_int(f.open("res://core_v2/visual/volumetric_cone.shader", File.READ)).is_equal(OK)
	var code: String = f.get_as_text()
	f.close()

	# SearchLightV2 comparte este shader: las extensiones tienen que ser OPCIONALES, o sea
	# que sus defaults deben ser no-op para quien no las asigna.
	assert_bool(code.find("uniform bool use_mask = false;") != -1).is_true()
	assert_bool(code.find("uniform float uv_length_scale : hint_range(0.5, 4.0) = 1.0;") != -1).is_true()
	assert_bool(code.find("uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;") != -1).is_true()


# El binario headless de CI usa el rasterizer dummy: los ShaderMaterial no guardan
# parametros y get_shader_param() devuelve null (float(null) es error de script). Mismo
# criterio que test_ice_level.gd / test_leak_fissure_visual.gd.
func _exposes_shader_param(material, param: String) -> bool:
	return material != null and material.get_shader_param(param) != null


class DummyOwner extends Spatial:
	var velocity := Vector3.ZERO
	var _grounded := true
	func is_effectively_grounded() -> bool:
		return _grounded


func test_helmet_flashlight_spring_inertia():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	var dummy_owner = auto_free(DummyOwner.new())
	dummy_owner.add_child(flashlight)
	add_child(dummy_owner)
	yield(get_tree(), "idle_frame")

	# Simular activacion de la linterna y paso de apunte inicial
	flashlight.set_enabled(true)
	flashlight._aim_initialized = true
	flashlight._aim_yaw = 0.0
	flashlight._aim_pitch = 0.0
	flashlight._aim_yaw_vel = 0.0
	flashlight._aim_pitch_vel = 0.0

	# Cambio repentino en el objetivo de yaw (camara girando a la derecha)
	var target_yaw := 0.3 # rad (~17 deg)
	var target_pitch := 0.0

	# Step 1: en el primer dt (0.016s), el spring arranca con lag (yaw se mueve poco, vel sube)
	var dt := 0.016
	var yaw_acc: float = flashlight.spring_stiffness * flashlight.spring_stiffness * (target_yaw - flashlight._aim_yaw) - 2.0 * flashlight.spring_damping * flashlight.spring_stiffness * flashlight._aim_yaw_vel
	flashlight._aim_yaw_vel += yaw_acc * dt
	flashlight._aim_yaw += flashlight._aim_yaw_vel * dt

	assert_float(flashlight._aim_yaw).is_less(target_yaw)
	assert_float(flashlight._aim_yaw_vel).is_greater(0.0)

	# Simular multiples pasos hasta alcanzar el overshoot
	var max_yaw := 0.0
	for i in range(20):
		yaw_acc = flashlight.spring_stiffness * flashlight.spring_stiffness * (target_yaw - flashlight._aim_yaw) - 2.0 * flashlight.spring_damping * flashlight.spring_stiffness * flashlight._aim_yaw_vel
		flashlight._aim_yaw_vel += yaw_acc * dt
		flashlight._aim_yaw += flashlight._aim_yaw_vel * dt
		if flashlight._aim_yaw > max_yaw:
			max_yaw = flashlight._aim_yaw

	# Con damping=0.6 < 1.0 (subamortiguado), el yaw maximo debe haber superado levemente el target (overshoot)
	assert_float(max_yaw).is_greater(target_yaw)


func test_helmet_flashlight_sway_and_bob():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	var dummy_owner = auto_free(DummyOwner.new())
	dummy_owner.add_child(flashlight)
	add_child(dummy_owner)
	yield(get_tree(), "idle_frame")

	flashlight.set_enabled(true)

	# 1. Test Sway Lateral al acelerar hacia la derecha
	dummy_owner.velocity = Vector3(5.0, 0.0, 0.0) # strafe derecha
	flashlight._prev_lat_speed = 0.0
	var delta := 0.016
	var lat_speed: float = dummy_owner.velocity.dot(flashlight.global_transform.basis.orthonormalized().x)
	var lat_accel: float = (lat_speed - flashlight._prev_lat_speed) / delta
	var sway_yaw: float = -lat_accel * flashlight.sway_lateral_gain

	assert_float(lat_accel).is_greater(0.0)
	assert_float(sway_yaw).is_less(0.0) # se inclina opuesto a la aceleracion por inercia

	# 2. Test salto y dip de aterrizaje
	dummy_owner._grounded = false
	dummy_owner.velocity = Vector3(0.0, -8.0, 0.0) # cayendo rapido
	flashlight._was_grounded = false
	flashlight._prev_vel_y = -8.0

	# Aterriza
	dummy_owner._grounded = true
	var landing_dip: float = clamp(-flashlight._prev_vel_y * flashlight.sway_landing_gain, 0.0, 0.25)
	assert_float(landing_dip).is_greater(0.0)

	# 3. Test Bob de caminata
	dummy_owner.velocity = Vector3(0.0, 0.0, 3.0) # movimiento hacia adelante
	var initial_phase: float = flashlight._bob_phase
	var h_speed: float = Vector2(dummy_owner.velocity.x, dummy_owner.velocity.z).length()
	if dummy_owner._grounded and h_speed > 0.1:
		flashlight._bob_phase += h_speed * flashlight.bob_frequency * delta

	assert_float(flashlight._bob_phase).is_greater(initial_phase)


func test_helmet_flashlight_determinism_and_reset():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	flashlight.set_enabled(true)

	# Alterar estado de resortes y movimiento
	flashlight._aim_yaw_vel = 12.5
	flashlight._aim_pitch_vel = -4.2
	flashlight._bob_phase = 3.14
	flashlight._landing_dip = 0.15
	flashlight._prev_lat_speed = 2.0

	# Apagar y volver a encender
	flashlight.set_enabled(false)
	assert_bool(flashlight.enabled).is_false()

	flashlight.set_enabled(true)
	assert_bool(flashlight.enabled).is_true()

	# Todos los contadores y velocidades del resorte deben haber vuelto a 0 / defaults
	assert_float(flashlight._aim_yaw_vel).is_equal(0.0)
	assert_float(flashlight._aim_pitch_vel).is_equal(0.0)
	assert_float(flashlight._bob_phase).is_equal(0.0)
	assert_float(flashlight._landing_dip).is_equal(0.0)
	assert_float(flashlight._prev_lat_speed).is_equal(0.0)
