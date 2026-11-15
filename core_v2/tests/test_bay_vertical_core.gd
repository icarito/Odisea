extends GdUnitTestSuite

# FD-322 / pista E — Bahía radial centrífuga como banco de pruebas del Transit-Run.
#
# Cubre: ruta principal como PARKOUR (SprintGap + RhythmSteps, dentro del 80 % del
# alcance con el g_eff(r) del anillo), desvíos curados OPCIONALES con su lenguaje
# visual, el cambio de modo que reorienta la geometría con blend acotado, la
# entrada/salida seamless reales, el marcador de slice completado y la validación
# de la ruta principal por semilla con `FlowRouteValidator`.

const ScenePacked := preload("res://core_v2/levels/bay_vertical/BayVertical.tscn")
const RotatorScript := preload("res://core_v2/levels/bay_vertical/BayCylinderRotator.gd")
const LevelScript := preload("res://core_v2/levels/bay_vertical/BayVerticalLevel.gd")
const BufferScript := preload("res://core_v2/levels/bay_vertical/BayTransitionBuffer.gd")
const RingHubLightStateScript := preload("res://core_v2/levels/RingHubLightState.gd")
const FlowScript := preload("res://core_v2/levels/bay_vertical/BayTransitFlow.gd")
const GravityMountScript := preload("res://core_v2/levels/bay_vertical/BayGravityMount.gd")
const ValidatorScript := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")
const FlowMetricsScript := preload("res://core_v2/systems/flow/FlowMetrics.gd")

const ENTRY_SPAWN_ID := "bay_vertical_entry"
const RETURN_SPAWN_ID := "bay_vertical_return"
const RINGHUB_SCENE := "res://core_v2/levels/RingHub_Level.tscn"
const BAY_SCENE := "res://core_v2/levels/bay_vertical/BayVertical.tscn"

# ── Presupuesto de flow (FlowMetrics + g_eff del anillo) ─────────────────────

func test_flow_budget_uses_measured_player_physics() -> void:
	var flow = auto_free(FlowScript.new())
	# g_eff del anillo en la superficie: la ruta se calibra ahí (peor caso).
	flow.configure_ring(sqrt(14.0 / 48.0), 48.0)
	assert_float(flow.g_eff(48.0)).is_equal_approx(14.0, 0.2)
	# Con el tick MÁS BAJO (30 Hz) el contrato mide H_max ≈ 3.76 m y D_max ≈ 10.1 m.
	assert_float(flow.h_max(48.0)).is_equal_approx(3.74, 0.10)
	assert_float(flow.d_max(48.0, 0.0)).is_equal_approx(10.12, 0.15)
	# Y el hueco principal queda dentro de la banda 70-80 % del alcance.
	var limit: float = flow.main_gap(48.0, 0.0)
	assert_float(limit).is_greater_equal(0.70 * flow.d_max(48.0, 0.0) - 0.01)
	assert_float(limit).is_less_equal(0.80 * flow.d_max(48.0, 0.0) + 0.01)

func test_flow_sizes_grow_as_g_eff_drops_toward_axis() -> void:
	var flow = auto_free(FlowScript.new())
	flow.configure_ring(sqrt(14.0 / 48.0), 48.0)
	# Cerca del eje g_eff cae (g = ω²·r) y el alcance CRECE; el nivel recorta el
	# hueco contra el límite de la superficie para no volverse absurdo.
	assert_float(flow.g_eff(8.0)).is_less(flow.g_eff(48.0))
	assert_float(flow.d_max(8.0, 0.0)).is_greater(flow.d_max(48.0, 0.0))

func test_flow_metrics_for_validator() -> void:
	var flow = auto_free(FlowScript.new())
	var m: Dictionary = flow.metrics_for_g(14.0)
	for key in ["g", "v_run", "v_jump", "tick", "main_threshold", "optional_min", "optional_max"]:
		assert_bool(m.has(key)).is_true()
	assert_float(float(m["g"])).is_equal_approx(14.0, 0.001)
	assert_float(float(m["tick"])).is_equal_approx(1.0 / 30.0, 0.0001)
	assert_float(float(m["v_run"])).is_equal_approx(FlowMetricsScript.from_scene().run_speed(), 0.01)

# ── Ruta principal = parkour (SprintGap + RhythmSteps) ───────────────────────

func test_route_is_parkour_with_both_chunk_kinds() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	assert_object(content).is_not_null()
	assert_int(content.get_platform_count()).is_greater(8)
	# El contrato pide SprintGap y RhythmSteps en la ruta principal.
	assert_bool(content.has_hop_kind("SprintGap")).is_true()
	assert_bool(content.has_hop_kind("RhythmSteps")).is_true()

func test_main_route_hops_are_within_flow_limits() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var flow = content.get_flow()
	var route: Array = content.get_route_points()
	var hops: Array = content.get_route_hops()
	assert_int(hops.size()).is_greater(6)
	for i in range(hops.size()):
		var h: Dictionary = hops[i]
		var y: float = float(route[i]["flat"].y)
		var g: float = flow.g_eff(flow.radius_at(y))
		var h_max: float = flow.h_max(g)
		var d_max: float = flow.d_max(g, float(h["dh"]))
		# Ningún salto de la ruta principal pasa el techo del 80 % (INV-1).
		assert_float(float(h["dh"])).is_less_equal(0.80 * h_max + 0.02)
		assert_float(float(h["gap"])).is_less_equal(0.80 * d_max + 0.05)
		# RhythmSteps exige cadencia corta; SprintGap es el cruce largo.
		if String(h["kind"]) == "RhythmSteps":
			assert_float(float(h["gap"])).is_less_equal(0.60 * d_max + 0.05)
		else:
			assert_float(float(h["dh"])).is_equal_approx(0.0, 0.001)

func test_route_climbs_toward_axis() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var pts: Array = content.get_route_points()
	assert_int(pts.size()).is_greater(8)
	var first: Vector3 = pts[0]["flat"]
	var last: Vector3 = pts[pts.size() - 1]["flat"]
	# "Subir = ir hacia el eje": el recorrido gana altura radial.
	assert_float(last.y).is_greater(first.y + 15.0)
	var base_radius: float = float(level.get_node("CylinderRotator").base_radius)
	assert_float(base_radius - last.y).is_less(base_radius * 0.5)

func test_main_route_has_no_puzzle_blocker() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	# INV-3: ni herramientas ni sockets curados en la ruta principal.
	assert_bool(content.main_route_has_puzzle_blocker()).is_false()
	var kinds: Array = content.get_route_kinds()
	for k in kinds:
		assert_bool(k == "SprintGap" or k == "RhythmSteps").is_true()

func test_main_route_gaps_within_surface_limit() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var limit: float = content.get_main_route_gap_limit()
	assert_float(limit).is_greater(0.0)
	var gaps: Array = content.get_main_route_gaps()
	assert_int(gaps.size()).is_greater(0)
	for g in gaps:
		assert_float(float(g)).is_less_equal(limit * 1.05)

func test_main_route_validates_per_seed() -> void:
	# N semillas: la ruta principal debe validar en todas (solo saltos dentro del
	# umbral main, sin herramientas ni sockets) con el validador del contrato.
	var seeds := [1, 3, 7, 11, 42, 77, 101, 1337, 4242, 20261114]
	for seed_val in seeds:
		var level = auto_free(ScenePacked.instance())
		var content = level.get_node_or_null("BayContent")
		content.generation_seed = seed_val
		add_child(level)
		var result: Dictionary = content.validate_main_route()
		assert_bool(result.has("valid_main_route")).is_true()
		assert_bool(bool(result["valid_main_route"])).is_true()
		var critical: Dictionary = result.get("critical_main_edge", {})
		if not critical.empty():
			assert_float(float(critical.get("demand_ratio", 99.0))).is_less_equal(0.80 + 0.001)
		level.queue_free()
		yield(get_tree(), "idle_frame")

func test_ring_calibration_over_many_seeds() -> void:
	# Calibración del anillo: 64 semillas, el ritmo del parkour varía por partida
	# y en TODAS la ruta principal valida sin pasar el techo del contrato (80 %).
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var seeds: Array = []
	for i in range(64):
		seeds.append(1 + i * 7919)
	var report: Array = content.calibration_report(seeds)
	assert_int(report.size()).is_equal(64)
	var worst := 0.0
	var invalid := 0
	var cycles := {}
	for entry in report:
		if not bool(entry["valid"]):
			invalid += 1
		worst = max(worst, float(entry["worst_demand"]))
		cycles[int(entry["cycle"])] = true
	assert_int(invalid).is_equal(0)
	assert_float(worst).is_less_equal(0.80 + 0.001)
	# El patrón NO está fijo: hay más de un ciclo de ritmo entre semillas.
	assert_int(cycles.keys().size()).is_greater(1)
	# Y la ruta vuelve a la semilla original tras calibrar.
	assert_int(content.get_platform_count()).is_greater(8)

# ── Desvíos curados opcionales con recompensa cinética ──────────────────────

func test_shortcuts_are_optional_and_labeled() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var labels: Array = content.get_socket_labels()
	assert_bool(labels.has("CuratedSocket")).is_true()
	assert_bool(labels.has("GlooClimb")).is_true()
	assert_bool(labels.has("MagRail")).is_true()
	var rewards: Array = content.get_socket_rewards()
	assert_int(rewards.size()).is_equal(labels.size())
	# El GlooClimb (herramienta) NUNCA está en la ruta principal.
	assert_bool(content.has_hop_kind("GlooClimb")).is_false()
	assert_bool(content.has_hop_kind("MagRail")).is_false()
	# Hay una cornisa/mantle como recompensa de desvío.
	assert_bool(rewards.has("ledge")).is_true()
	assert_object(content.get_shortcuts()).is_not_null()

func test_shortcuts_use_cold_light_and_stripes() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	# La ruta principal es luz cálida; los atajos, luz fría + franjas.
	var acc := [0, 0, 0]  # [cálidas, frías, franjas emisivas]
	for node in content.get_children():
		_collect_light_and_stripes(node, acc)
	assert_int(int(acc[1])).is_greater(0)
	assert_int(int(acc[2])).is_greater(0)

func _collect_light_and_stripes(node: Node, acc: Array) -> void:
	if node is Light:
		var c: Color = node.light_color
		if c.b > c.r and c.b > 0.6:
			acc[1] = int(acc[1]) + 1
		elif c.r > 0.85 and c.b < 0.7:
			acc[0] = int(acc[0]) + 1
	if node is MeshInstance:
		var mat = node.material_override
		if mat != null and "emission_enabled" in mat and bool(mat.emission_enabled):
			acc[2] = int(acc[2]) + 1
	for c in node.get_children():
		_collect_light_and_stripes(c, acc)

# ── Modo: reorienta la geometría con blend acotado ──────────────────────────

func test_rotator_consumes_spiral_blend() -> void:
	var r = auto_free(RotatorScript.new())
	r.base_radius = 48.0
	add_child(r)
	r._register_mode_driver()
	var flat := Vector3(24.0, 0.0, 0.0)
	r.spiral_blend = 1.0
	var curved: Transform = r.project_flat_point(flat)
	r.spiral_blend = 0.0
	var flatter: Transform = r.project_flat_point(flat)
	assert_float(flatter.origin.x).is_equal_approx(24.0, 0.01)
	assert_float(flatter.origin.y).is_equal_approx(0.0, 0.01)
	assert_float(curved.origin.y).is_greater(1.0)

func test_rotator_registers_with_gravity_world() -> void:
	var gw = get_node_or_null("/root/GravityWorld")
	assert_object(gw).is_not_null()
	var r = auto_free(RotatorScript.new())
	r.base_radius = 48.0
	add_child(r)
	r._register_mode_driver()
	assert_bool(gw.get_rotator() == r).is_true()
	gw.set_spiral_blend(0.0)
	assert_float(r.get_spiral_blend()).is_equal_approx(0.0, 0.001)
	gw.set_spiral_blend(1.0)
	assert_float(r.get_spiral_blend()).is_equal_approx(1.0, 0.001)

func test_mode_switch_blend_is_bounded_per_frame() -> void:
	var mount = auto_free(GravityMountScript.new())
	add_child(mount)
	assert_float(mount.get_gravity_blend()).is_equal_approx(1.0, 0.0001)
	assert_bool(mount.toggle_gravity_mode()).is_true()
	mount._physics_process(0.016)
	var after_one: float = mount.get_gravity_blend()
	assert_float(after_one).is_less(1.0)
	assert_float(after_one).is_greater(0.9)
	var steps := 0
	while mount.is_blending() and steps < 600:
		mount._physics_process(0.016)
		steps += 1
	assert_bool(mount.is_blending()).is_false()
	assert_float(mount.get_gravity_blend()).is_equal_approx(0.0, 0.0001)

# ── Entrada / salida reales + cierre de slice ───────────────────────────────

func test_scene_declares_real_entry_spawn() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var spawn = level.get_node_or_null("SpawnPointV2")
	assert_object(spawn).is_not_null()
	assert_str(String(spawn.get("spawn_id"))).is_equal(ENTRY_SPAWN_ID)

func test_buffers_target_real_scene_with_level_params() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	for name in ["EntryBuffer", "ExitBuffer"]:
		var buf = level.get_node_or_null(name)
		assert_object(buf).is_not_null()
		assert_str(String(buf.target_scene)).is_equal(RINGHUB_SCENE)
		assert_bool(buf.level_path.is_empty()).is_false()
		var target: Dictionary = buf.get_transition_target()
		assert_str(String(target.get("spawn_id"))).is_equal(RETURN_SPAWN_ID)

func test_ringhub_declares_valid_return_spawn() -> void:
	# El `spawn_id` declarado por la salida debe EXISTIR en RingHub (grafo recorrible).
	var hub = load(RINGHUB_SCENE)
	assert_object(hub).is_not_null()
	var hub_scene = hub.instance()
	var spawn = hub_scene.get_node_or_null("Hub/BayVerticalReturnSpawn")
	assert_object(spawn).is_not_null()
	assert_str(String(spawn.get("spawn_id"))).is_equal(RETURN_SPAWN_ID)
	# Y el hub tiene el pedestal que abre la bahía radial.
	assert_object(hub_scene.get_node_or_null("Hub/PedestalBayVertical")).is_not_null()
	hub_scene.free()

func test_ringhub_light_state_enters_radial_bay() -> void:
	var ls = auto_free(RingHubLightStateScript.new())
	assert_str(String(ls.bay_vertical_scene_path)).is_equal(BAY_SCENE)
	assert_str(String(ls.bay_vertical_spawn_id)).is_equal(ENTRY_SPAWN_ID)
	assert_bool(ls.has_method("enter_bay_vertical")).is_true()

func test_level_return_params_keep_current_state_with_valid_spawn() -> void:
	var lvl = auto_free(LevelScript.new())
	add_child(lvl)
	lvl._ringhub_return_state = {"wakeup": {"x": 1}, "light_state": {"lit": true},
		"player_snapshot": {"position": Vector3(1.0, 2.0, 3.0)}}
	var params: Dictionary = lvl.build_ringhub_params()
	assert_str(String(params.get("transition"))).is_equal("seamless")
	# Conserva el estado ACTUAL: no restaura el snapshot viejo del hub.
	assert_bool(params.get("preserve_player_state")).is_true()
	var sd: Dictionary = params.get("state_data", {})
	assert_bool(sd.has("player_snapshot")).is_false()
	# Y declara un destino REAL y recorrible.
	assert_str(String(params.get("target_spawn_id"))).is_equal(RETURN_SPAWN_ID)
	assert_str(String(sd.get("target_airlock_path"))).is_equal(lvl.ringhub_airlock_path)

func test_summit_exit_completes_slice() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var lvl = level.get_node_or_null("BayVerticalLevel")
	var content = level.get_node_or_null("BayContent")
	var exit_buf = level.get_node_or_null("ExitBuffer")
	assert_bool(exit_buf.completes_slice).is_true()
	assert_bool(content.is_slice_completed()).is_false()
	var fired := [false]
	content.connect("slice_completed", self, "_on_slice", [fired])
	assert_bool(lvl.complete_slice()).is_true()
	assert_bool(content.is_slice_completed()).is_true()
	assert_bool(fired[0]).is_true()

func _on_slice(fired: Array) -> void:
	fired[0] = true

# ── Contenido sobre el stream + ciclo con consumidor ────────────────────────

func test_cycle_has_real_consumer() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var cycle = level.get_node_or_null("BayProtocolCycle")
	assert_object(cycle).is_not_null()
	assert_bool(cycle.is_connected("phase_changed", content, "_on_phase_changed")).is_true()
	assert_int(content.get_light_count()).is_greater(0)
	content._apply_phase_lights(0)
	var rotor = content.get_rotor()
	assert_object(rotor).is_not_null()
	cycle._elapsed = 0.0
	content._animate_hazards()
	var a: float = float(rotor.rotation.z)
	cycle._elapsed = 1.0
	content._animate_hazards()
	assert_float(float(rotor.rotation.z)).is_not_equal(a)
