extends GdUnitTestSuite

# test_remote_control_touch_multitool.gd - El control remoto del telefono (RemoteControlHome,
# FD-294/296) monta el mismo MobileUI que el juego (via el autoload MobileUIManager) y reenvia al
# host las acciones que sintetizan sus botones. tool_fire_primary lo aprieta tambien el puntero
# fantasma que el servidor grafico emula de cada toque, asi que el telefono lo suprimia entero: la
# misma regresion que #384 arreglo para el juego local por InputProviderV2, pero RemoteControlHome
# tenia su propia supresion from_touch y el FireButton de la UI tactil quedaba muerto. Un boton
# explicito marca su accion en MobileUIManager (note_touch_action) y RemoteControlHome la deja
# pasar solo entonces. El cambio de modo no lo aprieta el fantasma: viaja directo.

var RemoteControlHomeScene = load("res://core_v2/ui/RemoteControlHome.tscn")
const TouchActionButtonScript = preload("res://core_v2/ui/TouchActionButton.gd")

class DummyClient extends Node:
	var inputs: Array = []

	func send_input(input_type: String, payload: Dictionary) -> void:
		inputs.append({"type": input_type, "payload": payload})

	func get_resume_time_left() -> float:
		return 0.0

	func ms_since_last_rx() -> int:
		return 0

class DummyManager extends Node:
	var client: Node = null

var _homes := []

func before_test() -> void:
	_reset_state()

func after_test() -> void:
	_reset_state()
	for home in _homes:
		if is_instance_valid(home):
			home.free()
	_homes.clear()

func _reset_state() -> void:
	for action in ["tool_fire_primary", "tool_fire_secondary", "tool_next_mode", "tool_prev_mode"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	Input.flush_buffered_events()
	MobileUIManager._touch_pointer_until = 0
	MobileUIManager._explicit_touch_actions.clear()
	MobileUIManager._touch_trackers.clear()
	MobileUIManager._is_touch_active = false

func _home(client: Node) -> Control:
	var mgr = auto_free(DummyManager.new())
	mgr.client = client
	add_child(mgr)
	var home = RemoteControlHomeScene.instance()
	add_child(home)
	_homes.append(home)
	home._remote_control_manager = mgr
	home._sent_action_strength.clear()
	return home

func _button(action: String) -> TouchActionButton:
	var btn := TouchActionButtonScript.new()
	btn.action_name = action
	add_child(btn) # el boton resuelve /root/MobileUIManager por el arbol
	auto_free(btn)
	return btn

# Ultimo evento "act" reenviado al host para la accion dada ({} si no viajo ninguno).
func _last_event(client: Node, action: String) -> Dictionary:
	var found: Dictionary = {}
	for msg in client.inputs:
		if msg["type"] != "event":
			continue
		var payload: Dictionary = msg["payload"]
		if String(payload.get("a", "")) == action:
			found = payload
	return found

# El FireButton del MobileUI sintetiza tool_fire_primary MIENTRAS el dedo abre la ventana del
# fantasma; con la marca explicita el telefono lo reenvia igual que hace InputProviderV2 local.
func test_explicit_fire_button_reaches_the_host_during_touch() -> void:
	var client = auto_free(DummyClient.new())
	add_child(client)
	var home := _home(client)
	MobileUIManager._touch_pointer_until = OS.get_ticks_msec() + 10000 # dedo apoyado

	var fire := _button("tool_fire_primary")
	fire._press()
	assert_bool(MobileUIManager.is_touch_action_explicit("tool_fire_primary")).is_true()
	home._send_touch_actions(client)
	var down := _last_event(client, "tool_fire_primary")
	assert_bool(down.get("p", false)).is_true()
	assert_float(float(down.get("s", 0.0))).is_equal(1.0)

	# Soltado: viaja el release para que el host no quede disparando.
	fire._release()
	home._send_touch_actions(client)
	assert_bool(_last_event(client, "tool_fire_primary").get("p", true)).is_false()

# Sin boton explicito, el fantasma del touch sigue suprimido: la regresion de #384 no se reabre.
func test_phantom_fire_without_explicit_button_stays_suppressed() -> void:
	var client = auto_free(DummyClient.new())
	add_child(client)
	var home := _home(client)
	MobileUIManager._touch_pointer_until = OS.get_ticks_msec() + 10000

	Input.action_press("tool_fire_primary") # click fantasma sobre el joystick/area de juego
	home._send_touch_actions(client)
	assert_bool(_last_event(client, "tool_fire_primary").empty()).is_true()
	assert_bool(home._sent_action_strength.has("tool_fire_primary")).is_false()

# Los botones de modo (< TOOL / TOOL >) no los aprieta el fantasma: viajan directo.
func test_tool_mode_buttons_reach_the_host() -> void:
	var client = auto_free(DummyClient.new())
	add_child(client)
	var home := _home(client)

	var next_btn := _button("tool_next_mode")
	next_btn._press()
	home._send_touch_actions(client)
	assert_bool(_last_event(client, "tool_next_mode").get("p", false)).is_true()
	next_btn._release()
	home._send_touch_actions(client)
	assert_bool(_last_event(client, "tool_next_mode").get("p", true)).is_false()

	var prev_btn := _button("tool_prev_mode")
	prev_btn._press()
	home._send_touch_actions(client)
	assert_bool(_last_event(client, "tool_prev_mode").get("p", false)).is_true()
	prev_btn._release()
	home._send_touch_actions(client)
	assert_bool(_last_event(client, "tool_prev_mode").get("p", true)).is_false()
