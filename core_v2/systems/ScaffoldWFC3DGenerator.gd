extends Spatial

# Volumen del gap casco-espiral
const VOLUME_X = 200.0
const VOLUME_Y = 100.0
const VOLUME_Z = 60.0
const LEVELS = 4          # 4 niveles verticales
const LEVEL_HEIGHT = 25.0

const ROOM_WEIGHTS = {
	"sS": 3.0,   # común
	"sM": 2.0,   # frecuente
	"sL": 0.8,   # pocas, puntos focales
	"sJ": 1.5,   # intersecciones
	"sD": 1.0,   # terminals/secrets
}

const ROOM_SCENES = {
	"sS": "res://core_v2/props/scaffold/RoomSmall.tscn",
	"sM": "res://core_v2/props/scaffold/RoomMedium.tscn",
	"sL": "res://core_v2/props/scaffold/RoomLarge.tscn",
	"sJ": "res://core_v2/props/scaffold/RoomJunction.tscn",
	"sD": "res://core_v2/props/scaffold/RoomDeadEnd.tscn",
}

const CONNECTOR_SCENES = {
	"cW": "res://core_v2/props/scaffold/ConnectorWalkway.tscn",
	"cR": "res://core_v2/props/scaffold/ConnectorRamp.tscn",
}

export var auto_generate: bool = false
export var generation_seed: int = 42
var generated_node_count: int = 0

func _ready():
	print("[ScaffoldWFC3DGenerator] _ready() called. auto_generate=", auto_generate)
	if auto_generate:
		generate(generation_seed)

func generate(seed_val: int = 42) -> Spatial:
	print("[ScaffoldWFC3DGenerator] generate() started with seed ", seed_val)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	var candidates = _generate_candidate_positions(seed_val)
	var placed = {}
	var domains = {}

	var all_types = ["sS", "sM", "sL", "sJ", "sD"]
	for pos in candidates:
		domains[pos] = all_types.duplicate()

	_apply_boundary_constraints(domains, candidates)

	while not _all_collapsed_rooms(placed, candidates):
		var pos = _min_entropy_room(domains, placed)
		var choice = _weighted_pick_room(domains[pos], rng)
		if choice == "": choice = "sS" # Fallback

		placed[pos] = choice
		domains[pos] = [choice]
		_propagate_room_constraints(domains, placed, pos)

	var edges = _connect_rooms(placed, rng)
	var network = _instance_network(placed, edges)
	add_child(network)
	generated_node_count = network.get_child_count()
	print("[ScaffoldWFC3DGenerator] Generated network with ", generated_node_count, " nodes.")
	return network

func _generate_candidate_positions(seed_val: int) -> Array:
	var positions = []
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	# Density: ~15-25 total rooms (LEVELS=4, so ~5-6 per level)
	var per_level = 5
	for l in range(LEVELS):
		for i in range(per_level):
			var x = rng.randf_range(10, VOLUME_X - 10)
			var y = l * LEVEL_HEIGHT + rng.randf_range(-5, 5)
			var z = rng.randf_range(10, VOLUME_Z - 10)
			positions.append(Vector3(x, y, z))

	return positions

func _all_collapsed_rooms(placed: Dictionary, candidates: Array) -> bool:
	return placed.size() == candidates.size()

func _min_entropy_room(domains: Dictionary, placed: Dictionary) -> Vector3:
	var min_pos = Vector3.ZERO
	var min_entropy = 9999

	for pos in domains:
		if placed.has(pos):
			continue
		var entropy = domains[pos].size()
		if entropy < min_entropy:
			min_entropy = entropy
			min_pos = pos

	return min_pos

func _weighted_pick_room(options: Array, rng: RandomNumberGenerator) -> String:
	if options.empty(): return ""
	if options.size() == 1: return options[0]

	var total_weight = 0.0
	var valid_options = []

	for opt in options:
		if opt == "": continue
		var weight = ROOM_WEIGHTS.get(opt, 1.0)
		total_weight += weight
		valid_options.append({"id": opt, "weight": weight})

	if total_weight == 0: return ""

	var r = rng.randf_range(0, total_weight)
	var current = 0.0
	for opt in valid_options:
		current += opt.weight
		if r <= current:
			return opt.id

	return valid_options[0].id

func _apply_boundary_constraints(domains: Dictionary, candidates: Array):
	for pos in candidates:
		pass

func _propagate_room_constraints(domains: Dictionary, placed: Dictionary, collapsed_pos: Vector3):
	var type = placed[collapsed_pos]

	for other_pos in domains:
		if placed.has(other_pos):
			continue

		var dist = collapsed_pos.distance_to(other_pos)
		if dist > 30.0:
			continue

		var current_domain = domains[other_pos]
		var new_domain = []

		for other_type in current_domain:
			if other_type == "":
				new_domain.append("")
				continue

			if _is_allowed_adjacency(type, other_type):
				new_domain.append(other_type)

		domains[other_pos] = new_domain

func _is_allowed_adjacency(type_a: String, type_b: String) -> bool:
	var rules = {
		"sS": ["sS", "sM", "sL", "sJ", "sD"],
		"sM": ["sS", "sM", "sL", "sJ"],
		"sL": ["sS", "sM", "sL", "sJ"],
		"sJ": ["sS", "sM", "sL", "sJ", "sD"],
		"sD": ["sS", "sJ"],
	}

	if rules.has(type_a):
		return type_b in rules[type_a]

	return true

func _connect_rooms(rooms: Dictionary, rng: RandomNumberGenerator) -> Array:
	var edges = []
	var candidates = rooms.keys()
	if candidates.empty(): return []

	var connected = [candidates[0]]
	var remaining = []
	for i in range(1, candidates.size()):
		remaining.append(candidates[i])

	while not remaining.empty():
		var best_dist = 99999.0
		var best_pair = []
		var best_idx = -1

		for i in range(remaining.size()):
			var p_rem = remaining[i]
			for p_con in connected:
				var d = p_rem.distance_to(p_con)
				if d < best_dist:
					best_dist = d
					best_pair = [p_con, p_rem]
					best_idx = i

		if best_idx != -1:
			var p_from = best_pair[0]
			var p_to = best_pair[1]
			var h_diff = abs(p_from.y - p_to.y)
			var type = _pick_connector(rooms[p_from], rooms[p_to], h_diff)

			edges.append({
				"from": p_from,
				"to": p_to,
				"type": type,
				"length": best_dist
			})
			connected.append(p_to)
			remaining.remove(best_idx)

	# Add some extra edges for cycles, avoiding redundant ones
	var extra_edges = 0
	var max_extra = 5
	var attempts = 0
	while extra_edges < max_extra and attempts < 20:
		attempts += 1
		var p1 = candidates[rng.randi() % candidates.size()]
		var p2 = candidates[rng.randi() % candidates.size()]
		if p1 == p2: continue

		# Check if already connected
		var already_connected = false
		for e in edges:
			if (e.from == p1 and e.to == p2) or (e.from == p2 and e.to == p1):
				already_connected = true
				break
		if already_connected: continue

		var dist = p1.distance_to(p2)
		if dist < 40.0:
			var h_diff = abs(p1.y - p2.y)
			var type = _pick_connector(rooms[p1], rooms[p2], h_diff)
			edges.append({
				"from": p1,
				"to": p2,
				"type": type,
				"length": dist
			})
			extra_edges += 1

	return edges

func _pick_connector(room_a: String, room_b: String, height_diff: float) -> String:
	if height_diff > 4.0:
		return "cR"
	return "cW"

func _instance_network(rooms: Dictionary, edges: Array) -> Spatial:
	var root = Spatial.new()
	root.name = "ScaffoldNetwork3D"

	for pos in rooms:
		var type = rooms[pos]
		var scene_path = ROOM_SCENES.get(type)
		if scene_path:
			var res = load(scene_path)
			if res:
				var instance = res.instance()
				instance.translation = pos
				root.add_child(instance)
				instance.name = "Room_" + type + "_" + str(str(pos).hash())

	for edge in edges:
		var type = edge.type
		var scene_path = CONNECTOR_SCENES.get(type)
		if scene_path:
			var res = load(scene_path)
			if res:
				var instance = res.instance()
				root.add_child(instance)

				var p_from = edge.from
				var p_to = edge.to
				instance.translation = p_from
				instance.look_at(p_to, Vector3.UP)

				var dist = p_from.distance_to(p_to)
				instance.scale.z = dist
				instance.name = "Conn_" + type + "_" + str(str(edge).hash())

	return root
