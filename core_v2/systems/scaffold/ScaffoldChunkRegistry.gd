extends Reference
# Sin class_name: se consume con preload() (mismo criterio que FlowMetrics).
#
# Catalogo maestro de chunks de andamio para Transit-Run y ensamblador por semilla.
# Datos puros, sin escena: cada chunk es un grafo de plataformas en su marco local
# (x lateral, y altura, z a lo largo del tramo, 0..CHUNK_LENGTH) que FlowRouteValidator
# evalua tal cual. La proyeccion al cilindro es de ScaffoldOrbit; el arte, de las escenas.
#
# Es una CADENA 1D, no una rejilla: todo chunk entra por socket A y su salida principal
# casa con el A del siguiente, arrastrando un desplazamiento (dy, bank_deg). Los sockets
# S (estacion) y R (riel) son salidas laterales: nunca estan en la ruta principal.
#
# Los tamanos se derivan de las metricas con las mismas funciones del validador (como
# BayTransitFlow), asi dimensionar y validar no divergen. Contrato: WFC_FLOW_METRICS.md.

const Validator := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

const CHUNK_LENGTH := 12.0
const WALKWAY_WIDTH := 2.5
const RAIL_HEIGHT := 0.6
const RAIL_THICKNESS := 0.1
const D_NOM_RATIO := 0.70        # hueco de la linea principal
const H_NOM_RATIO := 0.75        # desnivel de la linea principal
const TOOL_RATIO := 1.20         # por encima: imposible a pie
const RHYTHM_GAP_RATIO := 0.55   # WFC_FLOW_METRICS §5 RhythmSteps
const SOCKET_REACH_RATIO := 0.95 # WFC_FLOW_METRICS §5 CuratedSocket (0.90-1.00)
# Grados de peralte por segmento igual a lo largo del chunk (borde +X arriba).
const BANK_PROFILE_DEG := [5.0, 10.0, 15.0, 15.0, 10.0, 5.0]
const LANDING := 2.5             # tramo minimo de carrera antes/despues de un hueco

# [id, familia]. El peso de la familia se reparte entre sus miembros.
const CHUNKS := [
	["scaffold_sprint_chute", "main"], ["scaffold_triple_cadence", "main"],
	["scaffold_gap_leap", "main"], ["scaffold_curved_bank", "main"],
	["scaffold_gloo_rise", "tool"], ["scaffold_catenary_span", "tool"],
	["scaffold_laser_choke", "tool"],
	["diorama_mag_cart", "side"], ["diorama_counterweight_crane", "side"],
	["scaffold_splitter_hub", "side"],
]
const FAMILY_WEIGHT := {"main": 70.0, "tool": 20.0, "side": 10.0}
const ENDPOINT_CHUNK := "scaffold_sprint_chute"


static func chunk_ids() -> Array:
	var out := []
	for c in CHUNKS:
		out.append(c[0])
	return out


static func d_max(m: Dictionary, dh: float = 0.0) -> float:
	return Validator.compute_d_max(float(m["v_run"]), float(m["v_jump"]), float(m["g"]), dh, float(m["tick"]))


static func h_max(m: Dictionary) -> float:
	return Validator.compute_h_max(float(m["v_jump"]), float(m["g"]), float(m["tick"]))


static func _deck(id: String, z0: float, z1: float, y: float = 0.0, x: float = 0.0) -> Dictionary:
	return {"id": id, "position": Vector3(x, y, (z0 + z1) * 0.5), "size": Vector3(WALKWAY_WIDTH, 0.3, z1 - z0)}


static func _edge(from: String, to: String, gap: float, dh: float = 0.0, extra: Dictionary = {}) -> Dictionary:
	var e := {"from": from, "to": to, "gap_horizontal": gap, "delta_h": dh}
	for k in extra:
		e[k] = extra[k]
	return e


# Grafo local de un chunk: {nodes, edges, in, out, dy, bank_deg, side_outs, out_socket, blockers}.
# blockers: cajas que cierran un atajo de herramienta (pared de gloo, mamparo cortable).
# spans: huecos horizontales que se puentean con gloo.
static func build_chunk(id: String, m: Dictionary) -> Dictionary:
	var l := CHUNK_LENGTH
	var d: float = d_max(m)
	var c := {"id": id, "nodes": [], "edges": [], "in": "a", "out": "a", "dy": 0.0, "bank_deg": 0.0, "side_outs": {},
		"out_socket": "A", "blockers": [], "spans": []}
	var side := WALKWAY_WIDTH  # pasarela auxiliar pegada a la principal
	match id:
		"scaffold_sprint_chute":
			c["nodes"] = [_deck("a", 0.0, l)]
		"scaffold_curved_bank":
			# Peralte SOLO VISUAL para la ruta: la pasarela se inclina de verdad (malla y
			# colision) alrededor de su linea central, pero entra y sale plana, asi que el
			# grafo, los waypoints y el socket de salida son los de un tramo recto.
			var banked: Dictionary = _deck("a", 0.0, l)
			banked["roll_profile"] = BANK_PROFILE_DEG
			c["nodes"] = [banked]
			c["bank_deg"] = 15.0
		"scaffold_triple_cadence":
			var pad := 1.5
			var gap: float = min(RHYTHM_GAP_RATIO * d, (l - 4.0 * pad) / 3.0)
			var step: float = pad + gap
			c["nodes"] = [_deck("a", 0.0, pad), _deck("b", step, step + pad),
				_deck("c", 2.0 * step, 2.0 * step + pad), _deck("d", 3.0 * step, l)]
			for pair in [["a", "b"], ["b", "c"], ["c", "d"]]:
				c["edges"].append(_edge(pair[0], pair[1], gap, 0.0, {"tags": ["RhythmSteps"]}))
			c["out"] = "d"
		"scaffold_gap_leap":
			var drop := -0.5
			var leap: float = min(D_NOM_RATIO * d_max(m, drop), l - 2.0 * LANDING)
			c["nodes"] = [_deck("a", 0.0, LANDING), _deck("b", LANDING + leap, l, drop)]
			c["edges"] = [_edge("a", "b", leap, drop, {"tags": ["SprintGap"]})]
			c["out"] = "b"
			c["dy"] = drop
		"scaffold_gloo_rise":
			# Pared > H_max: a pie solo por la rampa perimetral; con gloo, directo.
			var rise: float = TOOL_RATIO * h_max(m)
			var wall_z: float = l - LANDING
			var ramp: Dictionary = _deck("ramp", 1.0, 8.0, rise * 0.5, side)
			ramp["rise"] = rise  # inclinada: sube `rise` de z0 a z1 (position.y es el punto medio)
			ramp["open_sides"] = [-1]  # el costado interior da a la pasarela, no al vacio
			# ramp_foot: se entra a la rampa por su pie, no de costado (de costado es una pared).
			c["nodes"] = [_deck("a", 0.0, wall_z), _deck("ramp_foot", 0.0, 1.0, 0.0, side), ramp,
				_deck("ramp_top", 8.0, l, rise, side), _deck("b", wall_z, l, rise)]
			c["edges"] = [_edge("a", "ramp_foot", 0.0), _edge("ramp_foot", "ramp", 0.0),
				_edge("ramp", "ramp_top", 0.0), _edge("ramp_top", "b", 0.0),
				_edge("a", "b", 0.0, rise, {"tags": ["GlooClimb"]})]
			c["blockers"] = [{"id": "gloo_wall", "position": Vector3(0.0, rise * 0.5, wall_z + 0.15),
				"size": Vector3(WALKWAY_WIDTH, rise, 0.3), "cuttable": false}]
			c["out"] = "b"
			c["dy"] = rise
			c["out_socket"] = "A_High"
		"scaffold_catenary_span":
			c["nodes"] = [_deck("a", 0.0, 1.0), _deck("s1", 1.5, 5.0, 0.0, side),
				_deck("s2", 7.0, 10.5, 0.0, side), _deck("b", l - 1.0, l)]
			c["edges"] = [_edge("a", "s1", 0.0), _edge("s1", "s2", 2.0), _edge("s2", "b", 0.0),
				_edge("a", "b", l - 2.0, 0.0, {"requires_tool": true, "tags": ["Catenary"]})]
			# El hueco se puede puentear con gloo (GlooSpan); el cable queda como decorado.
			c["spans"] = [{"id": "gloo_bridge", "from": Vector3(0.0, 0.0, 1.0),
				"to": Vector3(0.0, 0.0, l - 1.0), "required_blobs": 3}]
			c["out"] = "b"
		"scaffold_laser_choke":
			c["nodes"] = [_deck("a", 0.0, 6.0), _deck("s", 3.0, 9.0, 0.0, side), _deck("b", 6.0, l)]
			c["edges"] = [_edge("a", "s", 0.0), _edge("s", "b", 0.0),
				_edge("a", "b", 0.0, 0.0, {"requires_tool": true, "tags": ["LaserCut"]})]
			# Mas alto que el salto: si se puede saltar por encima, el laser no hace falta.
			var bulk_h: float = TOOL_RATIO * h_max(m)
			c["blockers"] = [{"id": "bulkhead", "position": Vector3(0.0, bulk_h * 0.5, 6.0),
				"size": Vector3(WALKWAY_WIDTH, bulk_h, 0.3), "cuttable": true}]
			c["out"] = "b"
		"diorama_mag_cart":
			c["nodes"] = [_deck("a", 0.0, l), _deck("rail", l - 1.0, l, 0.0, -side)]
			c["edges"] = [_edge("a", "rail", 0.0, 0.0, {"tags": ["MagRail"]})]
			c["side_outs"] = {"R": "rail"}
		"diorama_counterweight_crane", "scaffold_splitter_hub":
			var sx: float = side + SOCKET_REACH_RATIO * d
			c["nodes"] = [_deck("a", 0.0, l), _deck("station", 4.0, 8.0, 0.0, sx)]
			c["edges"] = [_edge("a", "station", SOCKET_REACH_RATIO * d, 0.0, {"tags": ["CuratedSocket"]})]
			c["side_outs"] = {"S": "station"}
		_:
			return {}
	_assign_rails(c)
	return c


# Barandas: cada plataforma lleva baranda en sus dos costados (-1 = -X, +1 = +X) salvo hacia
# donde la ruta cruza de costado (una arista la une con una plataforma de ese lado). Es dato
# del registro porque la baranda tiene colision: malla y fisica salen de aqui.
static func _assign_rails(c: Dictionary) -> void:
	var by_id := {}
	for n in c["nodes"]:
		by_id[n["id"]] = n
		n["rails"] = [-1, 1]
		for open_side in n.get("open_sides", []):
			n["rails"].erase(open_side)
	for e in c["edges"]:
		var a: Dictionary = by_id[e["from"]]
		var b: Dictionary = by_id[e["to"]]
		var dx: float = b["position"].x - a["position"].x
		if abs(dx) < 0.1:
			continue
		var side: int = 1 if dx > 0.0 else -1
		a["rails"].erase(side)
		b["rails"].erase(-side)


# Secuencia determinista de ids. LCG propio: nada de randf/randomize (AGENTS §1.2).
static func sequence(seed_val: int, count: int) -> Array:
	var per_family := {}
	for c in CHUNKS:
		per_family[c[1]] = int(per_family.get(c[1], 0)) + 1
	var state: int = (seed_val * 2654435761 + 1013904223) & 0x7fffffff
	var out := []
	for i in range(count):
		if i == 0 or i == count - 1:
			out.append(ENDPOINT_CHUNK)
			continue
		state = (state * 1103515245 + 12345) & 0x7fffffff
		var roll: float = float((state >> 8) % 10000) / 100.0
		var acc := 0.0
		var pick: String = ENDPOINT_CHUNK
		for c in CHUNKS:
			acc += float(FAMILY_WEIGHT[c[1]]) / float(per_family[c[1]])
			if roll < acc:
				pick = c[0]
				break
		out.append(pick)
	return out


# Grafo completo {entry, exit, nodes, edges, placements} listo para FlowRouteValidator.validate().
static func generate(seed_val: int, count: int, m: Dictionary) -> Dictionary:
	var graph := {"entry": "", "exit": "", "nodes": [], "edges": [], "placements": []}
	var base := Vector3.ZERO
	var prev_out := ""
	var ids: Array = sequence(seed_val, count)
	for i in range(ids.size()):
		var c: Dictionary = build_chunk(str(ids[i]), m)
		var prefix := "c%02d_" % i
		for n in c["nodes"]:
			var node: Dictionary = n.duplicate()
			node["id"] = prefix + str(n["id"])
			node["position"] = n["position"] + base
			graph["nodes"].append(node)
		for e in c["edges"]:
			var edge: Dictionary = e.duplicate()
			edge["from"] = prefix + str(e["from"])
			edge["to"] = prefix + str(e["to"])
			graph["edges"].append(edge)
		var in_id: String = prefix + str(c["in"])
		if prev_out == "":
			graph["entry"] = in_id
		else:
			graph["edges"].append(_edge(prev_out, in_id, 0.0))
		prev_out = prefix + str(c["out"])
		graph["placements"].append({"index": i, "id": ids[i], "origin": base, "bank_deg": c["bank_deg"], "side_outs": c["side_outs"]})
		base += Vector3(0.0, float(c["dy"]), CHUNK_LENGTH)
	graph["exit"] = prev_out
	return graph
