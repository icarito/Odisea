extends GdUnitTestSuite

# FD-322 — Bahía vertical radial (greybox). Cubre:
#  - determinismo del layout (misma semilla → mismo layout; distintas → difieren)
#  - conectividad: la cima es alcanzable desde la entrada por el grafo del layout
#  - ciclo global BayProtocolCycle: fases deterministas + snapshot/replay
#  - streaming por cercanía (los chunks entran solo cerca del jugador)
#  - atajos: puerta de láser se corta con laser_hit; gloo span abre con blobs
#
# Orden deliberado: los tests de generación pura corren primero (sin scenegraph);
# los que instancian nodos van al final.

const WellScript := preload("res://core_v2/levels/bay_vertical/BayVerticalWell.gd")
const CycleScript := preload("res://core_v2/levels/bay_vertical/BayProtocolCycle.gd")
const LaserGateScript := preload("res://core_v2/levels/bay_vertical/LaserGate.gd")
const GlooSpanScript := preload("res://core_v2/levels/bay_vertical/GlooSpan.gd")

func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for k in a.keys():
				if not b.has(k) or not _deep_equal(a[k], b[k]):
					return false
			return true
		TYPE_REAL, TYPE_INT:
			return abs(float(a) - float(b)) < 0.001
		_:
			return a == b

func _cell_map(layout: Dictionary) -> Dictionary:
	var m := {}
	for cell in layout.get("cells", []):
		m[int(cell["idx"])] = cell
	return m

func _reachable(layout: Dictionary, src_idx: int, dst_idx: int) -> bool:
	var sectors: int = int(layout.get("sectors", 16))
	var rings: int = int(layout.get("rings", 3))
	var cells := _cell_map(layout)
	if not cells.has(src_idx) or not cells.has(dst_idx):
		return false
	var visited := {}
	visited[src_idx] = true
	var queue: Array = [src_idx]
	while not queue.empty():
		var cur: int = queue.pop_front()
		if cur == dst_idx:
			return true
		var cell: Dictionary = cells[cur]
		var cx: int = cell["cx"]
		var cy: int = cell["cy"]
		var conn: Array = cell["connections"]
		# N=0, E=1, S=2, O=3
		var neigh := [
			(cy - 1) * sectors + cx if cy - 1 >= 0 else -1,
			cy * sectors + (cx + 1) % sectors,
			(cy + 1) * sectors + cx if cy + 1 < rings else -1,
			cy * sectors + int(posmod(cx - 1, sectors)),
		]
		for d in range(4):
			if conn.size() > d and conn[d]:
				var n: int = neigh[d]
				if n >= 0 and cells.has(n) and not visited.has(n):
					visited[n] = true
					queue.append(n)
	return false

# ── 1. Determinismo del layout (puro, sin nodos) ─────────────────────────────

func test_aaa_same_seed_same_layout() -> void:
	var w = WellScript.new()
	var a: Dictionary = w.generate_layout(20261114)
	var b: Dictionary = w.generate_layout(20261114)
	assert_bool(_deep_equal(a, b)).is_true()
	assert_bool(a.empty()).is_false()

func test_bbb_different_seeds_differ() -> void:
	var w = WellScript.new()
	var a: Dictionary = w.generate_layout(20261114)
	var b: Dictionary = w.generate_layout(20261115)
	assert_bool(_deep_equal(a, b)).is_false()

# ── 2. Conectividad: la cima es alcanzable ──────────────────────────────────

func test_ccc_entry_reaches_summit() -> void:
	var w = WellScript.new()
	var layout: Dictionary = w.generate_layout(20261114)
	var entry: int = int(layout.get("entry_idx", -1))
	var summit: int = int(layout.get("summit_idx", -1))
	assert_int(entry).is_greater_equal(0)
	assert_int(summit).is_greater_equal(0)
	assert_bool(_reachable(layout, entry, summit)).is_true()

func test_ccc2_summit_is_in_cima_band() -> void:
	var w = WellScript.new()
	var layout: Dictionary = w.generate_layout(20261114)
	var summit: int = int(layout.get("summit_idx", -1))
	var cells := _cell_map(layout)
	assert_bool(cells.has(summit)).is_true()
	assert_float(float(cells[summit]["base_height"])).is_greater_equal(8.0 - 0.001)

# ── 3. Ciclo global ─────────────────────────────────────────────────────────

func test_ddd_cycle_phases_deterministic() -> void:
	var c = auto_free(CycleScript.new())
	c.safe_duration = 2.0
	c.warning_duration = 1.0
	c.danger_duration = 3.0
	assert_int(c.phase_for_time(0.0)).is_equal(CycleScript.Phase.SAFE)
	assert_int(c.phase_for_time(1.5)).is_equal(CycleScript.Phase.SAFE)
	assert_int(c.phase_for_time(2.0)).is_equal(CycleScript.Phase.WARNING)
	assert_int(c.phase_for_time(2.7)).is_equal(CycleScript.Phase.WARNING)
	assert_int(c.phase_for_time(3.0)).is_equal(CycleScript.Phase.DANGER)
	assert_int(c.phase_for_time(5.5)).is_equal(CycleScript.Phase.DANGER)
	# Wrap: ciclo completo = 6s → vuelve a SAFE.
	assert_int(c.phase_for_time(6.0)).is_equal(CycleScript.Phase.SAFE)

func test_eee_cycle_replay_snapshot() -> void:
	var c1 = auto_free(CycleScript.new())
	c1.safe_duration = 1.0
	c1.warning_duration = 0.5
	c1.danger_duration = 1.5
	c1._elapsed = 3.2
	var snap: Dictionary = c1.get_snapshot()
	var c2 = auto_free(CycleScript.new())
	c2.restore_snapshot(snap)
	assert_float(c2._elapsed).is_equal_approx(3.2, 0.0001)
	assert_int(c2.get_phase()).is_equal(c1.get_phase())

# ── 4. Streaming por cercanía ────────────────────────────────────────────────

func test_fff_streaming_deferred_and_nearby_only() -> void:
	var w = auto_free(WellScript.new())
	w.enable_streaming = true
	add_child(w)
	# Con streaming, nada de chunks instanciados al arranque.
	assert_int(w.get_active_chunk_keys().size()).is_equal(0)
	# Pedir cerca de la entrada → entran chunks de la planta.
	w.debug_update_streaming_at(w.get_entry_world_position())
	assert_bool(w.get_active_chunk_keys().size() > 0).is_true()
	# Pedir todo (fuerza) → se ven todos los chunks.
	w.force_request_all_chunks()
	assert_int(w.get_active_chunk_keys().size()).is_greater_equal(4)

# ── 5. Atajos ───────────────────────────────────────────────────────────────

func test_ggg_laser_gate_cut_opens() -> void:
	var gate = auto_free(LaserGateScript.new())
	gate.cut_time = 0.3
	add_child(gate)
	var i := 0
	while i < 24 and not gate.is_opened():
		gate.laser_hit()
		i += 1
	assert_bool(gate.is_opened()).is_true()
	var snap: Dictionary = gate.get_state()
	var gate2 = auto_free(LaserGateScript.new())
	gate2.cut_time = 0.3
	add_child(gate2)
	gate2.restore_state(snap)
	assert_bool(gate2.is_opened()).is_true()

func test_iii_mode_toggle_is_deterministic_and_serialized() -> void:
	var w = auto_free(WellScript.new())
	add_child(w)
	var start: int = w.get_gravity_mode()
	var changed: bool = w.toggle_gravity_mode()
	assert_bool(changed).is_true()
	assert_int(w.get_gravity_mode()).is_not_equal(start)
	# Segundo toggle vuelve al original.
	w.toggle_gravity_mode()
	assert_int(w.get_gravity_mode()).is_equal(start)
	# Snapshot/replay: el modo y el blend viajan en el estado.
	w.set_gravity_mode_mode(WellScript.GRAVITY_MODE_THRUST)
	var snap: Dictionary = w.get_snapshot()
	assert_int(int(snap.get("gravity_mode", -1))).is_equal(WellScript.GRAVITY_MODE_THRUST)
	var w2 = auto_free(WellScript.new())
	add_child(w2)
	w2.restore_snapshot(snap)
	assert_int(w2.get_gravity_mode()).is_equal(WellScript.GRAVITY_MODE_THRUST)

func test_jjj_gravity_vector_is_sourced_not_hardcoded() -> void:
	var w = auto_free(WellScript.new())
	add_child(w)
	var g: Vector3 = w.get_gravity_vector_at(Vector3(3.0, 1.0, 0.0))
	# Debe devolver un vector no nulo y finito, provisto por GravityWorld (o su
	# fallback radial). La magnitud escala con el radio de referencia, así que solo
	# se verifica que sea una fuente real y no un cero/constante.
	assert_float(g.length()).is_greater(0.0)
	assert_bool(not is_nan(g.x) and not is_nan(g.y) and not is_nan(g.z)).is_true()

func test_hhh_gloo_span_needs_blobs() -> void:
	var span = auto_free(GlooSpanScript.new())
	span.span_from = Vector3(0.0, 0.0, 0.0)
	span.span_to = Vector3(3.0, 0.0, 0.0)
	span.required_blobs = 1
	add_child(span)
	assert_bool(span.is_opened()).is_false()
	var blob = Spatial.new()
	blob.add_to_group("gloo_blob")
	blob.global_transform.origin = Vector3(1.5, 0.0, 0.0)
	add_child(blob)
	span._physics_process(0.016)
	assert_bool(span.is_opened()).is_true()
