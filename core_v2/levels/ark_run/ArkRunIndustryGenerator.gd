extends Reference
# FD-324 F3 — generador determinista de industria procedural del Ark-Run.
# Hash propio por (semilla, coord); sin randf()/RNG global. El orden de carga no
# altera el resultado. Racimos en la banda [R_SPIRAL, R_HULL], z ∈ [-1000, 1000].

const Catalog = preload("res://core_v2/levels/ark_run/ArkRunIndustryChunk.gd")
const SLICE_SEED := 32401
const SLICE_LENGTH := 2000.0
const SLICE_HALF := 1000.0
const R_SPIRAL := 260.0
const R_HULL := 340.0
const INDUSTRY_MARGIN := 12.0
const SECTOR_COUNT := 12
const RING_SLOTS := 8
const RELINK_PERCENT := 720
const CORNERS := [
	Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(-1, 1, 1),
	Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(1, 1, 1),
]

# Racimo: id, anchor/basis, piezas, conectores, links, bounds y hash de orden estable.
static func generate_cluster(seed_value: int, sector_index: int, ring_slot: int) -> Dictionary:
	var h0 := _hash3(seed_value, sector_index, ring_slot)
	var angle := TAU * float(sector_index) / float(SECTOR_COUNT) + (_unit(h0, 1) - 0.5) * 0.24
	var z := -SLICE_HALF + INDUSTRY_MARGIN
	z += (SLICE_LENGTH - 2.0 * INDUSTRY_MARGIN) * float(ring_slot) / float(max(RING_SLOTS - 1, 1))
	z = clamp(z + (_unit(h0, 2) - 0.5) * 32.0, -SLICE_HALF + INDUSTRY_MARGIN, SLICE_HALF - INDUSTRY_MARGIN)
	var r_min := R_SPIRAL + INDUSTRY_MARGIN
	var radius := r_min + _unit(h0, 3) * (R_HULL - INDUSTRY_MARGIN - r_min)
	var radial := Vector3(cos(angle), sin(angle), 0.0)
	var basis := Basis(radial, Vector3(-sin(angle), cos(angle), 0.0), Vector3(0, 0, 1))
	var anchor := radial * radius + Vector3(0, 0, z)
	var result := {
		"id": "cluster_s%02d_r%02d" % [sector_index, ring_slot], "seed": seed_value,
		"sector_index": sector_index, "ring_slot": ring_slot,
		"anchor": anchor, "basis": basis, "gravity_mode": Catalog.GRAVITY_CENTRIFUGAL,
		"pieces": [], "parts": [], "connectors": [], "links": [],
	}
	var order: Array = Catalog.chunk_ids()
	var state := h0
	for i in range(order.size() - 1, 0, -1):
		state = _next_lcg(state)
		var j := int(state % (i + 1))
		var tmp = order[i]; order[i] = order[j]; order[j] = tmp
	var used := []
	for slot in range(1 + int(h0 % 3)):
		var chunk_id := ""; var offset := Vector3.ZERO
		var mate_free: Dictionary = {}; var mate_cand: Dictionary = {}
		for candidate in order:
			if used.has(candidate): continue
			var chunk: Dictionary = Catalog.get_chunk(str(candidate))
			if chunk.empty(): continue
			if slot == 0:
				if _chunk_fits(chunk, Vector3.ZERO, basis, anchor):
					chunk_id = str(candidate)
					break
				continue
			var mate := _find_mate(result, chunk)
			if mate.empty(): continue
			var candidate_offset: Vector3 = mate["free"]["pos"] - mate["cand"]["local_pos"]
			if _chunk_fits(chunk, candidate_offset, basis, anchor):
				chunk_id = str(candidate); offset = candidate_offset
				mate_free = mate["free"]; mate_cand = mate["cand"]
				break
		if chunk_id == "": break
		_append_chunk(result, chunk_id, slot, offset)
		used.append(chunk_id)
		if slot > 0 and not mate_free.empty():
			_connect(result, str(mate_free["id"]), chunk_id + ":" + str(mate_cand["id"]))
	result["bounds"] = _bounds(result)
	result["hash"] = cluster_hash(result)
	return result

# Decisión estática determinista (decisión #9). F5 la invoca al encender: un
# conector incompatible falla siempre; uno compatible reacopla o falla por hash.
static func evaluate_connection_relink(seed_value: int, cluster_id: String, connector_id: String, target_gravity_mode: String) -> Dictionary:
	var pieces := connector_id.split(":")
	var chunk_id: String = str(pieces[0]) if pieces.size() > 0 else ""
	var local_id: String = str(pieces[1]) if pieces.size() > 1 else ""
	var conn := Catalog.find_connector(chunk_id, local_id)
	var supported := not conn.empty() and Catalog.connector_supports_modes(conn.get("gravity_modes", []), target_gravity_mode)
	var h := _hash3(seed_value ^ _hash_string(cluster_id), _hash_string(connector_id), _mode_index(target_gravity_mode))
	var relinked := supported and (h % 1000) < RELINK_PERCENT
	var reason := "gravity_incompatible"
	if supported: reason = "relinked" if relinked else "static_failure"
	return {
		"cluster_id": cluster_id, "connector_id": connector_id,
		"target_gravity_mode": target_gravity_mode, "gravity_supported": supported,
		"relinked": relinked, "blocked": not relinked,
		"route_state": "open" if relinked else "blocked",
		"reason": reason, "decision_hash": h,
	}

static func cluster_hash(cluster: Dictionary) -> int:
	return _hash_string(_signature(cluster))

static func _append_chunk(cluster: Dictionary, chunk_id: String, slot: int, offset: Vector3) -> void:
	var chunk: Dictionary = Catalog.get_chunk(chunk_id)
	var piece_name := "p%02d" % slot
	cluster["pieces"].append({"chunk_id": chunk_id, "piece": piece_name, "offset": offset, "size": chunk["size"]})
	for p in chunk.get("pieces", []):
		cluster["parts"].append({
			"piece": piece_name + "/" + str(p["key"]), "chunk_id": chunk_id,
			"visual": str(p["visual"]), "size": p["size"], "rot": cluster["basis"],
			"pos": cluster["anchor"] + cluster["basis"].xform(Vector3(p["pos"]) + offset),
		})
	for c in chunk.get("connectors", []):
		cluster["connectors"].append({
			"id": chunk_id + ":" + str(c["id"]), "chunk_id": chunk_id,
			"local_id": str(c["id"]), "piece": piece_name,
			"pos": Vector3(c["local_pos"]) + offset, "dir": Vector3(c["local_dir"]),
			"gravity_modes": c["gravity_modes"].duplicate(), "connected": false, "peers": [],
		})

static func _find_mate(cluster: Dictionary, chunk: Dictionary) -> Dictionary:
	for free in cluster["connectors"]:
		if bool(free["connected"]) or not Catalog.connector_supports_modes(free["gravity_modes"], Catalog.GRAVITY_CENTRIFUGAL):
			continue
		for cand in chunk.get("connectors", []):
			if Catalog.connector_supports_modes(cand["gravity_modes"], Catalog.GRAVITY_CENTRIFUGAL) \
					and free["dir"].dot(Vector3(cand["local_dir"])) <= -0.99:
				return {"free": free, "cand": cand}
	return {}

static func _connect(cluster: Dictionary, free_id: String, new_id: String) -> void:
	for c in cluster["connectors"]:
		if str(c["id"]) == free_id or str(c["id"]) == new_id:
			c["connected"] = true
			c["peers"].append(new_id if str(c["id"]) == free_id else free_id)
	cluster["links"].append({"from": free_id, "to": new_id, "gravity_mode": Catalog.GRAVITY_CENTRIFUGAL})

static func _chunk_fits(chunk: Dictionary, offset: Vector3, basis: Basis, anchor: Vector3) -> bool:
	for piece in chunk.get("pieces", []):
		var half: Vector3 = piece["size"] * 0.5
		for corner_sign in CORNERS:
			var local: Vector3 = Vector3(piece["pos"]) + offset + Vector3(corner_sign.x * half.x, corner_sign.y * half.y, corner_sign.z * half.z)
			var world: Vector3 = anchor + basis.xform(local)
			var radius := sqrt(world.x * world.x + world.y * world.y)
			if radius < R_SPIRAL + 1.0 or radius > R_HULL - 1.0 or abs(world.z) > SLICE_HALF - 1.0:
				return false
	return true

static func _bounds(cluster: Dictionary) -> Dictionary:
	if cluster["parts"].empty(): return {"center": cluster["anchor"], "size": Vector3.ZERO}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for part in cluster["parts"]:
		var half: Vector3 = part["size"] * 0.5
		for corner_sign in CORNERS:
			var c: Vector3 = part["pos"] + part["rot"].xform(Vector3(corner_sign.x * half.x, corner_sign.y * half.y, corner_sign.z * half.z))
			lo = Vector3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z))
			hi = Vector3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
	return {"center": (lo + hi) * 0.5, "size": hi - lo}

static func _signature(cluster: Dictionary) -> String:
	var parts := [str(cluster["id"]), _vec(cluster["anchor"]),
		_vec(cluster["basis"].xform(Vector3(1, 0, 0))), _vec(cluster["basis"].xform(Vector3(0, 1, 0)))]
	for p in cluster["pieces"]:
		parts.append("%s@%s/%s" % [str(p["chunk_id"]), _vec(p["offset"]), _vec(p["size"])])
	var conns := []
	for c in cluster["connectors"]:
		conns.append("%s|%s|%s|%s|%s|%s" % [str(c["id"]), _vec(c["pos"]), _vec(c["dir"]),
			",".join(c["gravity_modes"]), str(c["connected"]), ",".join(c["peers"])])
	conns.sort()
	var links := []
	for l in cluster["links"]:
		links.append("%s>%s:%s" % [str(l["from"]), str(l["to"]), str(l["gravity_mode"])])
	links.sort()
	return "|".join(parts) + ";" + ";".join(conns) + ";" + ";".join(links)

static func _vec(v: Vector3) -> String:
	return "%.5f,%.5f,%.5f" % [v.x, v.y, v.z]

static func _hash_string(text: String) -> int:
	var h := 2166136261
	var bytes: PoolByteArray = text.to_utf8()
	for i in range(bytes.size()):
		h = (h ^ int(bytes[i])) & 0x7fffffff; h = (h * 16777619) & 0x7fffffff
	return h

static func _hash3(seed_value: int, a: int, b: int) -> int:
	var h := (seed_value * 2654435761) & 0x7fffffff
	h = (h ^ (a * 1103515245)) & 0x7fffffff; h = (h ^ (b * 12345)) & 0x7fffffff
	h = (h * 1103515245 + 12345) & 0x7fffffff; h = (h ^ (h >> 15)) & 0x7fffffff
	return (h * 1103515245 + 12345) & 0x7fffffff

static func _next_lcg(state: int) -> int:
	return (state * 1103515245 + 12345) & 0x7fffffff

static func _unit(h: int, salt: int) -> float:
	return float(_hash3(h, salt, 0x9E37) & 0xffff) / 65535.0

static func _mode_index(mode: String) -> int:
	if mode == Catalog.GRAVITY_CENTRIFUGAL: return 0
	if mode == Catalog.GRAVITY_AXIAL: return 1
	return 2 if mode == Catalog.GRAVITY_BOTH else 3
