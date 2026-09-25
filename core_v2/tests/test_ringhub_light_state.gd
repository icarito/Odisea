extends GdUnitTestSuite

# O20 — Estados de iluminacion DARK/LIT del domo de RingHub: el estado cambia el
# ambiente (desktop y flat), la transicion es un flicker determinista con sonido,
# y el boton de pedestal contra la pared lo alterna.

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")


func _boot_level() -> Spatial:
	var level: Spatial = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	return level


func _wait_flicker(state) -> void:
	for _i in range(400):
		if not state._flicker_active:
			return
		yield(get_tree(), "physics_frame")


func test_light_state_exists_and_button_is_wired() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var state = level.get_node_or_null("LightState")
	assert_object(state).is_not_null()
	assert_bool(state.has_method("set_lit")).is_true()
	assert_bool(state.has_method("toggle")).is_true()
	assert_bool(state.is_in_group("replay_sync")).is_true()

	var button = level.get_node_or_null("Hub/PedestalLight")
	assert_object(button).is_not_null()
	# Momentary: cada pulsacion dispara un solo `activated`, sin un `deactivated`
	# posterior que vuelva a alternar.
	assert_bool(button.momentary).is_true()
	assert_bool(button.is_connected("activated", state, "_on_button_activated")).is_true()

	# El estado arranca en DARK y el ambient ya quedo aplicado.
	assert_bool(state.lit).is_false()
	assert_float(state._level).is_equal(0.0)
	var env: Environment = state._dark_lighting.get_environment()
	assert_object(env).is_not_null()
	assert_float(env.ambient_light_energy).is_less(0.1)


func test_flicker_is_stepped_deterministic_and_lights_up() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")
	var env: Environment = state._dark_lighting.get_environment()
	assert_object(env).is_not_null()

	# El patron es una tabla de niveles, no una rampa: pasos distintos en la misma
	# fraccion de tiempo de paso.
	var dark_ambient: float = env.ambient_light_energy
	state.set_lit(true)
	assert_bool(state.lit).is_true()
	assert_bool(state._flicker_active).is_true()
	assert_int(state._switch_sounds_played).is_equal(1)
	assert_float(state._sample_level(0.0)).is_equal(0.0)
	assert_float(state._sample_level(state.flicker_step_time * 1.5)).is_equal(1.0)
	assert_float(state._sample_level(state.flicker_step_time * 2.5)).is_equal(0.0)
	yield(_wait_flicker(state), "completed")

	assert_bool(state._flicker_active).is_false()
	assert_float(state._level).is_equal(1.0)
	# LIT ilumina el ambiente...
	assert_float(env.ambient_light_energy).is_greater(dark_ambient + 0.5)
	# ...y prende la emision de las lamparas.
	assert_array(state._fixture_materials).is_not_empty()
	var glass: SpatialMaterial = state._fixture_materials[0]
	assert_float(glass.emission_energy).is_greater(0.1)

	# Apagar vuelve a DARK sin sonido extra.
	state.set_lit(false)
	yield(_wait_flicker(state), "completed")
	assert_bool(state.lit).is_false()
	assert_float(state._level).is_equal(0.0)
	assert_float(env.ambient_light_energy).is_less(0.1)
	assert_float(glass.emission_energy).is_equal(0.0)
	assert_int(state._switch_sounds_played).is_equal(1)


func test_snapshot_restores_mid_flicker_deterministically() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")

	state.set_lit(true)
	for _i in range(6):
		yield(get_tree(), "physics_frame")
	var snap: Dictionary = state.get_snapshot()
	assert_bool(snap["flicker_active"]).is_true()

	# Corromper el reloj y restaurar: el nivel aplicado debe volver al muestreo del
	# snapshot, sin sonido.
	var sounds_before: int = state._switch_sounds_played
	state._flicker_clock = 99.0
	state.restore_snapshot(snap)
	assert_float(state._flicker_clock).is_equal(float(snap["flicker_clock"]))
	assert_bool(state._flicker_active).is_true()
	assert_float(state._level).is_equal(state._sample_level(state._flicker_clock))
	assert_int(state._switch_sounds_played).is_equal(sounds_before)


func test_flat_path_drives_gate_levers() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	assert_object(gate).is_not_null()
	var prev_mode = gate._unshaded_mode
	var prev_ambient = gate._flat_ambient
	var prev_world = gate._world_light
	var prev_glow = gate._glow_floor
	# Fingir el tier plano: is_flat_mode() solo mira _unshaded_mode.
	gate._unshaded_mode = "3"
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")
	# En modo plano no se crean luminarias: los materiales unshaded no reciben luz.
	assert_array(state._luminaries).is_empty()
	# DARK baja las palancas del FlatFake...
	assert_float(gate._flat_ambient).is_equal_approx(state.dark_flat_ambient, 0.0001)
	# ...y LIT las sube (el Environment no ilumina unshaded).
	state.set_lit(true)
	yield(_wait_flicker(state), "completed")
	assert_float(gate._flat_ambient).is_equal_approx(state.lit_flat_ambient, 0.0001)
	assert_float(gate._world_light).is_equal_approx(state.lit_flat_world_light, 0.0001)
	assert_float(gate._glow_floor).is_equal_approx(state.lit_flat_glow_floor, 0.0001)
	gate._unshaded_mode = prev_mode
	gate._flat_ambient = prev_ambient
	gate._world_light = prev_world
	gate._glow_floor = prev_glow


func test_dark_zeroes_pool_and_lit_restores_it() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")
	var wall = level.get_node("Hub/WallLights")
	# DARK tambien apaga el pool: el export de creacion queda en 0 para que las
	# OmniLight perezosas nazcan apagadas...
	assert_float(float(wall.light_energy)).is_equal(0.0)
	# ...y la energia directa tambien se aplica a las que ya existan.
	for _i in range(40):
		yield(get_tree(), "physics_frame")
	var lights := []
	for child in wall.get_children():
		if child is OmniLight:
			lights.append(child)
	assert_array(lights).is_not_empty()
	for light in lights:
		assert_float(light.light_energy).is_equal(0.0)

	state.set_lit(true)
	yield(_wait_flicker(state), "completed")
	assert_float(float(wall.light_energy)).is_greater(0.1)
	for light in lights:
		assert_float(light.light_energy).is_greater(0.1)


func test_switch_sound_is_one_shot_and_leaves_shared_resource_alone() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")
	assert_object(state._sound_player).is_not_null()
	# El player usa una copia sin loop...
	assert_bool(bool(state._sound_player.stream.loop)).is_false()
	# ...y el recurso importado compartido (wall lights de Dome_Intro) sigue en loop.
	assert_bool(bool(state.switch_sound.loop)).is_true()


func test_relit_same_target_does_not_restart_flicker_or_replay() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")

	state.set_lit(true)
	for _i in range(3):
		yield(get_tree(), "physics_frame")
	var clock: float = state._flicker_clock
	var sounds: int = state._switch_sounds_played
	assert_bool(state._flicker_active).is_true()
	# Re-entrada con el mismo target: no reinicia el reloj ni vuelve a sonar.
	state.set_lit(true)
	assert_float(state._flicker_clock).is_equal(clock)
	assert_int(state._switch_sounds_played).is_equal(sounds)
	yield(_wait_flicker(state), "completed")
	assert_float(state._level).is_equal(1.0)
	assert_int(state._switch_sounds_played).is_equal(1)


func test_luminaries_light_the_whole_dome_in_lit() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var state = level.get_node_or_null("LightState")
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate != null and (bool(gate.is_flat_mode()) or bool(gate.is_low_tier())):
		# En tier bajo/plano no se crean: la iluminancia la da _apply_flat.
		assert_array(state._luminaries).is_empty()
		return
	if OS.get_name() in ["Android", "iOS"] or OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE") in ["1", "true", "yes", "on"]:
		# En movil tampoco: 16 luces reales son fillrate puro.
		assert_array(state._luminaries).is_empty()
		return
	# Una luminaria por cada una de las 16 lamparas de pared, repartidas por todo
	# el anillo: DARK apagadas, LIT encendidas mas alla del pool que sigue al player.
	assert_int(state._luminaries.size()).is_equal(16)
	for light in state._luminaries:
		assert_bool(light.visible).is_false()
		assert_float(light.light_energy).is_equal(0.0)
	state.set_lit(true)
	yield(_wait_flicker(state), "completed")
	for light in state._luminaries:
		assert_bool(light.visible).is_true()
		assert_float(light.light_energy).is_greater(0.1)
	state.set_lit(false)
	yield(_wait_flicker(state), "completed")
	for light in state._luminaries:
		assert_bool(light.visible).is_false()
		assert_float(light.light_energy).is_equal(0.0)


func test_gles3_gate_exposes_flat_light_setters() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	assert_object(gate).is_not_null()
	assert_bool(gate.has_method("set_flat_ambient")).is_true()
	assert_bool(gate.has_method("set_flat_world_light")).is_true()
	assert_bool(gate.has_method("set_flat_glow_floor")).is_true()

	var prev_ambient = gate._flat_ambient
	var prev_world = gate._world_light
	var prev_glow = gate._glow_floor
	gate.set_flat_ambient(0.42)
	assert_float(gate._flat_ambient).is_equal(0.42)
	gate.set_flat_world_light(0.77)
	assert_float(gate._world_light).is_equal(0.77)
	gate.set_flat_glow_floor(0.11)
	assert_float(gate._glow_floor).is_equal(0.11)
	# Restaurar para no contaminar otras suites del mismo proceso.
	gate.set_flat_ambient(prev_ambient)
	gate.set_flat_world_light(prev_world)
	gate.set_flat_glow_floor(prev_glow)
