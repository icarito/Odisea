extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-324 F0 — base de ArkRunSlice: escena limpia sin rotadores, espiral de 50
# placas, hub axial ZERO_G, zonas Puente/Motor y contención física real del
# casco contra un cuerpo lanzado radialmente.

const SliceScene = preload("res://core_v2/levels/ark_run/ArkRunSlice.tscn")
const SliceScript = preload("res://core_v2/levels/ark_run/ArkRunSlice.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPS := 0.000001
const TargetHintScript = preload("res://core_v2/levels/ark_run/ArkRunHudTargetHint.gd")

func _instantiate_slice():
	var slice = auto_free(SliceScene.instance())
	add_child(slice)
	slice.set_physics_process(false)
	var pilot = slice.get_node_or_null("Pilot")
	if pilot != null:
		pilot.set_physics_process(false)
	return slice

func test_scene_loads_headless_without_rotators() -> void:
	var slice = _instantiate_slice()
	assert_object(slice).is_not_null()
	assert_bool(slice.find_node("WorldRotator", true, false) == null).is_true()
	assert_bool(slice.find_node("CylinderRotator", true, false) == null).is_true()

	# Constantes publicadas del slice.
	assert_int(int(SliceScript.SLICE_SEED)).is_equal(32401)
	assert_float(float(SliceScript.SLICE_LENGTH)).is_equal_approx(2000.0, 1e-9)
	assert_float(float(SliceScript.R_HULL)).is_equal_approx(340.0, 1e-9)
	assert_float(float(SliceScript.R_HUB)).is_equal_approx(8.0, 1e-9)

	# Espiral: 1 campo, 50 placas, z de -1000 a +960.
	var field = slice.get_node_or_null("DomeSpiralField")
	assert_object(field).is_not_null()
	assert_int(field.get_spiral_count()).is_equal(6)
	var configs: Array = field.get_spiral_configs()
	assert_int(configs.size()).is_equal(6)
	for k in range(6):
		assert_float(float(configs[k]["phase"])).is_equal_approx(TAU * float(k) / 6.0, 1e-5)
	var config: Dictionary = slice.get_spiral_config()
	assert_int(SpiralGeometry.plate_count_for(config)).is_equal(50)
	assert_float(float(config["turns"])).is_equal_approx(2.0, EPS)
	assert_float(float(config["total_height"])).is_equal_approx(2000.0, EPS)
	assert_float(float(config["plate_step"])).is_equal_approx(40.0, EPS)
	assert_float(float(config["r_min"])).is_equal_approx(220.0, EPS)
	assert_float(float(config["r_max"])).is_equal_approx(260.0, EPS)
	assert_float(SpiralGeometry.plate_transform(config, 0).origin.z) \
		.is_equal_approx(-1000.0, EPS)
	assert_float(SpiralGeometry.plate_transform(config, 49).origin.z) \
		.is_equal_approx(960.0, EPS)

	# Casco grueso: 24 paredes + 2 tapas, inmutable y con malla visual.
	var hull = slice.get_node_or_null("ArkRunHull")
	assert_object(hull).is_not_null()
	assert_float(hull.get_hull_radius()).is_equal_approx(340.0, EPS)
	assert_float(hull.get_slice_length()).is_equal_approx(2000.0, EPS)
	assert_int(hull.get_wall_segment_count()).is_equal(24)
	assert_int(hull.get_collision_shape_count()).is_equal(26)
	assert_object(hull.get_node_or_null("HullVisual")).is_not_null()

	# Hub axial sobre Z con inicio en z ~ 0.
	var hub = slice.get_node_or_null("AxialHub/SpinAxialHub")
	assert_object(hub).is_not_null()
	assert_bool(hub.contains_global_point(Vector3(0.0, 0.0, 0.0))).is_true()
	assert_bool(hub.contains_global_point(Vector3(0.0, 0.0, 990.0))).is_true()
	assert_bool(hub.contains_global_point(Vector3(0.0, 0.0, 1100.0))).is_false()

	var pilot = slice.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()
	assert_float(abs(pilot.global_transform.origin.z)).is_less(1.0)
	assert_float(SpinFrame.r_perp(pilot.global_transform.origin).length()).is_less(8.0)
	# F7: arranca en ZERO_G; SPIN_REAL se activa recién al detonar (ver F7).
	assert_bool(pilot.is_spin_real_active()).is_false()

	# Zonas consultables por posición: Puente +Z, Motor -Z.
	assert_float(slice.get_bridge_z_min()).is_equal_approx(880.0, EPS)
	assert_float(slice.get_engine_z_max()).is_equal_approx(-940.0, EPS)
	assert_bool(slice.zone_at(Vector3(220.0, 0.0, 880.0)) == "Puente").is_true()
	assert_bool(slice.zone_at(Vector3(220.0, 0.0, 940.0)) == "Puente").is_true()
	assert_bool(slice.zone_at(Vector3(220.0, 0.0, 0.0)) == "").is_true()
	assert_bool(slice.zone_at(Vector3(220.0, 0.0, -940.0)) == "Motor").is_true()
	assert_bool(slice.zone_at(Vector3(220.0, 0.0, -970.0)) == "Motor").is_true()
	assert_bool(slice.is_in_bridge(Vector3(220.0, 0.0, 940.0))).is_true()
	assert_bool(slice.is_in_engine(Vector3(220.0, 0.0, -970.0))).is_true()

	# Contenedores vacíos listos para F1–F5.
	for node_name in [
		"ExplosionController", "TraversalRoot", "IndustryRoot",
		"EngineIgnitionRoot", "RaceHudRoot"
	]:
		assert_object(slice.get_node_or_null(String(node_name))).is_not_null()

func test_slice_wires_f1_f2_f3_modules_with_predictor_gated_in_hub() -> void:
	var slice = _instantiate_slice()
	# F1: pasamanos del núcleo, explosión armada al Puente y propulsores LT.
	var explosion_root = slice.get_node_or_null("ExplosionController")
	assert_object(explosion_root).is_not_null()
	assert_object(explosion_root.get_node_or_null("ArkRunHubHandrails")).is_not_null()
	assert_object(explosion_root.get_node_or_null("ArkRunThrusterInput")).is_not_null()
	var explosion = explosion_root.get_node_or_null("ArkRunExplosion")
	assert_object(explosion).is_not_null()
	assert_vector3(explosion.bridge_target).is_equal_approx(slice.get_bridge_target(), Vector3(1e-5, 1e-5, 1e-5))

	# F2: domos + andamios, ≥2 spokes con ascensor radial, cuerda y ruta de 50.
	var traversal_root = slice.get_node_or_null("TraversalRoot")
	var props = traversal_root.get_node_or_null("ArkRunTerraceProps")
	assert_object(props).is_not_null()
	# 150 domos posibles - 2 placas reservadas (Puente 48 / Motor 0) = 148.
	assert_int(props.get_dome_count()).is_equal(148)
	assert_int(props.get_scaffold_count()).is_greater(50)
	assert_int(slice.get_node("DomeSpiralField").get_spiral_count()).is_equal(6)
	for entry in props.get_dome_entries():
		assert_float(float(entry["variant"]["radius"])).is_greater_equal(30.0)
	var elevators = traversal_root.get_node_or_null("Elevators")
	assert_object(elevators).is_not_null()
	assert_int(elevators.get_child_count()).is_greater_equal(2)
	for spoke in elevators.get_children():
		assert_object(spoke.get_elevator()).is_not_null()
		assert_bool(spoke.is_elevator_operational()).is_true()
	var rope = traversal_root.get_node_or_null("Rope")
	assert_object(rope).is_not_null()
	assert_object(rope.get_rope()).is_not_null()
	assert_int(slice.get_waypoint_count()).is_equal(50)
	assert_str(String(slice.get_canonical_route().get_start_name())).is_equal("Puente")
	assert_str(String(slice.get_canonical_route().get_end_name())).is_equal("Motor")

	# F3: colisión gruesa de los 96 racimos siempre presente.
	var streamer = slice.get_node_or_null("IndustryRoot/ArkRunIndustryStreamer")
	assert_object(streamer).is_not_null()
	assert_int(streamer.get_coarse_body_count()).is_equal(96)

	# F4: host del Suit OS en RaceHudRoot, con destinos y ruta canónica.
	var host = slice.get_node_or_null("RaceHudRoot/ArkRunSuitOSHost")
	assert_object(host).is_not_null()
	assert_bool(host.slice == slice).is_true()
	SuitOS.ensure_ark_run_apps()
	var nav = SuitOS.get_screen("ship:ark_nav")
	assert_object(nav).is_not_null()
	host._sync_route(nav, slice)
	assert_float(nav.hull_radius).is_equal_approx(340.0, EPS)
	assert_float(nav.slice_length).is_equal_approx(2000.0, EPS)
	var labels: Array = []
	for destination in nav.get_destinations():
		labels.append(String(destination["label"]))
	assert_array(labels).is_equal(["Puente", "Núcleo", "Motor", "Ascensores"])
	assert_int(nav.get_route().size()).is_equal(50)
	nav.set_destination("bridge")
	host._sync_route(nav, slice)
	assert_int(nav.get_route().size()).is_equal(1)

	# F7: HUD diegético presente y refrescable.
	var hud = slice.get_node_or_null("RaceHudRoot/ArkRunHudOverlay")
	assert_object(hud).is_not_null()
	hud.refresh({"phase": "TEST", "timer": 1.0, "best": -1.0})
	assert_str(hud.get_phase_label().text).is_equal("TEST")
	hud.refresh({"phase": "TEST", "thrusting": true, "rope": "ATTACHED", "controls": "c"})
	assert_bool(hud._stats_label.text.find("PROPULSOR ACTIVO") >= 0).is_true()
	assert_bool(hud._stats_label.text.find("CUERDA ENGANCHADA") >= 0).is_true()
	assert_bool(slice.get_node("SpinRealCamera").enable_25d_override).is_false()

	# F7: anclajes de cuerda en todo el cilindro (domos de las 6 espirales).
	var anchors: Array = slice.collect_rope_anchors()
	assert_int(anchors.size()).is_greater_equal(150)
	var z_min := INF
	var z_max := -INF
	for anchor in anchors:
		var point: Vector3 = anchor.origin if typeof(anchor) == TYPE_TRANSFORM else anchor
		z_min = min(z_min, point.z)
		z_max = max(z_max, point.z)
	assert_float(z_min).is_less(-900.0)
	assert_float(z_max).is_greater(900.0)
	var anchor_visuals = slice.get_node_or_null("TraversalRoot/RopeAnchorVisuals")
	assert_object(anchor_visuals).is_not_null()
	assert_int(anchor_visuals.multimesh.instance_count).is_equal(anchors.size())
	var guides = slice.get_node_or_null("TraversalRoot/ArkRunLodTronPass/RouteGuides")
	assert_object(guides).is_not_null()
	assert_int(guides.multimesh.instance_count).is_greater(20)

	# HUD sin hints de teclas (feedback de playtest); el minimapa vive abajo.
	assert_bool(hud.get_node_or_null("HudRoot/Minimap") != null).is_true()
	# Idle ZERO_G dentro del hub: predictor oculto y preview salteado (sin costo).
	var pilot = slice.get_node_or_null("Pilot")
	assert_float(SpinFrame.r_perp(pilot.global_transform.origin).length()).is_less(8.0)
	var predictor = slice.get_node_or_null("SpinLandingPredictor")
	slice.update_spin_presentation(1.0 / 60.0)
	assert_bool(predictor.visible).is_false()
	var trail = predictor.get_node_or_null("LandingTrajectory")
	assert_object(trail).is_not_null()
	assert_int(trail.multimesh.instance_count).is_equal(0)

func test_hull_contains_body_thrown_radially() -> void:
	var slice = _instantiate_slice()
	var body := RigidBody.new()
	body.name = "HullProbe"
	body.gravity_scale = 0.0
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	var shape := SphereShape.new()
	shape.radius = 0.5
	var collision := CollisionShape.new()
	collision.shape = shape
	body.add_child(collision)
	# Arranca dentro de la banda industrial, por fuera de la espiral, hacia la pared.
	body.translation = Vector3(320.0, 0.0, 0.0)
	body.linear_velocity = Vector3(25.0, 0.0, 0.0)
	slice.add_child(body)

	var fps: float = float(Engine.iterations_per_second)
	var frames: int = int(ceil(2.0 * fps))
	var max_radial := 0.0
	var final_radial := 0.0
	for _i in range(frames):
		yield (get_tree(), "physics_frame")
		final_radial = SpinFrame.r_perp(body.global_transform.origin).length()
		max_radial = max(max_radial, final_radial)

	# Impacta el casco (pared interior r=340) y no escapa del mundo.
	assert_float(max_radial).is_greater(330.0)
	assert_float(max_radial).is_less(350.0)
	assert_float(final_radial).is_greater(334.0)
	assert_float(final_radial).is_less(350.0)
	assert_float(abs(body.global_transform.origin.z)).is_less(1050.0)

func test_shoulder_slots_are_suppressed_in_ark_run_and_restored_on_exit() -> void:
	var slice = SliceScene.instance()
	add_child(slice)
	slice.set_physics_process(false)
	assert_bool(SuitOS.shoulder_slots_suppressed).is_true()
	remove_child(slice)
	slice.free()
	assert_bool(SuitOS.shoulder_slots_suppressed).is_false()

func test_hud_target_hint_projects_on_screen_and_clamps_offscreen() -> void:
	var camera := Camera.new()
	add_child(camera)
	camera.global_transform = Transform(Basis.IDENTITY, Vector3.ZERO)
	var viewport := Vector2(1280.0, 720.0)
	var front: Dictionary = TargetHintScript.project_hint(camera, Vector3(0.0, 0.0, -20.0), viewport)
	assert_bool(bool(front["onscreen"])).is_true()
	var behind: Dictionary = TargetHintScript.project_hint(camera, Vector3(0.0, 0.0, 20.0), viewport)
	assert_bool(bool(behind["onscreen"])).is_false()
	var point: Vector2 = behind["position"]
	assert_bool(point.x >= 48.0 and point.x <= viewport.x - 48.0).is_true()
	assert_bool(point.y >= 48.0 and point.y <= viewport.y - 48.0).is_true()
	var offscreen: Dictionary = TargetHintScript.project_hint(camera, Vector3(1000.0, 0.0, -20.0), viewport)
	assert_bool(bool(offscreen["onscreen"])).is_false()
	remove_child(camera)
	camera.free()
