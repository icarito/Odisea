extends Spatial
# FD-324 F3 — streamer de industria procedural del Ark-Run.
# Colisión gruesa de TODOS los racimos una sola vez en _ready(): la física nunca
# depende del streaming. Pool cercano = malla low-poly unshaded + colisión fina.
# apply_gravity_mode() reacopla/falla rutas al encender (F5), determinista por hash.
const Catalog = preload("res://core_v2/levels/ark_run/ArkRunIndustryChunk.gd")
const Generator = preload("res://core_v2/levels/ark_run/ArkRunIndustryGenerator.gd")
export(int) var seed_value := Generator.SLICE_SEED
export(int) var sector_count := Generator.SECTOR_COUNT
export(int) var ring_slots := Generator.RING_SLOTS
export(bool) var build_coarse := true
export(bool) var build_fine := true
export(float) var stream_radius := 220.0
export(int) var pool_size := 10
export(int) var stream_interval_ticks := 8
export(NodePath) var stream_target_path := NodePath("")
var _clusters: Array = []
var _cluster_by_id: Dictionary = {}
var _coarse_root: Spatial = null
var _fine_root: Spatial = null
var _fine_pool: Dictionary = {}
var _gate_shapes: Dictionary = {}
var _route_state: Dictionary = {}
var _materials: Dictionary = {}
var _gravity_mode := Catalog.GRAVITY_CENTRIFUGAL
var _relinked_count := 0
var _blocked_count := 0
var _tick := 0
var _target = null

func _ready() -> void:
	_generate_clusters()
	if build_coarse: _build_coarse()
	if build_fine:
		_fine_root = Spatial.new()
		_fine_root.name = "FineDetail"
		add_child(_fine_root)
	apply_gravity_mode(_gravity_mode)
	_resolve_target()
	refresh_streaming()

func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % int(max(stream_interval_ticks, 1)) != 0: return
	if _target == null or not is_instance_valid(_target): _resolve_target()
	refresh_streaming()

# --- Consultas estables (F5 / tests) ---
func set_stream_target(node) -> void: _target = node
func get_coarse_body_count() -> int: return _coarse_root.get_child_count() if _coarse_root != null else 0
func get_fine_pool_size() -> int: return _fine_pool.size()
func get_route_state_summary() -> Dictionary:
	var keys := _route_state.keys()
	keys.sort()
	var h := 0
	for key in keys: h = (h * 31 + int(_route_state[key]["decision_hash"])) & 0x7fffffff
	return {"mode": _gravity_mode, "relinked": _relinked_count, "blocked": _blocked_count, "total": _route_state.size(), "hash": h}

# Reacopla/falla rutas al cambiar la gravedad (F5). No reconstruye colisión ni arte.
func apply_gravity_mode(mode: String) -> void:
	_gravity_mode = mode
	_relinked_count = 0
	_blocked_count = 0
	for cluster in _clusters:
		for conn in cluster["connectors"]:
			if bool(conn["connected"]): continue
			var key := _key(cluster["id"], conn["id"])
			var decision: Dictionary = Generator.evaluate_connection_relink(seed_value, str(cluster["id"]), str(conn["id"]), mode)
			_route_state[key] = decision
			if bool(decision["relinked"]): _relinked_count += 1
			else: _blocked_count += 1
			var gate = _gate_shapes.get(key)
			if gate != null and is_instance_valid(gate): gate.disabled = bool(decision["relinked"])

# --- Construcción ---
func _generate_clusters() -> void:
	_clusters.clear()
	_cluster_by_id.clear()
	for sector in range(int(max(sector_count, 1))):
		for ring in range(int(max(ring_slots, 1))):
			var cluster: Dictionary = Generator.generate_cluster(seed_value, sector, ring)
			_clusters.append(cluster)
			_cluster_by_id[str(cluster["id"])] = cluster
	_clusters.sort_custom(self, "_sort_by_id")

# Colisión gruesa estática: un StaticBody por racimo + compuertas de ruta.
func _build_coarse() -> void:
	_coarse_root = Spatial.new()
	_coarse_root.name = "CoarseCollision"
	add_child(_coarse_root)
	for cluster in _clusters:
		var body := StaticBody.new()
		body.name = "Coarse_" + str(cluster["id"])
		body.set_meta("cluster_id", str(cluster["id"]))
		var bounds: Dictionary = cluster["bounds"]
		var size: Vector3 = bounds["size"]
		var box := BoxShape.new(); box.extents = Vector3(max(size.x, 0.5), max(size.y, 0.5), max(size.z, 0.5)) * 0.5
		var shape := CollisionShape.new(); shape.name = "CoarseShape"; shape.shape = box
		body.add_child(shape)
		body.transform = Transform(Basis.IDENTITY, bounds["center"])
		for conn in cluster["connectors"]:
			if bool(conn["connected"]): continue
			var gate_box := BoxShape.new(); gate_box.extents = Vector3(1.2, 1.0, 1.2)
			var gate_shape := CollisionShape.new()
			gate_shape.name = "Gate_" + str(conn["chunk_id"]) + "_" + str(conn["local_id"])
			gate_shape.shape = gate_box; gate_shape.disabled = true
			gate_shape.transform = Transform(Basis.IDENTITY, Vector3(cluster["anchor"]) + cluster["basis"].xform(Vector3(conn["pos"])) - Vector3(bounds["center"]))
			body.add_child(gate_shape)
			_gate_shapes[_key(cluster["id"], conn["id"])] = gate_shape
		_coarse_root.add_child(body)

func _build_fine_cluster(cluster: Dictionary) -> Spatial:
	var root := Spatial.new()
	root.name = "Fine_" + str(cluster["id"])
	var body := StaticBody.new()
	body.name = "FineBody"
	root.add_child(body)
	for part in cluster["parts"]:
		var part_size: Vector3 = part["size"]
		var part_transform := Transform(part["rot"], part["pos"])
		var visual: Dictionary = Catalog.resolve_piece_visual(str(part["visual"]))
		var scene_path := str(visual.get("scene_path", ""))
		if scene_path != "" and ResourceLoader.exists(scene_path):
			var packed = load(scene_path)
			if packed is PackedScene:
				var instance = packed.instance(); instance.name = "Kit_" + str(part["piece"]).replace("/", "_")
				instance.transform = part_transform
				root.add_child(instance)
				continue
		var mesh_instance := MeshInstance.new()
		mesh_instance.name = "Mesh_" + str(part["piece"]).replace("/", "_")
		mesh_instance.mesh = _make_mesh(visual, part_size); mesh_instance.transform = part_transform
		root.add_child(mesh_instance)
		var box := BoxShape.new(); box.extents = part_size * 0.5
		var col := CollisionShape.new(); col.name = "Shape_" + str(part["piece"]).replace("/", "_")
		col.shape = box; col.transform = part_transform
		body.add_child(col)
	return root

func _make_mesh(visual: Dictionary, size: Vector3) -> Mesh:
	var mesh_path := str(visual.get("mesh_path", ""))
	if mesh_path != "" and ResourceLoader.exists(mesh_path):
		var res = load(mesh_path)
		if res is Mesh: return res
	var mesh := CubeMesh.new(); mesh.size = size; mesh.material = _material_for(visual)
	return mesh

func _material_for(visual: Dictionary) -> SpatialMaterial:
	var key := str(visual.get("key", "frame"))
	if _materials.has(key): return _materials[key]
	var color: Color = visual.get("color", Color(0.2, 0.6, 0.65))
	var material := SpatialMaterial.new()
	material.flags_unshaded = true; material.albedo_color = color
	material.emission_enabled = true; material.emission = color; material.emission_energy = 0.35
	_materials[key] = material
	return material

# --- Streaming acotado por cercanía (sólo detalle visual + colisión fina) ---
func refresh_streaming() -> void:
	if not build_fine or _fine_root == null: return
	var origin := Vector3.ZERO
	if _target != null and is_instance_valid(_target) and _target is Spatial: origin = _target.global_transform.origin
	var candidates := []
	for cluster in _clusters:
		var distance: float = cluster["anchor"].distance_to(origin)
		if distance <= stream_radius: candidates.append({"id": str(cluster["id"]), "distance": distance})
	candidates.sort_custom(self, "_sort_candidates")
	var wanted := {}
	for i in range(int(min(max(pool_size, 0), candidates.size()))): wanted[str(candidates[i]["id"])] = true
	for key in _fine_pool.keys():
		if wanted.has(str(key)): continue
		var node = _fine_pool[key]
		_fine_pool.erase(key)
		if node != null and is_instance_valid(node):
			if node.get_parent() != null: node.get_parent().remove_child(node)
			node.queue_free()
	for key in wanted.keys():
		if _fine_pool.has(key): continue
		var node: Spatial = _build_fine_cluster(_cluster_by_id[key])
		_fine_root.add_child(node)
		_fine_pool[key] = node

func _resolve_target() -> void:
	if stream_target_path != NodePath("") and has_node(stream_target_path):
		_target = get_node(stream_target_path)
		return
	if _target != null and is_instance_valid(_target): return
	var parent := get_parent()
	if parent != null: _target = parent.get_node_or_null("../Pilot")
	var players := get_tree().get_nodes_in_group("player")
	if _target == null and not players.empty(): _target = players[0]

func _key(cluster_id, connector_id) -> String: return str(cluster_id) + "|" + str(connector_id)
func _sort_by_id(a, b) -> bool: return str(a["id"]) < str(b["id"])
func _sort_candidates(a, b) -> bool:
	var da := float(a["distance"]); var db := float(b["distance"])
	if abs(da - db) > 0.001: return da < db
	return str(a["id"]) < str(b["id"])
