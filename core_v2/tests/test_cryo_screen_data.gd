extends GdUnitTestSuite

# test_cryo_screen_data.gd - El estado del sistema Criogenia viaja como DATOS del host al
# control remoto (FD-296 F4): collect_state en el host, apply_state en el control, y el
# snapshot del terminal embebiendolo. Nada de raster.

const RoomDialsPanelScript = preload("res://core_v2/things/RoomDialsPanel.gd")
const CoolantSchematicPanelScript = preload("res://core_v2/things/CoolantSchematicPanel.gd")
const CoolantSystemStatusUIScene = preload("res://core_v2/things/CoolantSystemStatusUI.tscn")
const CryoDiagnosticsUIScript = preload("res://core_v2/things/CryoDiagnosticsUI.gd")
const HoloTerminalHUDableScript = preload("res://core_v2/components/HoloTerminalHUDable.gd")
const Room3DScript = preload("res://core_v2/systems/room/Room3D.gd")
const HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")


func _is_json_safe(value) -> bool:
	var t = typeof(value)
	if t in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING]:
		return true
	elif t == TYPE_ARRAY:
		for item in value:
			if not _is_json_safe(item):
				return false
		return true
	elif t == TYPE_DICTIONARY:
		for key in value.keys():
			if typeof(key) != TYPE_STRING:
				return false
			if not _is_json_safe(value[key]):
				return false
		return true
	return false


func test_room_dials_collect_from_room_is_json_safe() -> void:
	var room = auto_free(Room3DScript.new())
	room.name = "TestRoom3D"
	add_child(room)
	room.set_temperature(-12.0)
	room.set_pressure(1.4)
	room.set_contamination(0.25)

	var panel = auto_free(RoomDialsPanelScript.new())
	panel.room_path = room.get_path()
	add_child(panel)

	var state: Dictionary = panel.collect_state()
	assert_bool(state.empty()).is_false()
	assert_bool(_is_json_safe(state)).is_true()
	assert_float(float(state.get("temperature", 0.0))).is_equal(-12.0)
	assert_float(float(state.get("pressure", 0.0))).is_equal(1.4)
	assert_float(float(state.get("contamination", 0.0))).is_equal(0.25)
	var flags: Dictionary = state.get("flags", {}) if typeof(state.get("flags", {})) == TYPE_DICTIONARY else {}
	# -12°C con freezing_point 0.0 es congelamiento (y no frio letal -25).
	assert_bool(bool(flags.get("freezing", false))).is_true()
	assert_bool(bool(flags.get("lethal_cold", true))).is_false()


func test_room_dials_apply_state_draws_from_data_without_room() -> void:
	var panel = auto_free(RoomDialsPanelScript.new())
	add_child(panel)
	assert_bool(panel._has_room_or_data()).is_false()

	# El control remoto no tiene Room3D: los datos recibidos son la unica fuente.
	panel.apply_state({
		"temperature": -12.0,
		"pressure": 1.4,
		"contamination": 0.25,
		"lethal_cold": -25.0,
		"freezing_point": 0.0,
		"overpressure": 2.4,
		"hazard_threshold": 0.7,
		"flags": {"freezing": true, "lethal_cold": false, "hazard": false, "fog": false, "overpressure": false}
	})

	assert_bool(panel._has_room_or_data()).is_true()
	assert_float(panel._room_value("temperature", 20.0)).is_equal(-12.0)
	assert_bool(panel._room_check("is_freezing", "freezing", false)).is_true()
	# Dibujar de datos no rompe (este panel no tiene room_path resuelto aca).
	panel.notification(CanvasItem.NOTIFICATION_DRAW)


class FakeValve extends Node:
	var is_active: bool = true


func test_schematic_collect_state_reflects_valves_and_is_json_safe() -> void:
	var valve_west = auto_free(FakeValve.new())
	valve_west.name = "ValveWestFloor1"
	valve_west.is_active = false # cerrada
	valve_west.add_to_group("coolant_valve")
	add_child(valve_west)

	var valve_east = auto_free(FakeValve.new())
	valve_east.name = "ValveEastFloor1"
	valve_east.is_active = true
	valve_east.add_to_group("coolant_valve")
	add_child(valve_east)

	var panel = auto_free(CoolantSchematicPanelScript.new())
	add_child(panel)

	var state: Dictionary = panel.collect_state()
	assert_bool(state.empty()).is_false()
	assert_bool(_is_json_safe(state)).is_true()
	assert_bool(bool(state.get("is_live", false))).is_true()
	var west_open: Array = state.get("west_open", [])
	assert_array(west_open).has_size(1)
	# ValveWestFloor1 es la primera de la columna oeste y esta cerrada.
	assert_bool(bool(west_open[0])).is_false()
	assert_bool(bool((state.get("east_open", []) as Array)[0])).is_true()
	# Sin fugas en escena, todos los tramos sanos.
	assert_int(int((state.get("west_states", []) as Array)[0])).is_equal(0)


func test_schematic_apply_state_draws_from_data_without_world() -> void:
	var panel = auto_free(CoolantSchematicPanelScript.new())
	add_child(panel)

	# Sin grupos en escena el modelo es el offline; con datos del host es el de ahi.
	assert_bool(bool(panel._gather_model().get("is_live", true))).is_false()

	panel.apply_state({
		"is_live": true,
		"west_open": [true, true, true, true, true, true],
		"east_open": [true, true, true, true, true, true],
		"has_interlink": false,
		"interlink_open": true,
		"west_states": [2, 0, 0, 0, 0], # LEAKING en el tronco oeste
		"east_states": [0, 0, 0, 0, 0],
		"west_rings": [0, 1, 0, 0, 0, 0], # WARNING en el anillo del piso 1
		"east_rings": [0, 0, 0, 0, 0, 0],
		"interlink_state": 0,
		"tank_west": 0.4,
		"tank_east": 1.0,
		"tanks": [],
		"planta_leaks": [{"pos": [10.0, -6.0], "ring": 1, "state": 2}],
		"hub_west": [10.0, -6.0],
		"hub_east": []
	})

	var model: Dictionary = panel._gather_model()
	assert_bool(bool(model.get("is_live", false))).is_true()
	assert_int(int((model.get("west_states", []) as Array)[0])).is_equal(2)
	# El caudal se resuelve de datos: tanque al 40% y fuga LEAKING secan el tronco oeste.
	var flows: Dictionary = panel._flows_for(model)
	assert_float(float((flows["west"]["trunk"] as Array)[0])).is_equal(0.0)
	# Y el dibujo desde datos no rompe.
	panel.notification(CanvasItem.NOTIFICATION_DRAW)


func test_tanks_collect_apply_roundtrip() -> void:
	var ui = auto_free(CoolantSystemStatusUIScene.instance())
	add_child(ui)
	# Sin tanques en escena no hay datos que colectar.
	assert_bool(ui.collect_state().empty()).is_true()

	# El remoto recibe niveles y reconstruye sus filas desde datos.
	ui.apply_state({"tanks": [{"east": false, "level": 0.43}, {"east": true, "level": 0.9}]})
	assert_int(ui._gauge_order.size()).is_equal(2)
	assert_float(float((ui._gauge_order[0] as Control).level)).is_equal(0.43)
	assert_float(float((ui._gauge_order[1] as Control).level)).is_equal(0.9)

	# Un segundo apply con la misma cantidad no reconstruye: solo actualiza niveles.
	ui.apply_state({"tanks": [{"east": false, "level": 0.2}, {"east": true, "level": 0.9}]})
	assert_int(ui._gauge_order.size()).is_equal(2)
	assert_float(float((ui._gauge_order[0] as Control).level)).is_equal(0.2)


func test_cryo_ui_collects_from_panels_and_updates_them() -> void:
	var ui = auto_free(CryoDiagnosticsUIScript.new())
	ui.name = "CryoDiagnosticsUI"
	var dials = auto_free(RoomDialsPanelScript.new())
	dials.name = "RoomDialsPanel"
	var schematic = auto_free(CoolantSchematicPanelScript.new())
	schematic.name = "CoolantSchematicPanel"
	var tanks = auto_free(CoolantSystemStatusUIScene.instance())
	tanks.name = "CoolantSystemStatusUI"
	ui.add_child(dials)
	ui.add_child(schematic)
	ui.add_child(tanks)
	add_child(ui)

	# Sin mundo no hay nada que colectar: el snapshot no lleva clave vacia.
	assert_bool(ui.collect_state().empty()).is_true()

	# El snapshot del host llega por update_snapshot y se reparte a los paneles.
	ui.update_snapshot({"proto": 1, "cryo": {
		"room": {"temperature": -12.0, "pressure": 1.4, "contamination": 0.25},
		"schematic": {"is_live": true},
		"tanks": {"tanks": [{"east": false, "level": 0.43}]}
	}})
	assert_float(dials._room_value("temperature", 20.0)).is_equal(-12.0)
	assert_bool(bool((schematic._remote_state as Dictionary).get("is_live", false))).is_true()
	assert_int(tanks._gauge_order.size()).is_equal(1)

	# Los eventos discretos del circuito (parche, valvula, tanque) llegan al bus raiz.
	var circuit_hits: Array = []
	ui.connect("circuit_state_changed", self, "_count_circuit_change", [circuit_hits])
	ui._on_circuit_state_changed()
	assert_int(circuit_hits.size()).is_equal(1)


func _count_circuit_change(circuit_hits: Array, _arg = null) -> void:
	circuit_hits.append(1)


class LeakHost extends Spatial:
	var _leak: Node = null

	func is_patched() -> bool:
		return false

	func is_firmly_patched() -> bool:
		return false


class FakeLeak extends Node:
	func get_state() -> int:
		return 2 # CoolantLeak.State.LEAKING


func test_schematic_collects_ring_leak_state() -> void:
	var leak = auto_free(FakeLeak.new())
	leak.name = "Leak"
	var patch = auto_free(LeakHost.new())
	patch.name = "PatchPointWestRing1"
	patch.set("_leak", leak)
	patch.add_to_group("gloo_patchable")
	patch.add_user_signal("patch_applied", [])
	patch.add_user_signal("patch_expired", [])
	# Posicion de mundo para el marcador de planta: el panel pide global_position a un Spatial.
	patch.translation = Vector3(10.0, 0.0, -6.0)
	add_child(patch)
	add_child(leak)

	var panel = auto_free(CoolantSchematicPanelScript.new())
	add_child(panel)

	var state: Dictionary = panel.collect_state()
	var leaks: Array = state.get("planta_leaks", [])
	assert_int(leaks.size()).is_equal(1)
	assert_int(int((leaks[0] as Dictionary).get("state", -1))).is_equal(2)
	assert_int(int((leaks[0] as Dictionary).get("ring", -1))).is_equal(1)


func test_hudable_snapshot_embeds_cryo_from_terminal_viewport() -> void:
	var terminal: HoloTerminalV2 = auto_free(HoloTerminalV2.new())
	terminal.name = "TestTerminal"
	terminal.filename = "res://core_v2/tests/fixtures/test_terminal.tscn"

	var hudable = auto_free(HoloTerminalHUDableScript.new())
	hudable.name = "HoloTerminalHUDable"
	hudable.hud_screen_title = "Criogenia"
	terminal.add_child(hudable)

	var viewport := Viewport.new()
	viewport.name = "Viewport"
	terminal.add_child(viewport)
	var ui = auto_free(CryoDiagnosticsUIScript.new())
	ui.name = "CryoDiagnosticsUI"
	var dials = auto_free(RoomDialsPanelScript.new())
	dials.name = "RoomDialsPanel"
	var room = auto_free(Room3DScript.new())
	room.name = "TestRoom3D"
	add_child(room)
	dials.room_path = room.get_path()
	ui.add_child(dials)
	viewport.add_child(ui)
	add_child(terminal)

	# _connect_cryo_ui se llama diferido en _ready; en el test lo invocamos directo.
	hudable._connect_cryo_ui()

	room.set_temperature(-12.0)
	var snap: Dictionary = hudable.widget_snapshot()
	assert_bool(snap.has("cryo")).is_true()
	var cryo: Dictionary = snap.get("cryo", {}) if typeof(snap.get("cryo", {})) == TYPE_DICTIONARY else {}
	assert_bool(_is_json_safe(cryo)).is_true()
	var room_state: Dictionary = cryo.get("room", {}) if typeof(cryo.get("room", {})) == TYPE_DICTIONARY else {}
	assert_float(float(room_state.get("temperature", 20.0))).is_equal(-12.0)


func test_widget_renders_cryo_summary() -> void:
	var widget: Control = auto_free(HoloTerminalWidgetScene.instance())
	add_child(widget)

	widget.set_snapshot({
		"proto": 1,
		"id": "holoterminal:cryo",
		"title": "Criogenia",
		"active": true,
		"cryo": {
			"room": {"temperature": -12.0, "pressure": 1.4, "contamination": 0.25},
			"schematic": {"west_states": [2, 0, 0, 0, 0], "east_states": [0, 0, 0, 0, 0],
				"west_rings": [0, 0, 0, 0, 0, 0], "east_rings": [0, 0, 0, 0, 0, 0]},
			"tanks": {"tanks": [{"east": false, "level": 0.43}]}
		}
	})

	var status_label: Label = widget.get_node("Margin/VBox/StatusLabel")
	var mode_label: Label = widget.get_node("Margin/VBox/ModeLabel")
	assert_str(status_label.text).contains("TEMP")
	assert_str(status_label.text).contains("-12.0°C")
	assert_str(status_label.text).contains("25%")
	assert_str(mode_label.text).contains("FUGA")
	assert_str(mode_label.text).contains("43%")


func test_widget_without_cryo_keeps_generic_text() -> void:
	var widget: Control = auto_free(HoloTerminalWidgetScene.instance())
	add_child(widget)

	widget.set_snapshot({"proto": 1, "id": "x", "title": "Terminal", "active": false})
	var status_label: Label = widget.get_node("Margin/VBox/StatusLabel")
	assert_str(status_label.text).contains("EN ESPERA")
