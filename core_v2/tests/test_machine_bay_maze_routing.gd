extends GdUnitTestSuite

# MachineBayMazeRouting — ruteo NO LINEAL del laberinto (FD-322).
#
# Cubre:
#  - topología: enlaces/compuertas presentes y su estado inicial determinista.
#  - progreso de máquinas abre las compuertas gated (palancas de estación).
#  - >1 ruta abierta simultánea tras el progreso (el nivel deja de ser lineal).
#  - pureza: el estado de la compuerta es función del estado de la máquina (sin
#    estado acumulado oculto): abrir/cerrar/abrir converge al mismo resultado.
#  - celda de enlace forzada en el streamer (borde oeste + espejo) a altura 0.
#  - las compuertas no invaden el corredor central / aproximación de Estación 1.
#
# La ruta crítica de FD-320 (corredor) se cubre en `test_machine_bay_route.gd`; acá
# solo se prueba que el ruteo agrega caminos sin tocar ese corredor.
#
# El nivel se instancia UNA sola vez para toda la suite: cada `MachineBay` levanta
# el worker threaded del streamer, y crear/varios por test crashéa el runner. Entre
# tests se resetea el estado de las palancas.

const BayScene := preload("res://core_v2/levels/machines/MachineBay.tscn")

var _bay: Node = null

func before() -> void:
	_bay = BayScene.instance()
	add_child(_bay)

func after() -> void:
	if is_instance_valid(_bay):
		_bay.queue_free()
	_bay = null

func _routing() -> Node:
	return _bay.get_node_or_null("MachineBayMazeRouting")

func _level() -> Node:
	return _bay.get_node_or_null("Level")

# Avanza N ticks de física. La señal `physics_frame` se emite ANTES de los
# `_physics_process` de los nodos, así que hay que ceder más de una vez para que el
# director reevalúe las compuertas.
func _advance(ticks: int = 3) -> void:
	for _i in range(ticks):
		yield(get_tree(), "physics_frame")
		yield(get_tree(), "idle_frame")

func _set_lever(item_name: String, active: bool) -> void:
	var item = _level().get_item(item_name)
	if is_instance_valid(item):
		item.set("is_active", active)

func _reset_levers() -> void:
	var routing = _routing()
	if is_instance_valid(routing):
		routing.gate_on_machine_progress = false
	_set_lever("SeesawLever", false)
	_set_lever("PendulumLever", false)
	yield(_advance(2), "completed")

# ── 1. Topología y estado inicial abierto (Transit-Run: sin bloqueo obligatorio) ─

func test_junctions_present_with_expected_initial_state() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	assert_object(routing).is_not_null()
	assert_int(routing.get_junction_ids().size()).is_equal(3)
	# Transit-Run: por defecto todas las compuertas están abiertas sin puzles previos.
	assert_bool(routing.is_junction_open("maze_entry")).is_true()
	assert_bool(routing.is_junction_open("maze_exit")).is_true()
	assert_bool(routing.is_junction_open("field_link")).is_true()

func test_initial_state_opens_all_routes_without_mandatory_puzzles() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	assert_bool(routing.is_route_open("corridor")).is_true()
	assert_bool(routing.is_route_open("maze")).is_true()
	assert_bool(routing.is_route_open("service_field")).is_true()
	assert_bool(routing.has_multiple_open_routes()).is_true()

# ── 2. El progreso de las máquinas abre las compuertas (modo flag legacy) ─────

func test_station_progress_opens_gated_junctions() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	routing.gate_on_machine_progress = true
	yield(_advance(), "completed")
	assert_bool(routing.is_junction_open("maze_exit")).is_false()
	assert_bool(routing.is_junction_open("field_link")).is_false()
	# Estación 1 (balancín) resuelta → se abre el paso a Estación 2.
	_set_lever("SeesawLever", true)
	yield(_advance(), "completed")
	assert_bool(routing.is_junction_open("maze_exit")).is_true()
	assert_bool(routing.is_junction_open("field_link")).is_false()
	# Estación 2 (péndulo) resuelta → se abre el enlace al campo streamed.
	_set_lever("PendulumLever", true)
	yield(_advance(), "completed")
	assert_bool(routing.is_junction_open("field_link")).is_true()

# ── 3. Más de un camino disponible ⇒ recorrido no lineal ─────────────────────

func test_multiple_routes_open_after_progress() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	routing.gate_on_machine_progress = true
	yield(_advance(), "completed")
	_set_lever("SeesawLever", true)
	yield(_advance(), "completed")
	assert_bool(routing.is_route_open("maze")).is_true()
	assert_bool(routing.has_multiple_open_routes()).is_true()
	_set_lever("PendulumLever", true)
	yield(_advance(), "completed")
	assert_bool(routing.is_route_open("service_field")).is_true()
	assert_int(routing.get_open_route_ids().size()).is_equal(3)

# ── 4. Pureza: sin estado acumulado oculto ───────────────────────────────────

func test_gate_state_is_a_pure_function_of_machine_state() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	routing.gate_on_machine_progress = true
	yield(_advance(), "completed")
	_set_lever("SeesawLever", true)
	yield(_advance(), "completed")
	assert_bool(routing.is_junction_open("maze_exit")).is_true()
	_set_lever("SeesawLever", false)
	yield(_advance(), "completed")
	assert_bool(routing.is_junction_open("maze_exit")).is_false()
	_set_lever("SeesawLever", true)
	yield(_advance(), "completed")
	assert_bool(routing.is_junction_open("maze_exit")).is_true()

# ── 5. Celda de enlace forzada en el streamer ────────────────────────────────

func test_streamer_forces_junction_cell_on_corridor_side() -> void:
	yield(_reset_levers(), "completed")
	var streamer = _bay.get_node_or_null("MachineBayLabyrinthStreamer")
	assert_object(streamer).is_not_null()
	var west: Dictionary = streamer.get_fixed_border_tiles(Vector2(0, 0))
	assert_bool(west.has("0,1")).is_true()
	assert_str(String(west["0,1"].get("id", ""))).is_equal("W")
	assert_float(float(west["0,1"].get("height", -1.0))).is_equal_approx(0.0, 0.001)
	# Espejo determinista: el borde este del chunk vecino comparte la misma fila.
	var mirror: Dictionary = streamer.get_fixed_border_tiles(Vector2(-1, 0))
	assert_bool(mirror.has("7,1")).is_true()
	assert_str(String(mirror["7,1"].get("id", ""))).is_equal("W")

# ── 6. Las compuertas no invaden el corredor central / Estación 1 ────────────

func test_gates_clear_of_station1_approach() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	for id in routing.get_junction_ids():
		var p: Vector3 = routing.get_junction_position(id)
		assert_float(p.x).is_greater(7.0)

# ── 7. La compuerta bloquea físicamente cerrada y libera abierta ─────────────
# Prueba "real" de que el camino alterno está gateado de verdad: la colisión del
# barrier se habilita/deshabilita según el estado de la máquina.

func test_closed_gate_blocks_and_open_gate_frees_collision() -> void:
	yield(_reset_levers(), "completed")
	var routing = _routing()
	routing.gate_on_machine_progress = true
	yield(_advance(120), "completed")
	var gate = routing.get_node_or_null("Gate_maze_exit")
	assert_object(gate).is_not_null()
	var barrier = gate.get_node_or_null("Barrier")
	assert_object(barrier).is_not_null()
	# Cerrada: el barrier está en la capa Prop y bloquea el paso.
	assert_int(barrier.collision_layer).is_equal(64)
	# Estación 1 resuelta → la compuerta anima y libera la colisión.
	_set_lever("SeesawLever", true)
	# anim_duration = 1.1 s ⇒ ~66 ticks; 120 deja margen.
	yield(_advance(120), "completed")
	assert_bool(routing.is_junction_open("maze_exit")).is_true()
	assert_int(barrier.collision_layer).is_equal(0)
	assert_int(barrier.collision_mask).is_equal(0)

