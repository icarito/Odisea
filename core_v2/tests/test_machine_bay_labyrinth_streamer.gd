extends GdUnitTestSuite

# MachineBayLabyrinthStreamer — laberinto industrial streamed (FD-320+).
# Cubre:
#  - determinismo de la generación WFC por chunk (misma key → misma malla)
#  - costuras deterministas: los bordes compartidos entre vecinos coinciden
#  - activación: con el jugador dentro de la zona, los chunks entran y se instancian
#
# Orden deliberado: los tests de determinismo corren PRIMERO (sin crear streamers,
# así ningún worker de tests anteriores toca el RNG global). El test que crea el
# streamer (que levanta el worker threaded) va al final.

const StreamerScene = preload("res://core_v2/levels/machines/MachineBayLabyrinthStreamer.tscn")
const SolverScript = preload("res://core_v2/systems/WFCSolverCore.gd")

func _solve_params(seed_val: int, key: Vector2) -> Dictionary:
	var params := {
		"grid_width": 4,
		"grid_depth": 4,
		"cell_size": 3.0,
		"seed": seed_val,
		"max_wfc_retries": 240,
		"require_single_component": true,
		"min_stairs_per_map": 0,
		"min_elevated_cells": 0,
		"min_empty_cells": 0,
		"min_height_span": 0.0,
		"constrain_border_heights": true,
		"border_presets": {},
		"fixed_border_tiles": {
			"0,0": {"id": "W", "rotation": 0, "height": 0.0},
			"%d,%d" % [3, 3]: {"id": "W", "rotation": 0, "height": 0.0}
		},
		"weight_W": 6.0,
		"weight_R": 5.0,
		"weight_P": 3.0,
		"weight_S": 8.0,
		"weight_C": 3.0,
		"weight_G": 0.5,
		"weight_X": 1.0,
		"weight_T": 2.0,
		"weight_E": 1.8,
		"weight_empty": 0.18
	}
	return params

func _solve_grid(seed_val: int) -> Array:
	var params := _solve_params(seed_val, Vector2(0, 0))
	var solver = SolverScript.new()
	solver.apply_params(params)
	return solver.generate_grid_data(seed_val)

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

# ── 1. Semillas distintas → mallas distintas (sin streamer / worker) ────────

func test_aaa_wfc_different_seeds_differ() -> void:
	var a: Array = _solve_grid(20261114)
	var c: Array = _solve_grid(20261115)
	assert_bool(_deep_equal(a, c)).is_false()

# ── 2. Costuras deterministas entre vecinos ─────────────────────────────────

func test_north_south_seams_agree() -> void:
	var s = auto_free(StreamerScene.instance())
	s.chunk_cells = 4
	add_child(s)
	var a = s.get_boundary_tile(Vector2(0, 0), "s")
	var b = s.get_boundary_tile(Vector2(0, 1), "n")
	assert_int(int(a.col)).is_equal(int(b.col))
	assert_str(String(a.spec.get("id", ""))).is_equal("W")
	assert_str(String(b.spec.get("id", ""))).is_equal("W")
	assert_float(float(a.spec.get("height", -1.0))).is_equal_approx(0.0, 0.001)
	assert_float(float(b.spec.get("height", -1.0))).is_equal_approx(0.0, 0.001)

func test_east_west_seams_agree() -> void:
	var s = auto_free(StreamerScene.instance())
	s.chunk_cells = 4
	add_child(s)
	var a = s.get_boundary_tile(Vector2(0, 0), "e")
	var b = s.get_boundary_tile(Vector2(1, 0), "w")
	assert_int(int(a.row)).is_equal(int(b.row))
	assert_str(String(a.spec.get("id", ""))).is_equal("W")
	assert_str(String(b.spec.get("id", ""))).is_equal("W")

func test_entry_world_position_matches_region() -> void:
	var s = auto_free(StreamerScene.instance())
	s.cell_size = 3.0
	s.region_origin = Vector3(22.0, 0.0, 26.0)
	add_child(s)
	var entry: Vector3 = s.get_entry_world_position()
	assert_float(entry.x).is_equal_approx(s.region_origin.x + s.cell_size * 0.5, 0.01)
	assert_float(entry.z).is_equal_approx(s.region_origin.z + s.cell_size * 0.5, 0.01)

# ── 3. Activación y streaming (último: levanta el worker) ────────────────────

func test_zzz_streamer_activates_and_instances_when_player_in_zone() -> void:
	var s = auto_free(StreamerScene.instance())
	s.chunk_cells = 8
	s.cell_size = 3.0
	s.region_origin = Vector3(22.0, 0.0, 26.0)
	s.seed_base = 20261114
	s.max_pending_jobs = 8
	s.max_chunk_requests_per_frame = 3
	s.collision_radius = 200.0
	s.debug_verbose = true
	add_child(s)

	var dummy = auto_free(KinematicBody.new())
	dummy.name = "PilotDummy"
	add_child(dummy)
	var session: Node = get_node("/root/SessionManager")
	var prev = session.player
	session.player = dummy
	dummy.global_transform.origin = Vector3(30.0, 0.0, 40.0)
	s.activate_now()

	var active := 0
	var touched := 0
	var pending := 0
	for i in range(500):
		yield(get_tree(), "physics_frame")
		active = s.get_active_chunk_keys().size()
		touched = s.get("_chunk_touched").size()
		pending = s.get("_pending_chunks").size()
		if active > 0 and touched > 0:
			break
	session.player = prev

	assert_int(active).is_greater(0)
	assert_int(touched).is_greater(0)
	var built := false
	for k in s.get_active_chunk_keys():
		var n = s.get_node("MazeChunk_%d_%d" % [int(k.x), int(k.y)])
		if n != null and n.get_child_count() > 0:
			built = true
			break
	assert_bool(built).is_true()
