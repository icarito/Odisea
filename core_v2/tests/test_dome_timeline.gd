extends GdUnitTestSuite

# FD-289 §9 T8 / §10 — test headless del CICLO COMPLETO del domo (beats 1→8) + snapshot/restore.
#
# Corre sobre el nivel de máquinas REAL (DomeMachineLevel: DomeNetworkStatus + DomeNetworkWiring
# + los props de las 4 redes + BlastDoorController) y un DomeSystemDirector LOCAL cuyo
# env_config es el DomeEnvConfig_intro.tres de producción. Determina el estado por eventos, sin
# randf ni reloj de pared (AGENTS.md §5.3): no hay yields de tiempo, solo idle_frame para los
# bindings deferred de los props.
#
# QUÉ CUBRE (el gap que T2/T6/T7 no prueban end-to-end):
#   1. Ciclo 1→5 con los props reales, en orden canónico, disparado por las interacciones
#      (interruptor principal → coolant → palanca del bus → válvula de plasma → purga de aire),
#      hasta 4/4 → blast_door_open + hangar_ready (beat 6).
#   2. GATING FINO DEL BUS: la palanca del bus no restaura energía hasta que el timeline habilita
#      `enable_auxpower_lever` (beat 2, tras coolant). §5 beat 3 "acoplado al coolant".
#   3. BUFFER OUT-OF-ORDER: redes que sanan antes de tiempo no saltean beats; el director las
#      guarda y las dispara en orden cuando la secuencia llega al beat (§7.1).
#   4. SNAPSHOT/RESTORE a mitad del ciclo (2/4): restaurar y continuar da el MISMO resultado
#      (contadores/estado) sin re-emitir señales.
#   5. Beat 6 descenso: la plataforma baja de forma determinista y el snapshot a mitad preserva
#      la posición exacta.
#   6. Beats 7/8: el hangar declarado por la config existe y `airlock_exit` apunta al exterior.
#
# QUÉ NO CUBRE (a propósito, ver reporte): la transición de escena real del descenso al hangar
# (HangarTransition/HangarPlatform no están instanciadas en Dome_Intro todavía) — se verifica el
# contrato de señales/config, no un cambio de escena en vivo.
#
# No corre la suite completa (AGENTS.md §6.1).

const MachineLevelScene := preload("res://core_v2/systems/dome/DomeMachineLevel.tscn")
const DirectorScript = preload("res://core_v2/systems/dome/DomeSystemDirector.gd")
const NetworkStatusScript = preload("res://core_v2/systems/dome/DomeNetworkStatus.gd")
const PlatformScene = preload("res://core_v2/props/hangar/HangarPlatform.tscn")

const CONFIG_PATH := "res://core_v2/systems/dome/DomeEnvConfig_intro.tres"


# --- RIG: nivel de máquinas real + director local (no usa el autoload) ---

func _make_rig() -> Dictionary:
	var host: Spatial = auto_free(Spatial.new())
	host.name = "DomeTimelineTestHost"
	add_child(host)

	var director = auto_free(DirectorScript.new())
	director.name = "LocalDirector"
	director.env_config = load(CONFIG_PATH)
	director.auto_load_airlock_scene = false
	host.add_child(director)

	var level = auto_free(MachineLevelScene.instance())
	# Redirigir el cableado al director local ANTES de entrar al árbol (su _ready resuelve).
	level.get_node("DomeNetworkWiring").director_path = director.get_path()
	host.add_child(level)

	return {
		"host": host,
		"director": director,
		"level": level,
		"status": level.get_node("DomeNetworkStatus"),
		"wiring": level.get_node("DomeNetworkWiring"),
	}


func _make_bare_director() -> Node:
	# Director aislado (sin props) para los casos de estado puro: beats, snapshot, airlock.
	var director = auto_free(DirectorScript.new())
	director.env_config = load(CONFIG_PATH)
	director.auto_load_airlock_scene = false
	add_child(director)
	return director


func _make_status(total: int = 4) -> Node:
	var status = auto_free(NetworkStatusScript.new())
	status.total_networks = total
	add_child(status)
	return status


func _spawn_platform() -> Node:
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	var platform: Node = PlatformScene.instance()
	host.add_child(platform)
	return platform


# --- PASOS DE GAMEPLAY (reusan las interacciones reales) ---

# Beat 1: el jugador acciona el interruptor principal → revela la fuga de coolant.
func _pull_master_switch(level: Node) -> void:
	level.get_node("Energy/MasterSwitch").set_active(true, true)


# Beat 2: cerrar la válvula aguas arriba (despresuriza) y parchear ambas fugas.
func _repair_coolant(level: Node) -> void:
	level.get_node("Coolant/CoolantValve").set_active(false, true)
	level.get_node("Coolant/LeakA_Patch").patch_with_gloo()
	level.get_node("Coolant/LeakB_Patch").patch_with_gloo()


# Beat 3: accionar la palanca del bus (sujeta al gate de coolant).
func _pull_bus_switch(level: Node) -> void:
	level.get_node("Energy/BusSwitch").set_active(true, true)


# Beat 4: patrón de plasma [1,0,1] → cerrar la válvula del medio.
func _solve_plasma(level: Node) -> void:
	level.get_node("Plasma/PlasmaValveB").set_active(false, true)


# Beat 5: purgar el aire en la zona verde del manómetro.
func _purge_air(level: Node) -> void:
	var dial = level.get_node("Air/AirPurgeDial")
	dial.value = dial.target
	dial._physics_process(dial.hold_duration + 0.1)


# --- 1. CICLO COMPLETO 1→5 con props reales ---

func test_full_cycle_beats_1_to_5_in_order_opens_blast_door() -> void:
	var rig := _make_rig()
	var director = rig["director"]
	var status = rig["status"]
	var level: Node = rig["level"]
	yield(get_tree(), "idle_frame") # PlasmaRoute._bind_valves es deferred

	var door = level.get_node("Doors/BlastDoor")
	director.connect("blast_door_open", door, "on_blast_door_open")

	# El bus real tarda restore_duration en rampar; en el test lo hacemos inmediato para no
	# depender de ticks de física (la rampa la cubre el propio AuxPowerBus).
	level.get_node("Energy/AuxPowerBus").restore_duration = 0.0

	var events: Array = []
	director.connect("timeline_event", self, "_record_event", [events])

	_pull_master_switch(level)   # beat 1
	_repair_coolant(level)       # beat 2
	_pull_bus_switch(level)      # beat 3
	_solve_plasma(level)         # beat 4
	_purge_air(level)            # beat 5

	assert_array(_events_in_order(events)).contains_exactly([
		"on_first_power_attempt", "coolant_healthy", "energy_healthy",
		"plasma_healthy", "air_healthy",
	])
	assert_array(_beats_in_order(events)).contains_exactly([1, 2, 3, 4, 5])
	assert_int(director.get_current_beat()).is_equal(5)

	# 4/4 → equilibrio, blast door (beat 6) y hangar listos.
	assert_int(status.healthy_count()).is_equal(4)
	assert_bool(status.is_all_healthy()).is_true()
	assert_bool(director.is_blast_door_open()).is_true()
	assert_bool(director.is_hangar_ready()).is_true()
	assert_bool(door.is_open()).is_true()
	assert_int(door.get_network_healthy_count()).is_equal(4)


# --- 2. GATING FINO DEL BUS ---

func test_bus_switch_is_gated_until_coolant_healthy() -> void:
	var rig := _make_rig()
	var director = rig["director"]
	var status = rig["status"]
	var level: Node = rig["level"]
	var wiring = rig["wiring"]
	yield(get_tree(), "idle_frame")

	var bus = level.get_node("Energy/AuxPowerBus")
	bus.restore_duration = 0.0

	# Estado inicial: la palanca del bus todavía NO está habilitada (§5 beat 3).
	assert_bool(wiring.is_auxpower_enabled()).is_false()
	_pull_bus_switch(level)
	assert_int(bus.get_state()).is_equal(bus.State.OFFLINE)
	assert_bool(status.is_healthy("energia")).is_false()
	assert_bool(director.is_beat_fired(3)).is_false()

	# Beat 1 + reparar coolant: el beat 2 habilita la palanca del bus.
	_pull_master_switch(level)
	_repair_coolant(level)
	assert_bool(director.is_beat_fired(2)).is_true()
	assert_bool(wiring.is_auxpower_enabled()).is_true()

	# Ahora sí la palanca restaura el bus y sanea la red de energía.
	_pull_bus_switch(level)
	assert_int(bus.get_state()).is_equal(bus.State.POWERED)
	assert_bool(status.is_healthy("energia")).is_true()
	assert_bool(director.is_beat_fired(3)).is_true()


# --- 3. BUFFER OUT-OF-ORDER ---

func test_out_of_order_networks_are_buffered_into_canonical_order() -> void:
	var rig := _make_rig()
	var director = rig["director"]
	var level: Node = rig["level"]
	yield(get_tree(), "idle_frame")

	var events: Array = []
	director.connect("timeline_event", self, "_record_event", [events])

	_pull_master_switch(level) # beat 1
	yield(get_tree(), "idle_frame")

	# Energía y plasma sanan ANTES que coolant. El bus se restaura directo (sin pasar por la
	# palanca, que aún está gateada) para forzar el caso fuera de orden.
	var bus = level.get_node("Energy/AuxPowerBus")
	bus.restore_duration = 0.0
	bus.request_restore()
	_solve_plasma(level)

	# Los beats futuros quedaron en espera: no saltean la secuencia.
	assert_bool(director.is_beat_fired(3)).is_false()
	assert_bool(director.is_beat_fired(4)).is_false()
	assert_array(_beats_in_order(events)).contains_exactly([1])

	# coolant llega último entre los tres: destraba 2 y arrastra 3 y 4 en orden.
	_repair_coolant(level)
	assert_array(_beats_in_order(events)).contains_exactly([1, 2, 3, 4])

	# aire completa el ciclo (beat 5).
	_purge_air(level)
	assert_array(_beats_in_order(events)).contains_exactly([1, 2, 3, 4, 5])


# --- 4. SNAPSHOT / RESTORE a mitad del ciclo ---

func test_snapshot_restore_mid_cycle_reproduces_final_state() -> void:
	var director = _make_bare_director()
	var status = _make_status()
	director.register_network_status(status)

	director.request_first_power_attempt() # beat 1
	status.mark_healthy("criocoolant")     # beat 2 → 1/4
	status.mark_healthy("energia")         # beat 3 → 2/4

	# Guardar a mitad del ciclo (2/4, beats 1..3 disparados).
	var snap := {
		"director": director.get_snapshot(),
		"status": status.get_snapshot(),
	}

	var doors: Array = [0]
	var hangars: Array = [0]
	director.connect("blast_door_open", self, "_bump_noargs", [doors])
	director.connect("hangar_ready", self, "_bump_noargs", [hangars])

	# Corrida de referencia hasta 4/4.
	status.mark_healthy("plasma")
	status.mark_healthy("aire")
	var ref_fired: Array = director.get_fired_beats()
	var ref_expected: int = director.get_expected_beat()
	var ref_status_count: int = status.healthy_count()
	assert_bool(director.is_all_healthy()).is_true()
	assert_bool(director.is_blast_door_open()).is_true()
	assert_bool(director.is_hangar_ready()).is_true()
	assert_int(doors[0]).is_equal(1)
	assert_int(hangars[0]).is_equal(1)

	# Restaurar a 2/4: sin re-emitir señales ni re-abrir el blast door.
	director.restore_snapshot(snap["director"])
	status.restore_snapshot(snap["status"])
	assert_int(director.get_expected_beat()).is_equal(4)
	assert_int(status.healthy_count()).is_equal(2)
	assert_bool(director.is_all_healthy()).is_false()
	assert_bool(director.is_blast_door_open()).is_false()
	assert_int(doors[0]).is_equal(1) # el restore no re-emite blast_door_open

	# Continuar desde el snapshot con los mismos pasos → mismo resultado.
	status.mark_healthy("plasma")
	status.mark_healthy("aire")
	assert_array(director.get_fired_beats()).contains_exactly(ref_fired)
	assert_int(director.get_expected_beat()).is_equal(ref_expected)
	assert_int(status.healthy_count()).is_equal(ref_status_count)
	assert_bool(director.is_all_healthy()).is_true()
	assert_bool(director.is_blast_door_open()).is_true()
	assert_bool(director.is_hangar_ready()).is_true()
	assert_int(doors[0]).is_equal(2)   # la 2ª corrida sí vuelve a disparar el beat
	assert_int(hangars[0]).is_equal(2)


# --- 5. Beat 6: descenso determinista + snapshot de posición ---

func test_beat_6_descent_snapshot_restore_preserves_position() -> void:
	var source = _spawn_platform()
	yield(get_tree(), "idle_frame")

	source.descend()
	source.set_physics_process(false)
	for _i in range(20):
		source.step(0.05)
	assert_int(source.state).is_equal(source.State.DESCENDING)

	var snap: Dictionary = source.get_snapshot()

	var restored = _spawn_platform()
	yield(get_tree(), "idle_frame")
	restored.restore_snapshot(snap)
	restored.set_physics_process(false)
	# El snapshot a mitad del descenso restaura la MISMA posición y velocidad.
	assert_float(restored.global_transform.origin.y).is_equal(source.global_transform.origin.y)
	assert_float(restored.current_velocity_y).is_equal(source.current_velocity_y)

	# El tramo restante, paso a paso, llega exactamente al mismo fondo.
	var guard := 0
	while (source.state == source.State.DESCENDING or restored.state == restored.State.DESCENDING) and guard < 100000:
		source.step(0.05)
		restored.step(0.05)
		guard += 1
	assert_int(guard).is_less(100000)
	assert_int(source.state).is_equal(source.State.BOTTOM)
	assert_int(restored.state).is_equal(restored.State.BOTTOM)
	assert_float(restored.global_transform.origin.y).is_equal(source.global_transform.origin.y)
	assert_float(restored.global_transform.origin.y).is_equal(restored.bottom_height)


# --- 6. Beats 7/8: hangar declarado + salida por la esclusa ---

func test_beats_7_and_8_hangar_scene_and_airlock_exit() -> void:
	var director = _make_bare_director()
	var targets: Array = []
	director.connect("airlock_exit", self, "_record_target", [targets])

	# Beat 7: la config declara el hangar (destino del descenso) y su spawn.
	assert_str(director.get_hangar_scene()).ends_with("Dome_Intro_Hangar.tscn")
	assert_str(director.get_hangar_spawn_id()).is_equal("from_dome_intro_platform")
	assert_bool(ResourceLoader.exists(director.get_hangar_scene())).is_true()

	# Beat 8: la salida por la esclusa apunta al exterior (ScaffoldOrbit). auto_load está
	# desactivado, así que sólo se verifica el contrato de la señal.
	assert_str(director.get_airlock_scene()).ends_with("ScaffoldOrbit.tscn")
	director.request_airlock_exit()
	assert_array(targets).contains_exactly(["res://core_v2/components/ScaffoldOrbit.tscn"])


# --- RECOLECTORES DE SEÑAL / HELPERS ---

func _record_event(event, _action, beat, sink: Array) -> void:
	sink.append({"event": event, "beat": beat})


func _events_in_order(sink: Array) -> Array:
	var out: Array = []
	for entry in sink:
		out.append(String(entry["event"]))
	return out


func _beats_in_order(sink: Array) -> Array:
	var out: Array = []
	for entry in sink:
		out.append(int(entry["beat"]))
	return out


func _record_target(target: String, sink: Array) -> void:
	sink.append(target)


func _bump_noargs(sink: Array) -> void:
	sink[0] += 1
