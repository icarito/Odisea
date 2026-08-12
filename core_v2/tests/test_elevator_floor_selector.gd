extends GdUnitTestSuite

# The cabin dial has two ways in that are easy to break independently: the rider
# pressing the key (interact) and the car bringing it up on its own (auto_interact,
# which the player controller drives through set_active, never through interact).

const ElevatorScene = preload("res://core_v2/props/machinery/ElevatorProp.tscn")

var _elevator: Node = null
var _selector: Node = null
var _dial: Control = null


func before_test() -> void:
	_elevator = auto_free(ElevatorScene.instance())
	_elevator.floor_heights = [0.0, 4.6, 9.1, 13.6, 18.1, 22.6]
	add_child(_elevator)
	yield(await_idle_frame(), "completed")
	# Deliberately the prop's own panel, not one bolted on by the test: the cabin
	# control once lived only in Dome_Intro.tscn and a level re-save lost it.
	_selector = _elevator.get_node_or_null("Platform/ElevatorFloorSelector")
	if _selector:
		_dial = _selector.get_node("Viewport/RadialSelector")


func test_the_car_ships_with_a_cabin_panel() -> void:
	assert_object(_selector) \
		.override_failure_message("ElevatorProp.tscn has no Platform/ElevatorFloorSelector") \
		.is_not_null()


func _aim_at_option(index: int) -> void:
	var angle: float = _dial._index_to_screen_angle(index)
	var half: float = min(_dial.rect_size.x, _dial.rect_size.y) / 2.0
	_dial.point_at(_dial.rect_size / 2.0 + Vector2(cos(angle), sin(angle)) * half * 0.65)


# Proveedor de input de mentira: es lo unico que necesita _frame_input() para devolver un
# InputDataV2, y deja al test manejar el flanco de tool_fire_primary a mano.
class _FakeInputProvider:
	var data = null
	func peek_input():
		return data


# Node, no Reference: _frame_input() hace `var body: Node = _zoomed_player`, y asignarle
# algo que no sea Node deja la variable en null sin avisar.
class _FakeBody:
	extends Node
	var input_provider = null


var _fake_body = null


# El click ya NO entra por _input(). Al arreglar la desincronizacion del replay, la
# confirmacion del dial pasa por InputDataV2.tool_fire_primary tanto en vivo como en
# reproduccion, y ElevatorFloorSelector la detecta por FLANCO en _drive_from_stream().
# Pinchar _input() con un InputEventMouseButton probaba un camino que ya no existe: pasaba
# el test y el dial estaba roto en reproduccion. Aca se reproduce el flanco de verdad.
func _left_click() -> void:
	# Se llama a _drive_from_stream() (via _feed) y no a _process(): este ultimo corre
	# despues _track_aim(), que sin camara en el test da la proyeccion por fuera de pantalla
	# y limpiaria el _aim_at_option() de arriba.
	var suelto = InputDataV2.new()
	suelto.tool_fire_primary = false
	_feed(suelto)
	# Misma condicion que aplica _process: la confirmacion se arma recien cuando no queda
	# ninguna tecla apretada, para que un mismo toque no abra y elija a la vez.
	if not _selector._confirm_armed and not _selector._any_confirm_held():
		_selector._confirm_armed = true
	var apretado = InputDataV2.new()
	apretado.tool_fire_primary = true
	_feed(apretado)


func test_the_prop_script_is_actually_attached() -> void:
	# Without this, a parse error in ElevatorFloorSelector.gd leaves a bare
	# StaticBody and every other test here passes on null returns.
	assert_bool(_selector.has_method("is_dial_open")) \
		.override_failure_message("ElevatorFloorSelector.gd failed to compile") \
		.is_true()


func test_stops_are_numbered_from_one() -> void:
	assert_array(_selector._resolve_labels()).is_equal(["1", "2", "3", "4", "5", "6"])


func test_proximity_activation_actually_shows_the_dial() -> void:
	# What PlayerControllerV2 does for an auto_interact prop: it flips set_active
	# directly. Before, that only grew an empty quad and the rider had to press the
	# key a second time to see anything.
	assert_bool(_selector.is_dial_open()).is_false()
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	assert_bool(_selector.is_dial_open()).is_true()
	assert_bool(_dial.visible).is_true()


func test_click_does_nothing_while_the_aim_is_off_the_dial() -> void:
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	_dial.clear_pointer()
	_left_click()
	assert_int(_elevator.target_floor).is_equal(-1)
	assert_bool(_selector.is_dial_open()).is_true()


func test_left_click_requests_the_aimed_floor() -> void:
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	_aim_at_option(3)
	_left_click()
	assert_int(_elevator.target_floor).is_equal(3)


func test_ambient_panel_stays_up_after_a_pick() -> void:
	# auto_interact is on in the scene: the controller re-triggers the moment
	# is_active goes false, so closing on select would only flicker.
	assert_bool(_selector.auto_interact).is_true()
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	_aim_at_option(2)
	_left_click()
	assert_bool(_selector.is_dial_open()).is_true()


func test_manual_panel_closes_after_a_pick() -> void:
	_selector.auto_interact = false
	_selector.interact()
	yield(await_idle_frame(), "completed")
	yield(await_idle_frame(), "completed")
	assert_bool(_selector.is_dial_open()).is_true()
	_aim_at_option(1)
	_left_click()
	assert_bool(_selector.is_dial_open()).is_false()
	assert_int(_elevator.target_floor).is_equal(1)


func _feed(input) -> void:
	# Alimenta un frame de input al selector por el mismo camino que usan el juego y la
	# reproduccion: _frame_input() -> peek_input() -> _drive_from_stream().
	#
	# is_instance_valid y no `== null`: auto_free lo libera al terminar cada test, pero la
	# variable de la suite sobrevive apuntando a un objeto muerto. Comparar contra null daba
	# falso y el test reusaba un cuerpo liberado, asi que _zoomed_player nunca se asignaba y
	# _frame_input() devolvia null en silencio.
	if not is_instance_valid(_fake_body):
		_fake_body = auto_free(_FakeBody.new())
		_fake_body.input_provider = _FakeInputProvider.new()
		_selector._zoomed_player = _fake_body
	_fake_body.input_provider.data = input
	_selector._drive_from_stream()


func _mouse_gesture(delta: Vector2):
	# OJO con el signo: InputProviderV2 entrega mouse_delta con la Y ya invertida, o sea que
	# "arriba en pantalla" es +Y aca. El parametro se pasa en coordenadas de pantalla y se
	# invierte al armar el InputDataV2, para que el test lea como se ve.
	var input = InputDataV2.new()
	input.mouse_delta = Vector2(delta.x, -delta.y)
	return input


func _move_stick(direction: Vector2):
	# Stick de movimiento, real o virtual: analog_move_active es lo que lo separa del
	# teclado, y lo marca InputProviderV2 al leer el frame.
	var input = InputDataV2.new()
	input.move_vec = direction
	input.analog_move_active = true
	return input


func test_vertical_movement_intent_sweeps_to_the_top_floor() -> void:
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	# Arriba en pantalla es -Y y el dial mapea las 12 al piso mas alto.
	var arriba = InputDataV2.new()
	arriba.move_vec = Vector2(0.0, -1.0)
	_feed(arriba)
	assert_int(_dial.get_hovered_index()).is_equal(5)


func test_the_movement_stick_keeps_aiming_after_a_look_gesture() -> void:
	# En joypad el stick DERECHO suma a mouse_delta, o sea que mirar una sola vez no puede
	# dejar muerto al izquierdo. En mobile pasa lo mismo con el arrastre de camara y el
	# joystick virtual. Manda el ultimo gesto, venga de donde venga.
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	_feed(_mouse_gesture(Vector2(0.0, -40.0)))
	assert_int(_dial.get_hovered_index()).is_equal(5)
	_feed(_move_stick(Vector2(0.0, 1.0)))
	assert_int(_dial.get_hovered_index()) \
		.override_failure_message("el stick de movimiento debe seguir apuntando despues de mirar") \
		.is_equal(0)
	_feed(_move_stick(Vector2(0.0, -1.0)))
	assert_int(_dial.get_hovered_index()).is_equal(5)


func test_the_mouse_gesture_angle_picks_the_floor() -> void:
	# El corazon del dial: elige el ANGULO CON EL QUE SE MOVIO EL MOUSE, no el angulo al
	# que quedo mirando la camara. Nada aca toca la camara y sin embargo se elige piso.
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")

	_feed(_mouse_gesture(Vector2(0.0, -40.0)))
	assert_int(_dial.get_hovered_index()) \
		.override_failure_message("empujar el mouse hacia arriba debe elegir el ultimo piso") \
		.is_equal(5)

	_feed(_mouse_gesture(Vector2(0.0, 40.0)))
	assert_int(_dial.get_hovered_index()) \
		.override_failure_message("empujar el mouse hacia abajo debe elegir el primer piso") \
		.is_equal(0)

	# El arco sube por la derecha: las 6 son el piso 1, las 3 el medio y las 12 el ultimo.
	# 45 grados arriba-derecha son 135 grados de recorrido sobre un paso de 180/5 = 36, o
	# sea el indice 4 (piso "5").
	_feed(_mouse_gesture(Vector2(30.0, -30.0)))
	assert_int(_dial.get_hovered_index()).is_equal(4)


func test_a_light_flick_past_the_deadzone_moves_the_selection() -> void:
	# Apenas cruzada la zona muerta el gesto vale entero: no hace falta un manotazo, y la
	# magnitud no escala nada. Si esto empieza a fallar, el dial se volvio pegajoso.
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	_feed(_mouse_gesture(Vector2(0.0, 40.0)))
	assert_int(_dial.get_hovered_index()).is_equal(0)
	_feed(_mouse_gesture(Vector2(0.0, -_selector.mouse_gesture_deadzone)))
	assert_int(_dial.get_hovered_index()) \
		.override_failure_message("un toque justo sobre la zona muerta debe mover la seleccion") \
		.is_equal(5)


func test_mouse_jitter_under_the_deadzone_does_not_move_the_dial() -> void:
	# El motivo de la zona muerta: a un pixel de recorrido la DIRECCION es ruido. Sin esto
	# la mano apoyada mandaba el angulo a cualquier lado y el dial saltaba solo.
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	_feed(_mouse_gesture(Vector2(30.0, -30.0)))
	assert_int(_dial.get_hovered_index()).is_equal(4)
	var temblor: float = _selector.mouse_gesture_deadzone * 0.4
	for muestra in [Vector2(0.0, temblor), Vector2(-temblor, 0.0), Vector2(temblor, temblor)]:
		_feed(_mouse_gesture(muestra))
		assert_int(_dial.get_hovered_index()) \
			.override_failure_message("el temblor bajo la zona muerta no debe mover el dial") \
			.is_equal(4)


func test_a_still_mouse_holds_the_selection() -> void:
	# El otro lado del umbral: sin gesto no hay cambio. Un frame de mouse quieto no puede
	# tirar la seleccion ni hacerla temblar.
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	_feed(_mouse_gesture(Vector2(30.0, -30.0)))
	assert_int(_dial.get_hovered_index()).is_equal(4)
	_feed(InputDataV2.new())
	assert_int(_dial.get_hovered_index()).is_equal(4)


func test_walking_does_not_move_the_dial_once_the_mouse_has_spoken() -> void:
	# En escritorio el jugador camina con WASD mientras elige. Ese move_vec no puede pisar
	# el gesto de mirada, o el piso elegido cambia solo por acomodarse en la cabina.
	_selector.set_active(true)
	yield(await_idle_frame(), "completed")
	_feed(_mouse_gesture(Vector2(0.0, -40.0)))
	assert_int(_dial.get_hovered_index()).is_equal(5)
	var caminando = InputDataV2.new()
	caminando.move_vec = Vector2(0.0, 1.0)
	_feed(caminando)
	assert_int(_dial.get_hovered_index()) \
		.override_failure_message("caminar no debe reelegir el piso") \
		.is_equal(5)


# --- Cabin zoom ---

func _make_stand_in_player() -> KinematicBody:
	# A 5.5 m spring arm inside a 3.6 m car frames the cabin from out in the
	# shaft. Riding has to pull the camera in — anywhere in the car, for the whole
	# trip — and give the rider's own distance back when they step out.
	var player := KinematicBody.new()
	player.set_script(load("res://core_v2/tests/helpers/StandInPlayer.gd"))
	player.collision_layer = 2
	player.collision_mask = 0
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.3, 0.9, 0.3)
	shape.shape = box
	player.add_child(shape)
	return player


func test_riding_the_car_pulls_the_camera_in() -> void:
	var player := _make_stand_in_player()
	_elevator.add_child(player)
	player.global_transform.origin = _elevator.get_node("Platform").global_transform.origin + Vector3(1.2, 1.0, 1.2)
	for _i in range(6):
		yield(await_idle_frame(), "completed")
	assert_float(player.base_spring_length_3d) \
		.override_failure_message("boarding should shorten the spring arm") \
		.is_equal(_selector.cabin_zoom_spring_length)


func test_stepping_out_hands_the_distance_back() -> void:
	var player := _make_stand_in_player()
	_elevator.add_child(player)
	player.global_transform.origin = _elevator.get_node("Platform").global_transform.origin + Vector3(1.2, 1.0, 1.2)
	for _i in range(6):
		yield(await_idle_frame(), "completed")
	assert_float(player.base_spring_length_3d).is_equal(_selector.cabin_zoom_spring_length)

	player.global_transform.origin += Vector3(0, 0, 40)
	for _i in range(6):
		yield(await_idle_frame(), "completed")
	assert_float(player.base_spring_length_3d) \
		.override_failure_message("leaving should restore the rider's own distance") \
		.is_equal(5.5)
