extends GdUnitTestSuite

# Test focalizado de DomeSystemDirector (FD-289 §7.1, T2).
# Cubre: orden de beats, buffer de eventos fuera de orden, idempotencia de mark_healthy,
# 4/4 -> blast_door_open + hangar_ready, snapshot/restore fiel y silencioso, y la señal
# airlock_exit. No corre la suite completa (AGENTS.md §6.1).

const DirectorScript = preload("res://core_v2/systems/dome/DomeSystemDirector.gd")
const NetworkStatusScript = preload("res://core_v2/systems/dome/DomeNetworkStatus.gd")
const ConfigScript = preload("res://core_v2/systems/dome/DomeEnvConfig.gd")

const CONFIG_PATH := "res://core_v2/systems/dome/DomeEnvConfig_intro.tres"


func _make_director() -> Node:
	var cfg: Resource = load(CONFIG_PATH)
	var director = auto_free(DirectorScript.new())
	director.env_config = cfg
	director.auto_load_airlock_scene = false
	add_child(director)
	return director


func _make_status() -> Node:
	var status = auto_free(NetworkStatusScript.new())
	add_child(status)
	return status


func _make_custom_config(airlock_scene: String) -> Resource:
	# Config mínima equivalente a la de intro pero con exterior configurable, para probar
	# que request_airlock_exit() no emite cuando no hay destino.
	var cfg = auto_free(ConfigScript.new())
	cfg.dome_id = "test"
	cfg.networks = PoolStringArray(["criocoolant", "plasma", "aire", "energia"])
	cfg.timeline = [
		{"beat": 1, "event": "on_first_power_attempt", "action": "spawn_coolant_leak"},
		{"beat": 2, "event": "coolant_healthy", "action": "enable_auxpower_lever"},
		{"beat": 3, "event": "energy_healthy", "action": "enable_plasma_route"},
		{"beat": 4, "event": "plasma_healthy", "action": "enable_air_system"},
		{"beat": 5, "event": "air_healthy", "action": "open_blast_door"},
	]
	cfg.exterior_airlock_scene = airlock_scene
	return cfg


# --- ORDEN DE BEATS ---

func test_beats_fire_in_canonical_order() -> void:
	var director := _make_director()
	var fired: Array = []
	director.connect("timeline_event", self, "_record_timeline_event", [fired])

	director.request_first_power_attempt()
	assert_int(fired.size()).is_equal(1)
	assert_int(fired[0]["beat"]).is_equal(1)
	assert_str(fired[0]["event"]).is_equal("on_first_power_attempt")
	assert_str(fired[0]["action"]).is_equal("spawn_coolant_leak")
	assert_int(director.get_current_beat()).is_equal(1)

	# Fuera de orden: energy (beat 3) llega antes que coolant (beat 2). No dispara todavía.
	assert_bool(director.notify_event("energy_healthy")).is_false()
	assert_int(fired.size()).is_equal(1)

	# coolant (beat 2) destraba la secuencia y arrastra el pendiente energy (beat 3).
	assert_bool(director.notify_event("coolant_healthy")).is_true()
	assert_int(fired.size()).is_equal(3)
	assert_int(fired[1]["beat"]).is_equal(2)
	assert_str(fired[1]["action"]).is_equal("enable_auxpower_lever")
	assert_int(fired[2]["beat"]).is_equal(3)
	assert_str(fired[2]["action"]).is_equal("enable_plasma_route")

	assert_bool(director.notify_event("plasma_healthy")).is_true()
	assert_int(fired.size()).is_equal(4)
	assert_str(fired[3]["action"]).is_equal("enable_air_system")

	assert_bool(director.notify_event("air_healthy")).is_true()
	assert_int(fired.size()).is_equal(5)
	assert_str(fired[4]["action"]).is_equal("open_blast_door")
	assert_int(director.get_current_beat()).is_equal(5)

	# Idempotente: repetir un beat ya disparado no vuelve a emitir.
	assert_bool(director.notify_event("air_healthy")).is_false()
	assert_int(fired.size()).is_equal(5)


func test_unknown_event_is_ignored() -> void:
	var director := _make_director()
	assert_bool(director.notify_event("no_existe")).is_false()
	assert_int(director.get_current_beat()).is_equal(0)


# --- 4/4 REDES ---

func test_four_healthy_networks_emit_blast_door_and_hangar() -> void:
	var director := _make_director()
	director.request_first_power_attempt()
	var status := _make_status()
	director.register_network_status(status)

	var doors: Array = [0]
	var hangars: Array = [0]
	director.connect("blast_door_open", self, "_bump_noargs", [doors])
	director.connect("hangar_ready", self, "_bump_noargs", [hangars])

	status.mark_healthy("criocoolant")
	status.mark_healthy("energia")
	status.mark_healthy("plasma")
	assert_int(doors[0]).is_equal(0)
	assert_int(hangars[0]).is_equal(0)
	assert_int(director.get_healthy_count()).is_equal(3)
	assert_bool(director.is_all_healthy()).is_false()

	status.mark_healthy("aire")
	assert_int(doors[0]).is_equal(1)
	assert_int(hangars[0]).is_equal(1)
	assert_int(director.get_healthy_count()).is_equal(4)
	assert_bool(director.is_all_healthy()).is_true()
	assert_bool(director.is_blast_door_open()).is_true()
	assert_bool(director.is_hangar_ready()).is_true()

	# Los alias red->evento hicieron avanzar el timeline completo (1..5).
	assert_array(director.get_fired_beats()).contains_exactly([1, 2, 3, 4, 5])

	# all_healthy() sin red nueva no re-dispara.
	status.mark_healthy("criocoolant")
	assert_int(doors[0]).is_equal(1)


func test_mark_healthy_is_idempotent_and_updates_counter_once() -> void:
	var director := _make_director()
	director.request_first_power_attempt()
	var status := _make_status()
	director.register_network_status(status)

	var healthy_events: Array = [0]
	status.connect("network_healthy", self, "_bump_onearg", [healthy_events])

	status.mark_healthy("criocoolant")
	status.mark_healthy("criocoolant")
	assert_int(healthy_events[0]).is_equal(1)
	assert_int(status.healthy_count()).is_equal(1)
	assert_int(director.get_healthy_count()).is_equal(1)
	# La primera red sana disparó el beat 2 una sola vez.
	assert_bool(director.is_beat_fired(2)).is_true()
	assert_bool(director.is_beat_fired(3)).is_false()


# --- SNAPSHOT / RESTORE ---

func test_snapshot_restore_is_faithful_and_silent() -> void:
	var director := _make_director()
	director.request_first_power_attempt()
	director.notify_event("coolant_healthy")
	assert_int(director.get_expected_beat()).is_equal(3)

	var snap: Dictionary = director.get_snapshot()

	# Avanzamos el estado para comprobar que el restore lo revierte.
	director.notify_event("energy_healthy")
	assert_bool(director.is_beat_fired(3)).is_true()
	assert_int(director.get_expected_beat()).is_equal(4)

	var reemitted: Array = [0]
	director.connect("timeline_event", self, "_bump_three_args", [reemitted])
	director.restore_snapshot(snap)

	assert_int(reemitted[0]).is_equal(0) # restore no re-emite
	assert_int(director.get_expected_beat()).is_equal(3)
	assert_bool(director.is_beat_fired(1)).is_true()
	assert_bool(director.is_beat_fired(2)).is_true()
	assert_bool(director.is_beat_fired(3)).is_false()

	# Continuar desde el snapshot da el mismo resultado que sin el desvío.
	assert_bool(director.notify_event("energy_healthy")).is_true()
	assert_bool(director.is_beat_fired(3)).is_true()
	assert_int(director.get_expected_beat()).is_equal(4)


func test_snapshot_restore_preserves_blast_door_state_without_reemitting() -> void:
	var director := _make_director()
	director.request_first_power_attempt()
	var status := _make_status()
	director.register_network_status(status)
	status.mark_healthy("criocoolant")
	status.mark_healthy("energia")
	status.mark_healthy("plasma")
	status.mark_healthy("aire")

	var snap: Dictionary = director.get_snapshot()
	assert_bool(director.is_blast_door_open()).is_true()

	var doors: Array = [0]
	director.connect("blast_door_open", self, "_bump_noargs", [doors])
	director.restore_snapshot(snap)

	assert_int(doors[0]).is_equal(0) # no re-emite al restaurar
	assert_bool(director.is_blast_door_open()).is_true()
	assert_bool(director.is_hangar_ready()).is_true()


# --- AIRLOCK EXIT ---

func test_request_airlock_exit_emits_signal_with_config_target() -> void:
	var director := _make_director()
	var targets: Array = []
	director.connect("airlock_exit", self, "_record_target", [targets])

	director.request_airlock_exit()
	assert_int(targets.size()).is_equal(1)
	assert_str(targets[0]).is_equal("res://core_v2/components/ScaffoldOrbit.tscn")

	director.request_airlock_exit("res://core_v2/levels/Custom.tscn")
	assert_int(targets.size()).is_equal(2)
	assert_str(targets[1]).is_equal("res://core_v2/levels/Custom.tscn")


func test_request_airlock_exit_without_target_does_not_emit() -> void:
	var director = auto_free(DirectorScript.new())
	director.env_config = _make_custom_config("")
	director.auto_load_airlock_scene = false
	add_child(director)

	var targets: Array = []
	director.connect("airlock_exit", self, "_record_target", [targets])
	director.request_airlock_exit()
	assert_int(targets.size()).is_equal(0)


# --- RECOLECTORES DE SEÑAL ---

func _record_timeline_event(event, action, beat, sink: Array) -> void:
	sink.append({"event": event, "action": action, "beat": beat})


func _record_target(target: String, sink: Array) -> void:
	sink.append(target)


func _bump_noargs(sink: Array) -> void:
	sink[0] += 1


func _bump_onearg(_arg, sink: Array) -> void:
	sink[0] += 1


func _bump_three_args(_a, _b, _c, sink: Array) -> void:
	sink[0] += 1
