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

func test_level_return_params_are_seamless_and_dont_invent_ids() -> void:
	var lvl = auto_free(LevelScript.new())
	add_child(lvl)
	lvl._ringhub_return_state = {"player_snapshot": {"position": Vector3(1.0, 2.0, 3.0)}}
	assert_bool(lvl.has_return_state()).is_true()
	var params: Dictionary = lvl.build_ringhub_params()
	assert_str(String(params.get("transition"))).is_equal("seamless")
	assert_bool(params.get("preserve_player_state")).is_false()
	assert_bool(params.has("state_data")).is_true()
	assert_bool(params.has("target_spawn_id")).is_false()
	assert_bool(params.has("spawn_id")).is_false()
	var sd: Dictionary = params.get("state_data", {})
	assert_bool(sd.has("player_snapshot")).is_true()

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
	assert_int(content.get_segment_count()).is_greater(20)
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
