extends GdUnitTestSuite

# test_cryopods_hudable.gd - La bahia de criocapsulas como pantalla de OdiseaOS (FD-304 §10).
# Lo que importa: que sea UNA pantalla y no 28, que solo pida atencion cuando algo le pasa a
# alguien, y que lo que viaja sean datos (el mismo widget dibuja en el HUD local y en el control).

const CryoPodsHUDableScript = preload("res://core_v2/things/CryoPodsHUDable.gd")
const CryoPodsWidgetScene = preload("res://core_v2/ui/hud/CryoPodsWidget.tscn")

const DOME_INTRO := "res://core_v2/levels/interiors/Dome_Intro.tscn"


class FakeBus:
	extends Node

	signal systems_changed()

	var state: int = 3 # STATE_DESCONOCIDO

	func get_summary() -> Dictionary:
		return {"criocoolant": {"state": state}}


func before_test() -> void:
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.clear_favorites()


func after_test() -> void:
	SuitOS.clear_favorites()


func _bay(roster: Array = [], count: int = 4) -> Node:
	var bay = auto_free(CryoPodsHUDableScript.new())
	bay.pod_count = count
	bay.pod_roster = roster
	add_child(bay)
	return bay


func test_the_whole_bay_is_one_screen_not_one_per_capsule() -> void:
	var bay = _bay([], 28)
	assert_str(bay.screen_id()).is_equal("ship:cryopods")
	assert_array(SuitOS.get_registered_screens()).contains(["ship:cryopods"])
	assert_int(SuitOS.get_registered_screens().size()).is_equal(1)
	assert_int(bay.widget_snapshot()["pods"].size()).is_equal(28)


func test_the_snapshot_is_json_safe() -> void:
	var bay = _bay(["Pod_01|Elías Vega|NOMINAL"], 4)
	var snap: Dictionary = bay.widget_snapshot()
	assert_str(to_json(parse_json(to_json(snap)))).is_equal(to_json(snap))
	assert_str(String(snap["pods"][0]["occupant"])).is_equal("Elías Vega")
	assert_str(String(snap["pods"][1]["occupant"])).is_empty()


func test_an_empty_capsule_is_never_in_alarm() -> void:
	# No hay nadie adentro a quien le pase algo: una bahia vacia no puede pedir atencion.
	var bus = auto_free(FakeBus.new())
	add_child(bus)
	var bay = _bay([], 4)
	bay.bus_path = bay.get_path_to(bus)
	bus.state = 2 # STATE_FALLO
	var snap: Dictionary = bay.widget_snapshot()
	assert_int(int(snap["alarms"])).is_equal(0)
	assert_float(bay.relevance()).is_equal_approx(bay.default_relevance, 0.001)


func test_relevance_jumps_when_an_occupied_capsule_is_in_alarm() -> void:
	var bay = _bay(["Pod_02|Marisol Quispe|NOMINAL"], 4)
	assert_float(bay.relevance()).is_equal_approx(bay.default_relevance, 0.001)
	assert_bool(bool(bay.widget_snapshot()["alarm"])).is_false()

	# El fallo del criocoolant del bus pone en riesgo a quien este dentro: la bahia sube fuerte.
	var bus = auto_free(FakeBus.new())
	add_child(bus)
	bay.bus_path = bay.get_path_to(bus)
	bus.state = 2
	var snap: Dictionary = bay.widget_snapshot()
	assert_int(int(snap["alarms"])).is_equal(1)
	assert_str(String(snap["pods"][1]["status"])).is_equal("ALERTA")
	assert_float(bay.relevance()).is_greater(0.5)


func test_scan_returns_the_telemetry_of_a_capsule_and_select_walks_the_roster() -> void:
	var bay = _bay(["Pod_01|Elías Vega|NOMINAL", "Pod_03|Ana Ruiz|HIPOTERMIA"], 4)
	var scanned: Dictionary = SuitOS.perform_action("ship:cryopods", "scan", {"pod": "Pod_03"})
	assert_bool(bool(scanned["ok"])).is_true()
	assert_str(String(scanned["pod"]["occupant"])).is_equal("Ana Ruiz")
	assert_bool(bool(scanned["pod"]["alarm"])).is_true()

	# La cruceta recorre el roster por la misma ruta, sin contrato nuevo.
	assert_int(int(bay.widget_snapshot()["focused"])).is_equal(0)
	var moved: Dictionary = SuitOS.perform_action("ship:cryopods", "select", {"delta": 2})
	assert_str(String(moved["pod"])).is_equal("Pod_03")
	assert_int(int(bay.widget_snapshot()["focused"])).is_equal(2)
	# Y no se pasa de los extremos.
	SuitOS.perform_action("ship:cryopods", "select", {"delta": 99})
	assert_int(int(bay.widget_snapshot()["focused"])).is_equal(3)

	# Fuera de lo declarado no hay nada que hacer: F4 valida el op contra allowed_actions.
	assert_bool(bool(SuitOS.perform_action("ship:cryopods", "eject", {}).get("ok", false))).is_false()


func test_a_is_the_primary_action_so_the_chord_can_reach_it() -> void:
	var bay = _bay([], 4)
	var actions: Array = bay.hud_gamepad_actions()
	assert_int(actions.size()).is_equal(1)
	assert_str(String(actions[0]["button"])).is_equal("a")
	assert_str(String(actions[0]["op"])).is_equal("scan")
	assert_bool(bool(actions[0]["confirm"])).is_true()
	assert_array(bay.allowed_actions()).contains(["scan"])


func test_the_widget_draws_from_the_snapshot_alone() -> void:
	var widget = auto_free(CryoPodsWidgetScene.instance())
	add_child(widget)
	var bay = _bay(["Pod_01|Elías Vega|NOMINAL"], 28)
	widget.set_snapshot(bay.widget_snapshot())
	var summary: Label = widget.get_node("Margin/VBox/SummaryLabel")
	assert_str(summary.text).contains("1/28")
	assert_str(widget.get_node("Margin/VBox/PodRow/PodLabel").text).contains("Elías Vega")

	# Sin roster declarado no se afirma ocupacion: se informa cuantas capsulas hay.
	widget.set_snapshot(_bay([], 28).widget_snapshot())
	assert_str(summary.text).contains("28 CÁPSULAS")

	# Offline (la bahia quedo en otro nivel): el mismo widget lo dice y no deja escanear.
	var offline: Dictionary = bay.widget_snapshot()
	offline["source"] = "offline"
	widget.set_snapshot(offline)
	assert_bool(widget.get_node("Margin/VBox/PodRow/ScanButton").disabled).is_true()


func test_the_bay_is_mounted_in_dome_intro() -> void:
	# Verification 10: tiene que aparecer en el registry de SuitOS en Dome_Intro. Se comprueba
	# sobre el .tscn y no instanciando el domo entero, que trae medio nivel con el.
	var file := File.new()
	assert_int(file.open(DOME_INTRO, File.READ)).is_equal(OK)
	var text: String = file.get_as_text()
	file.close()
	assert_str(text).contains("res://core_v2/things/CryoPodsHUDable.gd")
	assert_str(text).contains('[node name="CryoPodsHUDable" type="Node" parent="."]')
