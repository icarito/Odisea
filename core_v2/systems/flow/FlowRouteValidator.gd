extends Reference
class_name FlowRouteValidator

# Validador determinista y puro (sin escena) de rutas de parkour cinético.
#
# Evalúa un grafo de plataformas o chunks contra las métricas físicas del
# jugador (g, v_run, v_jump, tick y umbrales main/opcional) para determinar:
#   (a) Si existe una ruta principal de entrada a salida usando SOLO saltos
#       dentro del umbral main (<= 80% de D(delta_h) y H_max), sin herramientas
#       ni sockets curados.
#   (b) Qué aristas son opcionales (tramo 90-100% / roll-jump o CuratedSocket)
#       o requieren herramienta (GlooClimb, MagRail).
#   (c) Un reporte legible destacando la arista crítica más exigente.

const TAG_SPRINT_GAP := "SprintGap"
const TAG_RHYTHM_STEPS := "RhythmSteps"
const TAG_GLOO_CLIMB := "GlooClimb"
const TAG_MAG_RAIL := "MagRail"
const TAG_CURATED_SOCKET := "CuratedSocket"

const CAT_MAIN := "main"
const CAT_OPTIONAL_SKILL := "optional_skill"
const CAT_TOOL := "requires_tool"
const CAT_SOCKET := "curated_socket"
const CAT_UNREACHABLE := "unreachable"

const DEFAULT_G := 14.0
const DEFAULT_V_RUN := 7.0
const DEFAULT_V_JUMP := 10.0
const DEFAULT_TICK := 1.0 / 60.0
const DEFAULT_MAIN_THRESHOLD := 0.80
const DEFAULT_OPTIONAL_MIN := 0.90
const DEFAULT_OPTIONAL_MAX := 1.00

const THRESHOLD_EPSILON := 1e-5


static func default_metrics() -> Dictionary:
	return {
		"g": DEFAULT_G,
		"v_run": DEFAULT_V_RUN,
		"v_jump": DEFAULT_V_JUMP,
		"tick": DEFAULT_TICK,
		"main_threshold": DEFAULT_MAIN_THRESHOLD,
		"optional_min": DEFAULT_OPTIONAL_MIN,
		"optional_max": DEFAULT_OPTIONAL_MAX,
	}


# Helper compatible con duck-typing para construir el diccionario de métricas
# desde una instancia de FlowMetrics.gd cuando aterrice en main.
static func metrics_from_object(flow_metrics) -> Dictionary:
	var base := default_metrics()
	if flow_metrics == null:
		return base
	if typeof(flow_metrics) == TYPE_DICTIONARY:
		return _normalize_metrics(flow_metrics)
	if flow_metrics.has_method("to_dict"):
		var d = flow_metrics.call("to_dict")
		if typeof(d) == TYPE_DICTIONARY:
			return _normalize_metrics(d)
	var keys := ["g", "v_run", "v_jump", "tick", "main_threshold", "optional_min", "optional_max"]
	for k in keys:
		var val = flow_metrics.get(k)
		if val != null:
			base[k] = float(val)
	return _normalize_metrics(base)


static func compute_h_max(v_jump: float, g: float, tick: float = 0.0) -> float:
	if g <= 0.0 or v_jump <= 0.0:
		return 0.0
	var continuous := (v_jump * v_jump) / (2.0 * g)
	var tick_correction := 0.5 * v_jump * max(tick, 0.0)
	return continuous + tick_correction


static func compute_air_time(v_jump: float, g: float, delta_h: float) -> float:
	if g <= 0.0 or v_jump <= 0.0:
		return -1.0
	var disc := (v_jump * v_jump) - (2.0 * g * delta_h)
	if disc < 0.0:
		return -1.0
	var t_air := (v_jump + sqrt(disc)) / g
	if t_air < 0.0:
		return -1.0
	return t_air


static func compute_d_max(v_run: float, v_jump: float, g: float, delta_h: float, tick: float = 0.0) -> float:
	if v_run < 0.0:
		return -1.0
	var t_air := compute_air_time(v_jump, g, delta_h)
	if t_air < 0.0:
		return -1.0
	var continuous := v_run * t_air
	var tick_correction := 0.5 * v_run * max(tick, 0.0)
	return continuous + tick_correction


static func evaluate_edge(edge: Dictionary, nodes_by_id: Dictionary, metrics: Dictionary) -> Dictionary:
	var m := _normalize_metrics(metrics)
	var from_id := str(edge.get("from", ""))
	var to_id := str(edge.get("to", ""))

	var from_node: Dictionary = nodes_by_id.get(from_id, {})
	var to_node: Dictionary = nodes_by_id.get(to_id, {})

	var gap_h := _resolve_gap_horizontal(edge, from_node, to_node)
	var delta_h := _resolve_delta_h(edge, from_node, to_node)
	var g_used := float(edge.get("g", to_node.get("g", from_node.get("g", m["g"]))))
	var v_run := float(m["v_run"])
	var v_jump := float(m["v_jump"])
	var tick := float(m["tick"])
	var main_thr := float(m["main_threshold"])
	var opt_min := float(m["optional_min"])
	var opt_max := float(m["optional_max"])

	var h_max := compute_h_max(v_jump, g_used, tick)
	var d_max := compute_d_max(v_run, v_jump, g_used, delta_h, tick)

	var tags := _collect_edge_tags(edge, to_node)
	var requires_tool := bool(edge.get("requires_tool", false)) or _has_any_tag(tags, [TAG_GLOO_CLIMB, TAG_MAG_RAIL])
	var is_socket := bool(edge.get("is_socket", edge.get("curated_socket", false))) or _has_any_tag(tags, [TAG_CURATED_SOCKET])

	var ratio_h := 0.0
	if delta_h > 0.0:
		ratio_h = (delta_h / h_max) if h_max > 0.0 else INF

	var ratio_d := INF
	if gap_h <= 0.0 and d_max >= 0.0:
		ratio_d = 0.0
	elif d_max > 0.0:
		ratio_d = gap_h / d_max

	var demand_ratio := max(ratio_d, ratio_h)
	var reasons: Array = []
	var category := CAT_UNREACHABLE

	if is_socket:
		category = CAT_SOCKET
		reasons.append("CuratedSocket: ruta secundaria opcional, excluida de ruta principal")
	elif requires_tool:
		category = CAT_TOOL
		reasons.append("Requiere herramienta (%s)" % _format_tool_tags(tags))
	elif d_max < 0.0 or ratio_h > (1.0 + THRESHOLD_EPSILON) or ratio_d > (1.0 + THRESHOLD_EPSILON):
		category = CAT_UNREACHABLE
		if d_max < 0.0 or ratio_h > (1.0 + THRESHOLD_EPSILON):
			reasons.append("Altura delta_h=%.2fm supera H_max=%.2fm" % [delta_h, h_max])
		if d_max >= 0.0 and ratio_d > (1.0 + THRESHOLD_EPSILON):
			reasons.append("Hueco %.2fm supera D_max=%.2fm" % [gap_h, d_max])
	elif demand_ratio <= (main_thr + THRESHOLD_EPSILON):
		category = CAT_MAIN
		reasons.append("Dentro de umbral main (<= %.0f%%)" % [main_thr * 100.0])
	else:
		category = CAT_OPTIONAL_SKILL
		if demand_ratio >= (opt_min - THRESHOLD_EPSILON):
			reasons.append("Tramo opcional de habilidad/roll-jump (%.1f%%)" % [demand_ratio * 100.0])
		else:
			reasons.append("Supera umbral main %.0f%% (%.1f%%), queda como opcional" % [main_thr * 100.0, demand_ratio * 100.0])

	var in_roll_jump_band := (
		category == CAT_OPTIONAL_SKILL
		and demand_ratio >= (opt_min - THRESHOLD_EPSILON)
		and demand_ratio <= (opt_max + THRESHOLD_EPSILON)
	)

	return {
		"from": from_id,
		"to": to_id,
		"gap_horizontal": gap_h,
		"delta_h": delta_h,
		"g_used": g_used,
		"d_max": d_max,
		"h_max": h_max,
		"ratio_d": ratio_d,
		"ratio_h": ratio_h,
		"demand_ratio": demand_ratio,
		"category": category,
		"in_roll_jump_band": in_roll_jump_band,
		"main_passable": category == CAT_MAIN,
		"tags": tags,
		"reasons": reasons,
	}


static func validate(graph: Dictionary, metrics: Dictionary = {}) -> Dictionary:
	var m := _normalize_metrics(metrics)
	var nodes_by_id := _index_nodes(graph.get("nodes", []))
	var entry_id := str(graph.get("entry", ""))
	var exit_id := str(graph.get("exit", ""))

	var raw_edges: Array = graph.get("edges", [])
	var evaluated_edges: Array = []
	for e in raw_edges:
		if typeof(e) == TYPE_DICTIONARY:
			evaluated_edges.append(evaluate_edge(e, nodes_by_id, m))

	evaluated_edges = _sort_evaluated_edges(evaluated_edges)

	var optional_edges: Array = []
	var tool_edges: Array = []
	var unreachable_edges: Array = []
	var main_adj: Dictionary = {}

	for ev in evaluated_edges:
		var cat := str(ev["category"])
		if cat == CAT_MAIN:
			var f := str(ev["from"])
			if not main_adj.has(f):
				main_adj[f] = []
			main_adj[f].append(ev)
		elif cat == CAT_OPTIONAL_SKILL or cat == CAT_SOCKET:
			optional_edges.append(ev)
		elif cat == CAT_TOOL:
			tool_edges.append(ev)
		else:
			unreachable_edges.append(ev)

	var path_result := _find_best_main_path(entry_id, exit_id, nodes_by_id, main_adj)
	var valid_main: bool = bool(path_result["found"])
	var main_path: Array = path_result["path"]
	var main_path_edges: Array = path_result["edges"]

	var critical_main_edge: Dictionary = _pick_most_demanding_edge(main_path_edges)
	var most_demanding_edge: Dictionary = _pick_most_demanding_edge(evaluated_edges)
	var critical_edge: Dictionary = critical_main_edge if valid_main and not critical_main_edge.empty() else most_demanding_edge

	var report := _build_report(
		valid_main,
		entry_id,
		exit_id,
		main_path,
		critical_edge,
		evaluated_edges,
		optional_edges,
		tool_edges,
		unreachable_edges,
		m
	)

	var main_waypoints: Array = _build_main_waypoints(main_path, nodes_by_id)
	var side_socket_waypoints: Array = _build_side_socket_waypoints(optional_edges, nodes_by_id)

	return {
		"valid_main_route": valid_main,
		"main_path": main_path,
		"main_waypoints": main_waypoints,
		"side_socket_waypoints": side_socket_waypoints,
		"main_path_edges": main_path_edges,
		"edges_evaluated": evaluated_edges,
		"optional_edges": optional_edges,
		"tool_edges": tool_edges,
		"unreachable_edges": unreachable_edges,
		"critical_edge": critical_edge,
		"critical_main_edge": critical_main_edge,
		"most_demanding_edge": most_demanding_edge,
		"metrics_used": m,
		"report": report,
	}


# Hook de lectura determinista: devuelve la lista ordenada de waypoints de la ruta
# principal (entry -> exit) sin mutar el grafo ni la generacion.
static func extract_main_waypoints(graph: Dictionary, metrics: Dictionary = {}) -> Array:
	var res := validate(graph, metrics)
	if not bool(res.get("valid_main_route", false)):
		return []
	return res.get("main_waypoints", [])


# Hook de lectura determinista: devuelve los Side Sockets (CuratedSocket) fuera
# de la ruta principal, ordenados por id de destino.
static func extract_side_socket_waypoints(graph: Dictionary, metrics: Dictionary = {}) -> Array:
	var res := validate(graph, metrics)
	return res.get("side_socket_waypoints", [])


static func _build_main_waypoints(main_path: Array, nodes_by_id: Dictionary) -> Array:
	var out: Array = []
	var count := main_path.size()
	for i in range(count):
		var nid := str(main_path[i])
		var node: Dictionary = nodes_by_id.get(nid, {})
		out.append({
			"index": i,
			"id": nid,
			"position": _to_vec3(node.get("position", Vector3.ZERO)),
			"has_position": node.has("position"),
			"tags": _copy_string_array(node.get("tags", [])),
			"is_entry": i == 0,
			"is_exit": i == count - 1,
		})
	return out


static func _build_side_socket_waypoints(optional_edges: Array, nodes_by_id: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for ev in optional_edges:
		if str(ev.get("category", "")) != CAT_SOCKET:
			continue
		var to_id := str(ev.get("to", ""))
		if to_id == "" or seen.has(to_id):
			continue
		seen[to_id] = true
		var to_node: Dictionary = nodes_by_id.get(to_id, {})
		out.append({
			"id": to_id,
			"from": str(ev.get("from", "")),
			"position": _to_vec3(to_node.get("position", Vector3.ZERO)),
			"has_position": to_node.has("position"),
			"tags": _copy_string_array(to_node.get("tags", [])),
			"category": CAT_SOCKET,
		})
	return out


static func _copy_string_array(raw) -> Array:
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			var s := str(item)
			if s != "":
				out.append(s)
	return out


static func _normalize_metrics(metrics: Dictionary) -> Dictionary:
	var base := default_metrics()
	for k in base.keys():
		if metrics.has(k):
			base[k] = float(metrics[k])
	return base


static func _index_nodes(nodes: Array) -> Dictionary:
	var out: Dictionary = {}
	for n in nodes:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nid := str(n.get("id", ""))
		if nid != "":
			out[nid] = n
	return out


static func _to_vec3(val) -> Vector3:
	if typeof(val) == TYPE_VECTOR3:
		return val
	if typeof(val) == TYPE_ARRAY and val.size() >= 3:
		return Vector3(float(val[0]), float(val[1]), float(val[2]))
	if typeof(val) == TYPE_DICTIONARY:
		return Vector3(float(val.get("x", 0.0)), float(val.get("y", 0.0)), float(val.get("z", 0.0)))
	return Vector3.ZERO


static func _resolve_gap_horizontal(edge: Dictionary, from_node: Dictionary, to_node: Dictionary) -> float:
	if edge.has("gap_horizontal"):
		return max(0.0, float(edge["gap_horizontal"]))
	if edge.has("gap"):
		return max(0.0, float(edge["gap"]))
	if from_node.has("position") and to_node.has("position"):
		var p_from := _to_vec3(from_node["position"])
		var p_to := _to_vec3(to_node["position"])
		var delta_xz := Vector2(p_to.x - p_from.x, p_to.z - p_from.z)
		var center_dist := delta_xz.length()
		var margin := _platform_edge_margin(from_node, delta_xz) + _platform_edge_margin(to_node, delta_xz)
		return max(0.0, center_dist - margin)
	return 0.0


static func _platform_edge_margin(node: Dictionary, dir_xz: Vector2) -> float:
	if not node.has("size"):
		return 0.0
	var sz_val = node["size"]
	if typeof(sz_val) == TYPE_INT or typeof(sz_val) == TYPE_REAL:
		return max(0.0, float(sz_val) * 0.5)
	var sz := _to_vec3(sz_val)
	if dir_xz.length_squared() <= 1e-8:
		return 0.0
	var d := dir_xz.normalized()
	return abs(d.x) * (sz.x * 0.5) + abs(d.y) * (sz.z * 0.5)


static func _resolve_delta_h(edge: Dictionary, from_node: Dictionary, to_node: Dictionary) -> float:
	if edge.has("delta_h"):
		return float(edge["delta_h"])
	if edge.has("dh"):
		return float(edge["dh"])
	if from_node.has("position") and to_node.has("position"):
		var p_from := _to_vec3(from_node["position"])
		var p_to := _to_vec3(to_node["position"])
		return p_to.y - p_from.y
	return 0.0


static func _collect_edge_tags(edge: Dictionary, to_node: Dictionary) -> Array:
	var seen: Dictionary = {}
	var tags: Array = []
	for src in [edge.get("tags", []), to_node.get("tags", [])]:
		if typeof(src) == TYPE_ARRAY:
			for t in src:
				var ts := str(t)
				if ts != "" and not seen.has(ts):
					seen[ts] = true
					tags.append(ts)
	tags.sort()
	return tags


static func _has_any_tag(tags: Array, candidates: Array) -> bool:
	for c in candidates:
		if tags.has(c):
			return true
	return false


static func _format_tool_tags(tags: Array) -> String:
	var tools: Array = []
	for t in tags:
		if t == TAG_GLOO_CLIMB or t == TAG_MAG_RAIL:
			tools.append(t)
	if tools.empty():
		return "Tool"
	return PoolStringArray(tools).join(", ")


static func _sort_evaluated_edges(edges: Array) -> Array:
	var sorted := edges.duplicate()
	var n := sorted.size()
	for i in range(1, n):
		var key: Dictionary = sorted[i]
		var j := i - 1
		while j >= 0 and _edge_less(key, sorted[j]):
			sorted[j + 1] = sorted[j]
			j -= 1
		sorted[j + 1] = key
	return sorted


static func _edge_less(a: Dictionary, b: Dictionary) -> bool:
	var af := str(a.get("from", ""))
	var bf := str(b.get("from", ""))
	if af != bf:
		return af < bf
	var at := str(a.get("to", ""))
	var bt := str(b.get("to", ""))
	if at != bt:
		return at < bt
	return float(a.get("demand_ratio", 0.0)) < float(b.get("demand_ratio", 0.0))


static func _node_blocks_main_route(node: Dictionary) -> bool:
	var tags = node.get("tags", [])
	if typeof(tags) != TYPE_ARRAY:
		return false
	return _has_any_tag(tags, [TAG_GLOO_CLIMB, TAG_MAG_RAIL, TAG_CURATED_SOCKET])


# Dijkstra minimax determinista: minimiza el demand_ratio máximo de la ruta,
# luego cantidad de saltos, y desempata lexicográficamente por node_id.
static func _find_best_main_path(
	entry_id: String,
	exit_id: String,
	nodes_by_id: Dictionary,
	main_adj: Dictionary
) -> Dictionary:
	if entry_id == "" or exit_id == "":
		return {"found": false, "path": [], "edges": []}
	if not nodes_by_id.has(entry_id) or not nodes_by_id.has(exit_id):
		return {"found": false, "path": [], "edges": []}
	if _node_blocks_main_route(nodes_by_id[entry_id]) or _node_blocks_main_route(nodes_by_id[exit_id]):
		return {"found": false, "path": [], "edges": []}
	if entry_id == exit_id:
		return {"found": true, "path": [entry_id], "edges": []}

	var best_cost: Dictionary = {}
	var best_hops: Dictionary = {}
	var prev_node: Dictionary = {}
	var prev_edge: Dictionary = {}
	var visited: Dictionary = {}
	var frontier: Array = [entry_id]

	best_cost[entry_id] = 0.0
	best_hops[entry_id] = 0

	while not frontier.empty():
		frontier.sort()
		var u := str(frontier[0])
		var u_cost := float(best_cost[u])
		var u_hops := int(best_hops[u])
		for idx in range(1, frontier.size()):
			var cand := str(frontier[idx])
			var c_cost := float(best_cost[cand])
			var c_hops := int(best_hops[cand])
			if c_cost < u_cost - 1e-9 or (abs(c_cost - u_cost) <= 1e-9 and (c_hops < u_hops or (c_hops == u_hops and cand < u))):
				u = cand
				u_cost = c_cost
				u_hops = c_hops

		frontier.erase(u)
		if visited.has(u):
			continue
		visited[u] = true

		if u == exit_id:
			break

		var outgoing: Array = main_adj.get(u, [])
		for ev in outgoing:
			var v := str(ev["to"])
			if visited.has(v):
				continue
			var v_node: Dictionary = nodes_by_id.get(v, {})
			if _node_blocks_main_route(v_node):
				continue
			var new_cost := max(u_cost, float(ev["demand_ratio"]))
			var new_hops := u_hops + 1
			var should_update := false
			if not best_cost.has(v):
				should_update = true
			else:
				var cur_cost := float(best_cost[v])
				var cur_hops := int(best_hops[v])
				if new_cost < cur_cost - 1e-9:
					should_update = true
				elif abs(new_cost - cur_cost) <= 1e-9 and new_hops < cur_hops:
					should_update = true
				elif abs(new_cost - cur_cost) <= 1e-9 and new_hops == cur_hops and u < str(prev_node.get(v, "")):
					should_update = true

			if should_update:
				best_cost[v] = new_cost
				best_hops[v] = new_hops
				prev_node[v] = u
				prev_edge[v] = ev
				if not frontier.has(v):
					frontier.append(v)

	if not best_cost.has(exit_id):
		return {"found": false, "path": [], "edges": []}

	var path: Array = []
	var edges: Array = []
	var cur := exit_id
	while cur != "":
		path.push_front(cur)
		if prev_edge.has(cur):
			edges.push_front(prev_edge[cur])
		cur = str(prev_node.get(cur, ""))

	return {"found": true, "path": path, "edges": edges}


static func _pick_most_demanding_edge(edges: Array) -> Dictionary:
	if edges.empty():
		return {}
	var best: Dictionary = edges[0]
	for i in range(1, edges.size()):
		var cur: Dictionary = edges[i]
		var cur_r := float(cur.get("demand_ratio", 0.0))
		var best_r := float(best.get("demand_ratio", 0.0))
		if cur_r > best_r + 1e-9:
			best = cur
		elif abs(cur_r - best_r) <= 1e-9 and _edge_less(cur, best):
			best = cur
	return best


static func _build_report(
	valid_main: bool,
	entry_id: String,
	exit_id: String,
	main_path: Array,
	critical_edge: Dictionary,
	evaluated_edges: Array,
	optional_edges: Array,
	tool_edges: Array,
	unreachable_edges: Array,
	m: Dictionary
) -> String:
	var lines: Array = []
	var status := "PASS" if valid_main else "FAIL"
	lines.append("[FlowRouteValidator] %s | entry=%s -> exit=%s" % [status, entry_id, exit_id])
	lines.append(
		"Metricas: g=%.2f, v_run=%.2f, v_jump=%.2f, tick=%.4fs, main<=%.0f%%"
		% [m["g"], m["v_run"], m["v_jump"], m["tick"], m["main_threshold"] * 100.0]
	)

	if valid_main:
		lines.append("Ruta principal (%d saltos): %s" % [max(0, main_path.size() - 1), PoolStringArray(main_path).join(" -> ")])
	else:
		lines.append("Ruta principal: NO ENCONTRADA (ningún camino cumple umbral main sin herramientas/sockets)")

	if not critical_edge.empty():
		var pct := "%.1f%%" % [float(critical_edge["demand_ratio"]) * 100.0] if float(critical_edge["demand_ratio"]) < INF else "INF"
		lines.append(
			"Arista crítica: %s -> %s [%s] | gap=%.2fm (D_max=%.2fm) | dh=%.2fm (H_max=%.2fm) | exigencia=%s"
			% [
				critical_edge["from"],
				critical_edge["to"],
				critical_edge["category"],
				critical_edge["gap_horizontal"],
				critical_edge["d_max"],
				critical_edge["delta_h"],
				critical_edge["h_max"],
				pct,
			]
		)

	lines.append(
		"Resumen aristas (%d total): main=%d, opcionales=%d, herramienta=%d, inalcanzables=%d"
		% [
			evaluated_edges.size(),
			evaluated_edges.size() - optional_edges.size() - tool_edges.size() - unreachable_edges.size(),
			optional_edges.size(),
			tool_edges.size(),
			unreachable_edges.size(),
		]
	)
	return PoolStringArray(lines).join("\n")
