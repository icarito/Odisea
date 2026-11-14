extends Spatial
class_name MachineBayMazeRouting

# MachineBayMazeRouting.gd — director de ruteo NO LINEAL de la Bahía de Máquinas.
#
# Problema: el corredor de estaciones es lineal y el laberinto procedural era un
# callejón de una sola entrada. Este director conecta la ruta del laberinto
# (`LabyrinthSection` MST + `MachineBayLabyrinthStreamer` WFC) con las estaciones
# mediante compuertas (`MazeRoutingGate`) cuyo estado depende del avance de las
# MÁQUINAS (palancas de estación / Orden 0001 cerrada) — el "director de beats" es
# el propio `MachineLevel`, que ya acumula ese progreso.
#
# Diseño no lineal (ver `docs/features/FD-322_ruteo_laberinto_no_lineal.md`):
#   - Ruta crítica: el corredor de estaciones (FD-320), intacta.
#   - Ruta laberinto: boca del laberinto (siempre) → paso a Estación 2 (abre al
#     completar la Estación 1) — un atajo lateral entre E1 y E2.
#   - Ruta campo de servicio: la anterior + enlace al campo streamed (abre al
#     completar la Estación 2) — el laberinto WFC deja de ser un callejón sin salida.
#
# Determinismo: el estado de cada compuerta es una función pura del estado de
# `MachineLevel` (mismo replay → mismas compuertas). El director no introduce RNG ni
# estado propio; solo sincroniza compuertas, que sí son `replay_sync`.

const GateScene := preload("res://core_v2/levels/machines/MazeRoutingGate.tscn")

export(NodePath) var machine_level_path: NodePath = NodePath("../Level")
export(NodePath) var streamer_path: NodePath = NodePath("../MachineBayLabyrinthStreamer")

# Tabla determinista de enlaces. `requirement`:
#   always               → siempre abierta (boca del laberinto)
#   item_active:<NAME>   → el item/palanca <NAME> del MachineLevel está activo
#   order_complete       → la Orden 0001 quedó cerrada (válvula maestra)
# `fallback_pos` se usa cuando no hay streamer (tests del director aislado).
# `field_cell` fuerza la celda del campo streamed para que la compuerta abra sobre
# un piso transitable garantizado.
const JUNCTIONS := [
	{
		"id": "maze_entry",
		"title": "Boca del laberinto",
		"requirement": "always",
		"fallback_pos": Vector3(8.5, 0.0, 12.0),
		"field_cell": null,
	},
	{
		"id": "maze_exit",
		"title": "Paso a Estación 2",
		"requirement": "item_active:SeesawLever",
		"fallback_pos": Vector3(17.5, 0.0, 27.0),
		"field_cell": null,
	},
	{
		"id": "field_link",
		"title": "Enlace al campo de servicio streamed",
		"requirement": "item_active:PendulumLever",
		"fallback_pos": Vector3(23.5, 0.0, 30.5),
		"field_cell": {"chunk": Vector2(0, 0), "row": 1},
	},
]

# Rutas nombradas del nivel (para documentación y tests de topología). Una ruta está
# abierta cuando TODOS sus enlaces lo están.
const ROUTES := [
	{"id": "corridor", "title": "Corredor de estaciones (ruta crítica FD-320)", "junctions": []},
	{"id": "maze", "title": "Laberinto MST → Estación 2 (atajo lateral)", "junctions": ["maze_entry", "maze_exit"]},
	{"id": "service_field", "title": "Campo de servicio streamed (WFC)", "junctions": ["maze_entry", "maze_exit", "field_link"]},
]

var _streamer: Node = null
var _machine_level: Node = null
var _gates: Dictionary = {}  # id -> MazeRoutingGate

func _ready() -> void:
	if Engine.editor_hint:
		return
	_streamer = get_node_or_null(streamer_path)
	_machine_level = get_node_or_null(machine_level_path)
	_configure_streamer_cells()
	_build_gates()
	_evaluate(true)

func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_evaluate(false)

# Fuerza en el streamer las celdas de enlace (borde oeste a altura de cubierta) para
# que cada compuerta abra sobre piso walkable, sin depender del hash de costura.
func _configure_streamer_cells() -> void:
	if _streamer == null or not _streamer.has_method("set_junction_cells"):
		return
	var cells := {}
	for j in JUNCTIONS:
		var fc = j.get("field_cell", null)
		if fc == null:
			continue
		var chunk: Vector2 = fc["chunk"]
		cells["%d,%d" % [int(chunk.x), int(chunk.y)]] = int(fc["row"])
	_streamer.set_junction_cells(cells)

func _build_gates() -> void:
	for j in JUNCTIONS:
		var id := str(j["id"])
		var gate = GateScene.instance()
		gate.name = "Gate_" + id
		gate.transform = Transform(Basis.IDENTITY, _junction_world_position(j))
		add_child(gate)
		_gates[id] = gate

func _junction_world_position(j: Dictionary) -> Vector3:
	var fc = j.get("field_cell", null)
	if fc != null and _streamer != null and _streamer.has_method("get_junction_world_position"):
		var chunk: Vector2 = fc["chunk"]
		return _streamer.get_junction_world_position(chunk, int(fc["row"]))
	return j.get("fallback_pos", Vector3.ZERO)

func _evaluate(immediate: bool) -> void:
	for j in JUNCTIONS:
		var id := str(j["id"])
		var gate = _gates.get(id, null)
		if gate == null:
			continue
		var want: bool = _requirement_met(str(j.get("requirement", "always")))
		if gate.is_open() != want:
			gate.set_active(want, immediate)

func _requirement_met(req: String) -> bool:
	if req == "always":
		return true
	if _machine_level == null:
		return false
	if req == "order_complete":
		return _machine_level.has_method("is_work_order_completed") and bool(_machine_level.is_work_order_completed())
	if req.begins_with("item_active:"):
		if not _machine_level.has_method("get_item"):
			return false
		var item_name := req.substr("item_active:".length())
		var item = _machine_level.get_item(item_name)
		return is_instance_valid(item) and bool(item.get("is_active"))
	return false

# ── API para tests / depuración ──────────────────────────────────────────────

func get_junction_ids() -> Array:
	var out: Array = []
	for j in JUNCTIONS:
		out.append(str(j["id"]))
	return out

func get_junction_requirement(id: String) -> String:
	for j in JUNCTIONS:
		if str(j["id"]) == id:
			return str(j.get("requirement", "always"))
	return ""

func get_junction_position(id: String) -> Vector3:
	var gate = _gates.get(id, null)
	if is_instance_valid(gate):
		return gate.global_transform.origin
	for j in JUNCTIONS:
		if str(j["id"]) == id:
			return _junction_world_position(j)
	return Vector3.ZERO

func is_junction_open(id: String) -> bool:
	var gate = _gates.get(id, null)
	return is_instance_valid(gate) and bool(gate.is_open())

func get_open_junction_ids() -> Array:
	var out: Array = []
	for id in get_junction_ids():
		if is_junction_open(id):
			out.append(id)
	return out

func is_route_open(route_id: String) -> bool:
	for route in ROUTES:
		if str(route["id"]) != route_id:
			continue
		for jid in route["junctions"]:
			if not is_junction_open(str(jid)):
				return false
		return true
	return false

func get_open_route_ids() -> Array:
	var out: Array = []
	for route in ROUTES:
		if is_route_open(str(route["id"])):
			out.append(str(route["id"]))
	return out

# >1 camino disponible simultáneamente ⇒ el nivel admite recorridos no lineales.
func has_multiple_open_routes() -> bool:
	return get_open_route_ids().size() > 1
