extends GdUnitTestSuite

# FD-289 §7.8 (T6/T7) — cableado de las 4 redes al domo real.
# Cubre: (a) estructura de la escena DomeMachineLevel (los props de cada red), y (b) el
# cableado red->HEALTHY de DomeNetworkWiring contra DomeNetworkStatus/DomeSystemDirector.
# No corre la suite completa (AGENTS.md §6.1).

const MachineLevelScene := preload("res://core_v2/systems/dome/DomeMachineLevel.tscn")
const WiringScript = preload("res://core_v2/systems/dome/DomeNetworkWiring.gd")
const DirectorScript = preload("res://core_v2/systems/dome/DomeSystemDirector.gd")
const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const LeakPatchPointScript = preload("res://core_v2/systems/cryo/LeakPatchPoint.gd")
const CoolantTankScript = preload("res://core_v2/props/pipe/CoolantTank.gd")
const PipeValveScript = preload("res://core_v2/props/pipe/PipeValve.gd")
const PlasmaConduitScript = preload("res://core_v2/systems/plasma/PlasmaConduit.gd")
const PlasmaRouteScript = preload("res://core_v2/systems/plasma/PlasmaRoute.gd")
const AuxPowerBusScript = preload("res://core_v2/systems/auxpower/AuxPowerBus.gd")
const PressureSectionScript = preload("res://core_v2/systems/atmosphere/PressureSection.gd")
const PressurePumpScript = preload("res://core_v2/props/controls/PressurePump.gd")
const PurgeDialScript = preload("res://core_v2/systems/atmosphere/PurgeDial.gd")
const PurgeTunerScript = preload("res://core_v2/props/controls/PurgeTuner.gd")
const BlastDoorScript = preload("res://core_v2/props/doors/BlastDoorController.gd")
const NetworkStatusScript = preload("res://core_v2/systems/dome/DomeNetworkStatus.gd")

const CONFIG_PATH := "res://core_v2/systems/dome/DomeEnvConfig_intro.tres"


# --- Estructura de la escena (sin entrar al árbol: no toca el director autoload) ---

func _flatten(node: Node, out: Array) -> Array:
	out.append(node)
	for child in node.get_children():
		_flatten(child, out)
	return out


func _count_script(root: Node, script: Script) -> int:
	var n := 0
	for node in _flatten(root, []):
		if node.get_script() == script:
			n += 1
	return n


func test_machine_level_declares_every_network() -> void:
	var level: Node = MachineLevelScene.instance()
	assert_object(level).is_not_null()

	# Registro/estado del domo + cableado.
	assert_int(_count_script(level, NetworkStatusScript)).is_equal(1)
	assert_int(_count_script(level, WiringScript)).is_equal(1)

	# Criocoolant: 1 tanque, 2 fugas, 3 parches, 1 válvula aguas arriba.
	assert_int(_count_script(level, CoolantTankScript)).is_equal(1)
	assert_int(_count_script(level, CoolantLeakScript)).is_equal(2)
	assert_int(_count_script(level, LeakPatchPointScript)).is_equal(3)

	# Plasma: 1 fisura (PlasmaConduit) + 3 válvulas de redirección (PlasmaRoute).
	assert_int(_count_script(level, PlasmaConduitScript)).is_equal(1)
	assert_int(_count_script(level, PlasmaRouteScript)).is_equal(1)
	var plasma_valves := 0
	for node in _flatten(level.get_node("Plasma"), []):
		if node.get_script() == PipeValveScript:
			plasma_valves += 1
	assert_int(plasma_valves).is_equal(3)

	# Energía: bus + bomba? no: bus + fusible + interruptores; Aire: sección + bomba + purga.
	assert_int(_count_script(level, AuxPowerBusScript)).is_equal(1)
	assert_int(_count_script(level, PressureSectionScript)).is_equal(1)
	assert_int(_count_script(level, PressurePumpScript)).is_equal(1)
	assert_int(_count_script(level, PurgeDialScript)).is_equal(1)
	assert_int(_count_script(level, PurgeTunerScript)).is_equal(1)

	# La compuerta de piso (T3) está y su semáforo se relaya desde el cableado.
	assert_int(_count_script(level, BlastDoorScript)).is_equal(1)

	# El cableado declara las 4 redes.
	var wiring: Node = level.get_node("DomeNetworkWiring")
	assert_int(wiring.coolant_leak_paths.size()).is_equal(2)
	assert_str(String(wiring.plasma_route_path)).is_equal("../Plasma/PlasmaRoute")
	assert_str(String(wiring.aux_power_bus_path)).is_equal("../Energy/AuxPowerBus")
	assert_str(String(wiring.pressure_section_path)).is_equal("../Air/AirPressureSection")
	assert_str(String(wiring.blast_door_path)).is_equal("../Doors/BlastDoor")

	level.free()


# --- Cableado (rig con director local; no usa el autoload) ---

func _make_rig() -> Dictionary:
	var host: Spatial = auto_free(Spatial.new())
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
	}


func _level(rig: Dictionary) -> Node:
	return rig["level"]


func test_coolant_network_marks_healthy_when_all_leaks_are_patched() -> void:
	var rig := _make_rig()
	var director = rig["director"]
	var status = rig["status"]
	var level: Node = rig["level"]

	var healthy := []
	status.connect("network_healthy", self, "_record_id", [healthy])

	# Beat 1: el primer intento de energía revela la fuga (arma la red de coolant).
	director.request_first_power_attempt()
	yield(get_tree(), "idle_frame")
	assert_int(_count_script(level.get_node("Coolant"), CoolantLeakScript)).is_equal(2)

	# Cerrar la válvula aguas arriba despresuriza el tramo -> el parche aplica firme.
	var valve = level.get_node("Coolant/CoolantValve")
	valve.set_active(false, true)
	level.get_node("Coolant/LeakA_Patch").patch_with_gloo()
	assert_bool(status.is_healthy("criocoolant")).is_false() # falta la segunda

	level.get_node("Coolant/LeakB_Patch").patch_with_gloo()
	assert_bool(status.is_healthy("criocoolant")).is_true()
	assert_array(healthy).contains(["criocoolant"])
	# El director avanzó el beat 2 con el alias coolant_healthy.
	assert_bool(director.is_beat_fired(2)).is_true()


func test_plasma_network_marks_healthy_when_route_solves() -> void:
	var rig := _make_rig()
	var status = rig["status"]
	var level: Node = rig["level"]
	yield(get_tree(), "idle_frame") # PlasmaRoute._bind_valves es deferred

	# Patrón requerido [1,0,1]; las 3 válvulas arrancan abiertas -> cerrar la del medio.
	assert_bool(status.is_healthy("plasma")).is_false()
	level.get_node("Plasma/PlasmaValveB").set_active(false, true)
	assert_bool(status.is_healthy("plasma")).is_true()


func test_energy_network_marks_healthy_when_bus_is_powered() -> void:
	var rig := _make_rig()
	var status = rig["status"]
	var level: Node = rig["level"]

	assert_bool(status.is_healthy("energia")).is_false()
	var bus = level.get_node("Energy/AuxPowerBus")
	bus.restore_duration = 0.0
	bus.request_restore()
	assert_bool(status.is_healthy("energia")).is_true()


func test_air_network_marks_healthy_when_purged() -> void:
	var rig := _make_rig()
	var status = rig["status"]
	var level: Node = rig["level"]

	assert_bool(status.is_healthy("aire")).is_false()
	var dial = level.get_node("Air/AirPurgeDial")
	dial.value = dial.target # en zona verde
	dial._physics_process(dial.hold_duration + 0.1) # bloquea y purga
	assert_bool(status.is_healthy("aire")).is_true()


func test_four_networks_fire_blast_door_opens_and_beats() -> void:
	var rig := _make_rig()
	var director = rig["director"]
	var status = rig["status"]
	var level: Node = rig["level"]
	yield(get_tree(), "idle_frame")

	var door = level.get_node("Doors/BlastDoor")
	# El controlador local en tests se conecta manualmente (en el juego lo hace solo contra el autoload).
	director.connect("blast_door_open", door, "on_blast_door_open")

	# Coolant (beat 1 + parches) -> beat 2
	director.request_first_power_attempt()
	level.get_node("Coolant/CoolantValve").set_active(false, true)
	level.get_node("Coolant/LeakA_Patch").patch_with_gloo()
	level.get_node("Coolant/LeakB_Patch").patch_with_gloo()
	# Energía (beat 3; arma la ruta de plasma vía timeline) -> beat 3
	var bus = level.get_node("Energy/AuxPowerBus")
	bus.restore_duration = 0.0
	bus.request_restore()
	# Plasma (beat 4): resolver la ruta -> beat 4
	level.get_node("Plasma/PlasmaValveB").set_active(false, true)
	# Aire (beat 5)
	var dial = level.get_node("Air/AirPurgeDial")
	dial.value = dial.target
	dial._physics_process(dial.hold_duration + 0.1)

	assert_int(status.healthy_count()).is_equal(4)
	assert_bool(status.is_all_healthy()).is_true()
	assert_array(director.get_fired_beats()).contains_exactly([1, 2, 3, 4, 5])
	assert_bool(director.is_blast_door_open()).is_true()
	assert_bool(director.is_hangar_ready()).is_true()
	# La compuerta abrió y el semáforo de borde llegó a 4.
	assert_bool(door.is_open()).is_true()
	assert_int(door.get_network_healthy_count()).is_equal(4)


# --- Semáforo aislado (sin director) ---

func test_relay_semaphore_updates_blast_door_count() -> void:
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	var status = auto_free(NetworkStatusScript.new())
	status.total_networks = 4
	host.add_child(status)
	var door = auto_free(BlastDoorScript.new())
	host.add_child(door)
	var wiring = auto_free(WiringScript.new())
	wiring.network_status_path = status.get_path()
	wiring.director_path = NodePath("") # sin director
	wiring.blast_door_path = door.get_path()
	host.add_child(wiring)

	status.mark_healthy("criocoolant")
	status.mark_healthy("energia")
	assert_int(door.get_network_healthy_count()).is_equal(2)


# --- Snapshot ---

func test_snapshot_restores_armed_flags() -> void:
	var wiring = auto_free(WiringScript.new())
	add_child(wiring)
	wiring.restore_snapshot({"coolant_armed": true, "air_armed": true})
	var snap: Dictionary = wiring.get_snapshot()
	assert_bool(snap["coolant_armed"]).is_true()
	assert_bool(snap["plasma_armed"]).is_false()
	assert_bool(snap["air_armed"]).is_true()


func _record_id(network_id, sink: Array) -> void:
	sink.append(network_id)
