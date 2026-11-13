extends GdUnitTestSuite

# Test focalizado de T1 (FD-289): DomeNetworkStatus + DomeEnvConfig.
# No toca niveles reales: verifica el contrato de los dos componentes nuevos.

const DomeNetworkStatusScript = preload("res://core_v2/systems/dome/DomeNetworkStatus.gd")
const INTRO_CONFIG_PATH := "res://core_v2/systems/dome/DomeEnvConfig_intro.tres"


func _make_status(total: int = 4) -> Node:
	var status = auto_free(DomeNetworkStatusScript.new())
	status.total_networks = total
	add_child(status)
	return status


func test_network_status_starts_empty_and_joins_replay_sync() -> void:
	var status = _make_status()

	assert_int(status.healthy_count()).is_equal(0)
	assert_bool(status.is_all_healthy()).is_false()
	assert_bool(status.is_healthy("criocoolant")).is_false()
	assert_bool(status.is_in_group("replay_sync")).is_true()


func test_mark_healthy_emits_signal_and_is_idempotent() -> void:
	var status = _make_status()
	var network_events := []
	var all_events := [0]
	status.connect("network_healthy", self, "_on_network_healthy", [network_events])
	status.connect("all_healthy", self, "_on_all_healthy", [all_events])

	status.mark_healthy("criocoolant")
	assert_int(status.healthy_count()).is_equal(1)
	assert_bool(status.is_healthy("criocoolant")).is_true()
	assert_int(network_events.size()).is_equal(1)
	assert_str(network_events[0]).is_equal("criocoolant")

	# Re-notificar la misma red no duplica el conteo ni re-emite.
	status.mark_healthy("criocoolant")
	assert_int(status.healthy_count()).is_equal(1)
	assert_int(network_events.size()).is_equal(1)

	# Un id vacío se ignora.
	status.mark_healthy("")
	assert_int(status.healthy_count()).is_equal(1)
	assert_int(all_events[0]).is_equal(0)


func test_all_healthy_emitted_once_at_total() -> void:
	var status = _make_status(4)
	var all_events := [0]
	status.connect("all_healthy", self, "_on_all_healthy", [all_events])

	status.mark_healthy("criocoolant")
	status.mark_healthy("plasma")
	status.mark_healthy("aire")
	assert_int(all_events[0]).is_equal(0)
	assert_bool(status.is_all_healthy()).is_false()

	status.mark_healthy("energia")
	assert_bool(status.is_all_healthy()).is_true()
	assert_int(all_events[0]).is_equal(1)

	# Una red extra no vuelve a emitir all_healthy.
	status.mark_healthy("extra")
	assert_int(all_events[0]).is_equal(1)


func test_mark_unhealthy_rearms_all_healthy() -> void:
	var status = _make_status(2)
	var all_events := [0]
	status.connect("all_healthy", self, "_on_all_healthy", [all_events])

	status.mark_healthy("criocoolant")
	status.mark_healthy("plasma")
	assert_int(all_events[0]).is_equal(1)

	status.mark_unhealthy("plasma")
	assert_bool(status.is_all_healthy()).is_false()
	assert_int(status.healthy_count()).is_equal(1)

	status.mark_healthy("plasma")
	assert_int(all_events[0]).is_equal(2)


func test_snapshot_restore_determinism() -> void:
	var status = _make_status(4)
	status.mark_healthy("criocoolant")
	status.mark_healthy("plasma")
	var snap: Dictionary = status.get_snapshot()
	assert_dict(snap).contains_keys(["healthy", "all_healthy_emitted"])

	var status2 = _make_status(4)
	status2.restore_snapshot(snap)

	assert_int(status2.healthy_count()).is_equal(2)
	assert_bool(status2.is_healthy("criocoolant")).is_true()
	assert_bool(status2.is_healthy("plasma")).is_true()
	assert_bool(status2.is_healthy("aire")).is_false()

	# Completar el equilibrio: restaurado o fresco, el resultado final coincide.
	status.mark_healthy("aire")
	status.mark_healthy("energia")
	status2.mark_healthy("aire")
	status2.mark_healthy("energia")
	assert_int(status2.healthy_count()).is_equal(status.healthy_count())
	assert_bool(status2.is_all_healthy()).is_true()


func test_intro_config_resource_fields() -> void:
	var config = load(INTRO_CONFIG_PATH)
	assert_object(config).is_not_null()
	assert_bool(config is Resource).is_true()
	assert_str(config.dome_id).is_equal("intro")
	assert_int(config.network_count()).is_equal(4)
	assert_bool(config.has_network("criocoolant")).is_true()
	assert_bool(config.has_network("plasma")).is_true()
	assert_bool(config.has_network("aire")).is_true()
	assert_bool(config.has_network("energia")).is_true()
	assert_bool(config.has_network("desconocida")).is_false()
	assert_str(config.hangar_spawn_id).is_equal("from_dome_intro_platform")
	assert_str(config.hangar_scene).ends_with("Dome_Intro_Hangar.tscn")
	assert_str(config.exterior_airlock_scene).ends_with("ScaffoldOrbit.tscn")
	assert_bool(config.blast_door_path is NodePath).is_true()


func test_intro_config_timeline_actions() -> void:
	var config = load(INTRO_CONFIG_PATH)
	assert_int(config.timeline.size()).is_equal(5)
	assert_str(config.get_timeline_action("on_first_power_attempt")).is_equal("spawn_coolant_leak")
	assert_str(config.get_timeline_action("coolant_healthy")).is_equal("enable_auxpower_lever")
	assert_str(config.get_timeline_action("energy_healthy")).is_equal("enable_plasma_route")
	assert_str(config.get_timeline_action("plasma_healthy")).is_equal("enable_air_system")
	assert_str(config.get_timeline_action("air_healthy")).is_equal("open_blast_door")
	assert_str(config.get_timeline_action("missing_event")).is_equal("")


func _on_network_healthy(network_id: String, sink: Array) -> void:
	sink.append(network_id)


func _on_all_healthy(sink: Array) -> void:
	sink[0] += 1
