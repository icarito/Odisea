extends GdUnitTestSuite

# FD-322 — Bahía radial centrífuga: tests de la ESCENA cilíndrica real
# (`BayVertical.tscn`) y de sus piezas nuevas, separados de
# `test_bay_vertical.gd` (que cubre el componente de contenido `BayVerticalWell`).
#
# Cubre los tres hilos del review de #415:
#  1) contenido curado montado sobre los chunks del stream (recorrido + atajos +
#     sala de control + rotor + ciclo con consumidores);
#  2) el cambio de modo REORIENTA la geometría: el rotator consume
#     `spiral_blend` y se registra en `GravityWorld`;
#  3) entrada/salida reales: SpawnPointV2 con id existente + buffers hacia
#     RingHub con parámetros seamless (sin IDs inventados).

const ScenePacked := preload("res://core_v2/levels/bay_vertical/BayVertical.tscn")
const RotatorScript := preload("res://core_v2/levels/bay_vertical/BayCylinderRotator.gd")
const LevelScript := preload("res://core_v2/levels/bay_vertical/BayVerticalLevel.gd")
const BufferScript := preload("res://core_v2/levels/bay_vertical/BayTransitionBuffer.gd")
const RingHubLightStateScript := preload("res://core_v2/levels/RingHubLightState.gd")
const FlowScript := preload("res://core_v2/levels/bay_vertical/BayTransitFlow.gd")
const GravityMountScript := preload("res://core_v2/levels/bay_vertical/BayGravityMount.gd")
const FlowRouteValidatorScript := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

const ENTRY_SPAWN_ID := "bay_vertical_entry"
const RINGHUB_SCENE := "res://core_v2/levels/RingHub_Level.tscn"
const BAY_SCENE := "res://core_v2/levels/bay_vertical/BayVertical.tscn"

# ── 2. El modo reorienta la geometría (spiral_blend + GravityWorld) ───────────

func test_rotator_consumes_spiral_blend() -> void:
	var r = auto_free(RotatorScript.new())
	r.base_radius = 48.0
	add_child(r)
	r._register_mode_driver()
	# Un punto a media vuelta de arco: centrífugo (blend 1) lo curva hacia el eje;
	# axial (blend 0) lo deja plano en su coordenada flat.
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
	# set_spiral_blend del autoload LLEGA a la geometría (no solo al estado).
	gw.set_spiral_blend(0.0)
	assert_float(r.get_spiral_blend()).is_equal_approx(0.0, 0.001)
	gw.set_spiral_blend(1.0)
	assert_float(r.get_spiral_blend()).is_equal_approx(1.0, 0.001)

# ── 3. Entrada/salida reales ─────────────────────────────────────────────────

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
		assert_bool(buf.kind == BufferScript.Kind.ENTRY or buf.kind == BufferScript.Kind.EXIT).is_true()

func test_level_return_params_are_seamless_and_keep_current_state() -> void:
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
	assert_bool(sd.has("target_airlock_path")).is_true()
	assert_str(String(sd.get("target_airlock_path"))).is_equal(lvl.ringhub_airlock_path)
	# Nada de IDs de spawn inventados.
	assert_bool(params.has("target_spawn_id")).is_false()
	assert_bool(params.has("spawn_id")).is_false()

func test_entry_trigger_points_at_bay_scene_and_spawn() -> void:
	# El pedestal del hub entra a la escena de la bahía con el spawn real.
	var ls = auto_free(RingHubLightStateScript.new())
	assert_str(String(ls.bay_vertical_scene_path)).is_equal(BAY_SCENE)
	assert_str(String(ls.bay_vertical_spawn_id)).is_equal(ENTRY_SPAWN_ID)
	assert_bool(ls.has_method("enter_bay_vertical")).is_true()

func test_ringhub_has_real_entry_pedestal() -> void:
	# La escena de RingHub debe declarar el pedestal que abre la bahía radial.
	var hub = load(RINGHUB_SCENE)
	assert_object(hub).is_not_null()
	var hub_scene = hub.instance()
	var pedestal = hub_scene.get_node_or_null("Hub/PedestalBayVertical")
	assert_object(pedestal).is_not_null()
	assert_bool(pedestal.has_signal("activated")).is_true()
	hub_scene.free()

# ── 1. Contenido curado montado sobre el stream ─────────────────────────────

func test_scene_mounts_curated_content_over_stream() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	assert_object(content).is_not_null()
	# Recorrido sembrado (más de un puñado de tramos de suelo).
	assert_int(content.get_segment_count()).is_greater(15)
	# Landmarks y atajos curados presentes.
	assert_object(content.get_laser_gate()).is_not_null()
	assert_object(content.get_gloo_span()).is_not_null()
	assert_object(content.get_rotor()).is_not_null()
	assert_int(content.get_shortcuts().size()).is_greater_equal(3)

func test_content_spine_climbs_toward_axis() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var pts: Array = content.get_spine_world_points()
	assert_int(pts.size()).is_greater(20)
	var first: Vector3 = pts[0]
	var last: Vector3 = pts[pts.size() - 1]
	# "Subir = ir hacia el eje": en centrífugo el recorrido gana altura radial.
	assert_float(last.y).is_greater(first.y + 15.0)
	# La cima queda cerca del eje (radio chico).
	var base_radius: float = float(level.get_node("CylinderRotator").base_radius)
	var axis_radius: float = sqrt(last.x * last.x + last.z * last.z)
	assert_float(axis_radius).is_less(base_radius * 0.5)

func test_content_follows_mode_reorientation() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var rotator = level.get_node("CylinderRotator")
	var content = level.get_node_or_null("BayContent")
	# Centrífugo: el puente mode-gated no es sólido.
	rotator.spiral_blend = 1.0
	content._physics_process(0.016)
	assert_bool(content.is_mode_bridge_solid()).is_false()
	# Propulsión: el puente (atajo de un solo modo) se solidifica sobre el
	# recorrido real.
	rotator.spiral_blend = 0.0
	content._physics_process(0.016)
	assert_bool(content.is_mode_bridge_solid()).is_true()

func test_content_cycle_has_consumers() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var cycle = level.get_node_or_null("BayProtocolCycle")
	assert_object(cycle).is_not_null()
	# El ciclo tiene un consumidor conectado (la capa de contenido).
	assert_bool(cycle.is_connected("phase_changed", content, "_on_phase_changed")).is_true()
	# Y el consumidor actúa: pinta las luces de sala por fase.
	assert_int(content.get_light_count()).is_greater(0)
	var lights_root = level.get_node_or_null("BayLights")
	var first_light = null
	for c in lights_root.get_children():
		if c is Light:
			first_light = c
			break
	assert_object(first_light).is_not_null()
	content._apply_phase_lights(0)
	var safe_color: Color = first_light.light_color
	content._apply_phase_lights(2)
	var danger_color: Color = first_light.light_color
	assert_bool(safe_color != danger_color).is_true()

func test_content_rotor_follows_cycle_clock() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var rotor = content.get_rotor()
	assert_object(rotor).is_not_null()
	var cycle = level.get_node_or_null("BayProtocolCycle")
	cycle._elapsed = 0.0
	content._animate_hazards()
	var a := float(rotor.rotation.z)
	cycle._elapsed = 1.0
	content._animate_hazards()
	var b := float(rotor.rotation.z)
	# Giro determinista derivado del reloj del ciclo (sin timer propio).
	assert_float(b).is_not_equal(a)

# ── Transit-Run: presupuesto de flow, ruta principal y sockets ───────────────

func test_transit_flow_budget_matches_contract() -> void:
	var flow = auto_free(FlowScript.new())
	flow.g = 14.0
	flow.v_jump = 10.0
	flow.v_run = 7.0
	flow.tick = 1.0 / 60.0
	# Métricas medidas en el motor: H_max ≈ 3.66 m (60 Hz), D_max corriendo ≈ 10.04 m.
	assert_float(flow.h_max()).is_equal_approx(3.66, 0.03)
	assert_float(flow.d_max(0.0)).is_equal_approx(10.04, 0.10)
	# Escalón cómodo ≤ 2.9 m (sin cornisa) y hueco principal ≤ 8.0 m (80 %).
	assert_float(flow.step_rise()).is_less_equal(2.9)
	assert_float(flow.main_route_gap()).is_less_equal(8.0)
	# Y se mantiene en la banda 70-80 % del alcance del contrato.
	assert_float(flow.main_route_gap()).is_greater_equal(0.70 * flow.d_max(0.0) - 0.01)
	assert_float(flow.main_route_gap()).is_less_equal(0.80 * flow.d_max(0.0) + 0.01)
	# El opcional usa la banda 90-100 %.
	assert_float(flow.optional_gap()).is_less_equal(1.00 * flow.d_max(0.0) + 0.01)

func test_flow_metrics_delegate_to_validator() -> void:
	var flow = auto_free(FlowScript.new())
	flow.g = 12.5
	flow.v_run = 6.5
	flow.v_jump = 9.5
	var m: Dictionary = flow.metrics()
	for key in ["g", "v_run", "v_jump", "tick", "main_threshold", "optional_min", "optional_max"]:
		assert_bool(m.has(key)).is_true()
	assert_float(float(m["g"])).is_equal_approx(12.5, 0.001)
	# h_max/d_max salen EXACTAMENTE del validador (misma fuente que la validación).
	assert_float(flow.h_max()).is_equal_approx(
		FlowRouteValidatorScript.compute_h_max(9.5, 12.5, float(m["tick"])), 0.0001)
	assert_float(flow.d_max(0.0)).is_equal_approx(
		FlowRouteValidatorScript.compute_d_max(6.5, 9.5, 12.5, 0.0, float(m["tick"])), 0.0001)

func test_main_route_validates_per_seed() -> void:
	# La ruta principal debe validar (entrada->cima con saltos dentro del umbral
	# main, sin herramientas ni sockets) para cualquier semilla.
	for seed_val in [1, 7, 42, 1337, 20261114]:
		var level = auto_free(ScenePacked.instance())
		var content = level.get_node_or_null("BayContent")
		content.generation_seed = seed_val
		add_child(level)
		var result: Dictionary = content.validate_main_route()
		assert_bool(result.has("valid_main_route")).is_true()
		assert_bool(bool(result["valid_main_route"])).is_true()
		var critical: Dictionary = result.get("critical_main_edge", {})
		if not critical.empty():
			assert_float(float(critical.get("demand_ratio", 99.0))).is_less_equal(0.80 + 0.0001)
		level.queue_free()
		yield(get_tree(), "idle_frame")

func test_flow_reads_ring_angular_velocity() -> void:
	var gw = get_node_or_null("/root/GravityWorld")
	assert_object(gw).is_not_null()
	var saved: float = float(gw.ship_angular_velocity_rad_s)
	# g(r) = ω²·r: elegimos ω para que g=14 en r=48.
	gw.ship_angular_velocity_rad_s = sqrt(14.0 / 48.0)
	var flow = auto_free(FlowScript.new())
	var ok: bool = flow.configure_gravity_from_world(gw, 48.0)
	gw.ship_angular_velocity_rad_s = saved
	assert_bool(ok).is_true()
	assert_float(flow.g).is_equal_approx(14.0, 0.2)
	assert_str(String(flow.source)).is_equal("gravity_world")

func test_flow_parses_contract_text() -> void:
	var flow = auto_free(FlowScript.new())
	var parsed: bool = flow.parse_contract("| g | 11.2 |\n- v_jump: 9\n- v_run = 8\n")
	assert_bool(parsed).is_true()
	assert_float(flow.g).is_equal_approx(11.2, 0.001)
	assert_float(flow.v_jump).is_equal_approx(9.0, 0.001)
	assert_float(flow.v_run).is_equal_approx(8.0, 0.001)

func test_main_route_gaps_are_jumpable() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var limit: float = content.get_main_route_gap_limit()
	assert_float(limit).is_greater(0.0)
	var gaps: Array = content.get_main_route_gaps()
	assert_int(gaps.size()).is_greater(0)
	for g in gaps:
		# Ningún hueco de la ruta principal excede el umbral (saltable a v_run).
		assert_float(float(g)).is_less_equal(limit * 1.10)

func test_main_route_has_no_puzzle_blocker() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	# La ruta principal nunca se bloquea con un puzle (gloo/láser viven en sockets).
	assert_bool(content.main_route_has_puzzle_blocker()).is_false()

func test_main_route_is_a_walkable_ramp() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var limit: float = content.get_main_route_gap_limit()
	var flats: Array = content.get_spine_flat_points()
	assert_int(flats.size()).is_greater(10)
	# Conectividad en el marco del cilindro (donde camina el jugador): cada tramo
	# sube dentro del presupuesto y avanza menos que el alcance; pendiente < 40°.
	for i in range(flats.size() - 1):
		var a: Vector3 = flats[i]
		var b: Vector3 = flats[i + 1]
		var run: float = abs(b.x - a.x)
		var rise: float = b.y - a.y
		assert_float(run).is_less_equal(limit * 1.10)
		assert_float(rise).is_less_equal(limit * 0.60)
		if run > 0.01:
			assert_float(rise / run).is_less(0.84)  # tan(40°)
	# Las placas siguen AMBOS extremos: el +Z del tramo NO es perpendicular al
	# "up" proyectado (sería un escalón horizontal en vez de rampa).
	var plates: Array = content.get_main_segment_nodes()
	assert_int(plates.size()).is_greater(10)
	var tilted := false
	for p in plates:
		var parts: Array = String(p.name).split("_")
		if parts.size() < 2:
			continue
		var idx: int = int(parts[1])
		if idx + 1 >= flats.size():
			continue
		var up: Vector3 = content._project_point(flats[idx]).basis.y.normalized()
		var z: Vector3 = p.transform.basis.z.normalized()
		if abs(up.dot(z)) > 0.05:
			tilted = true
			break
	assert_bool(tilted).is_true()

func test_sockets_are_optional_and_labeled() -> void:
	var level = auto_free(ScenePacked.instance())
	add_child(level)
	var content = level.get_node_or_null("BayContent")
	var labels: Array = content.get_socket_labels()
	assert_bool(labels.has("GlooClimb")).is_true()
	assert_bool(labels.has("CuratedSocket")).is_true()
	assert_bool(labels.has("MagRail")).is_true()
	# Todas las etiquetas usadas pertenecen al contrato (tags del validador).
	var contract_tags: Array = [FlowRouteValidatorScript.TAG_SPRINT_GAP,
		FlowRouteValidatorScript.TAG_RHYTHM_STEPS, FlowRouteValidatorScript.TAG_GLOO_CLIMB,
		FlowRouteValidatorScript.TAG_MAG_RAIL, FlowRouteValidatorScript.TAG_CURATED_SOCKET]
	var known: Array = content.get_known_labels()
	assert_int(known.size()).is_greater(0)
	for l in known:
		assert_bool(contract_tags.has(l)).is_true()

# ── El cambio de modo no teletransporta la geometría ─────────────────────────

func test_mode_switch_blend_is_bounded_per_frame() -> void:
	var mount = auto_free(GravityMountScript.new())
	add_child(mount)
	# Arranca en centrífugo (blend 1).
	assert_float(mount.get_gravity_blend()).is_equal_approx(1.0, 0.0001)
	assert_bool(mount.toggle_gravity_mode()).is_true()
	# Un solo frame de 16 ms no debe saltar el blend completo (1 -> 0).
	mount._physics_process(0.016)
	var after_one: float = mount.get_gravity_blend()
	assert_float(after_one).is_less(1.0)
	assert_float(after_one).is_greater(0.9)
	# Y tras suficientes frames converge exactamente al target (propulsión = 0).
	var steps := 0
	while mount.is_blending() and steps < 600:
		mount._physics_process(0.016)
		steps += 1
	assert_bool(mount.is_blending()).is_false()
	assert_float(mount.get_gravity_blend()).is_equal_approx(0.0, 0.0001)
