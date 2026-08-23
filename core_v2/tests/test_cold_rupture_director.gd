extends GdUnitTestSuite

# test_cold_rupture_director.gd - Unit & integration tests for ColdRuptureDirector and OYS integration.

const ColdRuptureDirectorScript = preload("res://core_v2/systems/cryo/ColdRuptureDirector.gd")
const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const OYSTriggerScript = preload("res://core_v2/components/OYSTrigger.gd")
const RandomLeakSeederScript = preload("res://core_v2/systems/cryo/RandomLeakSeeder.gd")


func test_director_registers_and_handles_oys_calls() -> void:
	var root = Spatial.new()
	add_child(root)

	var director = ColdRuptureDirectorScript.new()
	director.name = "ColdRuptureDirector"
	root.add_child(director)

	var focus = Spatial.new()
	focus.name = "RuptureFocus"
	root.add_child(focus)

	var seeder = RandomLeakSeederScript.new()
	seeder.name = "RandomLeakSeeder"
	root.add_child(seeder)

	var sm = director.get_node_or_null("/root/SessionManager")
	if sm != null:
		assert_bool(sm.get_oys_actor("ColdRupture") == director).is_true()

	var expl_pos = director.spawn_explosion()
	assert_bool(director.consumed).is_true()
	assert_bool(director.last_explosion_pos == expl_pos).is_true()

	var snapshot = director.get_snapshot()
	assert_bool(snapshot["consumed"]).is_true()

	var director2 = ColdRuptureDirectorScript.new()
	director2.name = "ColdRuptureDirector2"
	root.add_child(director2)
	director2.restore_snapshot(snapshot)
	assert_bool(director2.consumed).is_true()
	assert_bool(director2.last_explosion_pos == expl_pos).is_true()
	root.queue_free()


func test_oys_trigger_script_clears_file_on_trigger() -> void:
	var trigger = OYSTriggerScript.new()
	trigger.script_file = ""
	trigger.trigger_once = true
	add_child(trigger)
	yield(get_tree(), "idle_frame")

	# El SessionManager es un autoload COMPARTIDO por las 50 suites del run de CI, y
	# is_respawning / is_replaying deciden si el disparador ejecuta o saltea el script.
	# Este caso asegura que una entrada NORMAL quema trigger_once, asi que tiene que
	# declarar que la entrada es normal en vez de heredar lo que dejo otra suite.
	var session = get_node_or_null("/root/SessionManager")
	var previous := {}
	if session != null:
		previous = {
			"respawning": session.is_respawning,
			"replaying": session.is_replaying,
			"recording": session.is_recording
		}
		session.is_respawning = false
		session.is_replaying = false
		session.is_recording = false

	trigger.script_file = "res://core_v2/levels/interiors/cold_rupture.oys"
	assert_bool(trigger.script_file != "").is_true()
	trigger.trigger_from_script(trigger)
	var cleared: bool = trigger.script_file == ""

	if session != null:
		session.is_respawning = bool(previous["respawning"])
		session.is_replaying = bool(previous["replaying"])
		session.is_recording = bool(previous["recording"])

	assert_bool(cleared).is_true()


# Regla del domo: mientras quede una fuga viva suena el latido; cuando la ultima se
# parchea o se queda sin presion, la musica vuelve a la de la zona.
func test_leak_state_drives_the_dome_music() -> void:
	var am = get_node("/root/AudioManager")
	assert_object(am).is_not_null()
	am.reset()

	var director = auto_free(ColdRuptureDirectorScript.new())
	director.name = "ColdRuptureDirectorMusic"
	add_child(director)

	var leak: Spatial = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.0
	leak.ramp_up_duration = 0.0
	add_child(leak)

	director._connect_leak_music()
	assert_str(am.get_song_override()).is_equal("")

	leak.trigger_leak()
	assert_str(am.get_song_override()).is_equal(director.leak_song)

	# Parche firme: la fuga se sella y la calma vuelve.
	leak.seal()
	leak._physics_process(leak.dissipate_duration + 0.1)
	assert_bool(director.has_active_leak()).is_false()
	assert_str(am.get_song_override()).is_equal("")

	am.reset()


# Cerrar la valvula aguas arriba (DEPRESSURIZED) tambien cuenta como "sin fuga activa".
func test_depressurized_leak_returns_to_calm_music() -> void:
	var am = get_node("/root/AudioManager")
	am.reset()

	var director = auto_free(ColdRuptureDirectorScript.new())
	director.name = "ColdRuptureDirectorValve"
	add_child(director)

	var leak: Spatial = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.0
	leak.ramp_up_duration = 0.0
	add_child(leak)

	director._connect_leak_music()
	leak.trigger_leak()
	assert_str(am.get_song_override()).is_equal(director.leak_song)

	leak.depressurize()
	assert_str(am.get_song_override()).is_equal("")

	am.reset()


# El respawn arranca con la musica de la zona; si el checkpoint restaura fugas abiertas,
# el director vuelve a pedir el latido al restaurar su snapshot (esta en 'replay_sync').
func test_respawn_returns_to_zone_music_and_snapshot_restores_the_heartbeat() -> void:
	var am = get_node("/root/AudioManager")
	am.reset()

	var director = auto_free(ColdRuptureDirectorScript.new())
	director.name = "ColdRuptureDirectorRespawn"
	add_child(director)

	var leak: Spatial = auto_free(CoolantLeakScript.new())
	leak.name = "LeakForRespawn"
	leak.warning_duration = 0.0
	leak.ramp_up_duration = 0.0
	add_child(leak)

	director._connect_leak_music()
	leak.trigger_leak()
	assert_str(am.get_song_override()).is_equal(director.leak_song)

	var snapshot: Dictionary = director.get_snapshot()
	assert_bool(bool(snapshot["leak_music"])).is_true()

	# Lo que hace el respawn: soltar el override y volver a la musica de la zona.
	am.restart_bgm_from_active_zones()
	assert_str(am.get_song_override()).is_equal("")

	# El checkpoint trae la fuga abierta: el director la reconoce y vuelve a pedir latido.
	director.restore_snapshot(snapshot)
	director._sync_leak_music()
	assert_bool(director.has_active_leak()).is_true()
	assert_str(am.get_song_override()).is_equal(director.leak_song)

	# Y si el respawn no tiene fugas vivas, se queda con la musica de la zona.
	leak.seal()
	leak._physics_process(leak.dissipate_duration + 0.1)
	am.restart_bgm_from_active_zones()
	director._sync_leak_music()
	assert_str(am.get_song_override()).is_equal("")

	am.reset()
