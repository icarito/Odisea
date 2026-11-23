extends GdUnitTestSuite

# FD-324 F6 — carrera/presentacion: cronometro, reinicio y fantasma; camara
# cilindrica sobre el rig existente; sombra a lo largo de g_eff; LOD Tron de 3
# niveles; y predictor de preview acotado con error < 0.5 m.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const RaceScript = preload("res://core_v2/levels/ark_run/ArkRunRaceController.gd")
const CameraScript = preload("res://core_v2/camera/ArkRunCylindricalCamera.gd")
const ShadowScript = preload("res://core_v2/levels/ark_run/ArkRunGravityShadow.gd")
const LodScript = preload("res://core_v2/levels/ark_run/ArkRunLodTronPass.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")
const EPS := 1e-5
func _run_for(controller, seconds: float, z0: float, vz: float) -> void:
	var dt := 1.0 / 60.0
	var steps: int = int(round(seconds / dt))
	for index in range(steps):
		var t: float = float(index + 1) * dt
		controller.tick(dt, Vector3(240.0, 0.0, z0 + vz * t), Basis.IDENTITY)
func test_chronometer_finish_restart_and_margin() -> void:
	var race = auto_free(RaceScript.new())
	add_child(race)
	race.set_reference_time(10.0)
	race.start_run()
	_run_for(race, 2.0, 0.0, 0.0)
	assert_float(race.t_run).is_equal_approx(2.0, 1e-4)
	assert_bool(race.running).is_true()

	race.tick(1.0 / 60.0, Vector3(240.0, 0.0, -950.0), Basis.IDENTITY)
	assert_bool(race.running).is_false()
	assert_bool(race.finished).is_true()
	assert_float(race.best_time_sec).is_equal_approx(2.0 + 1.0 / 60.0, 1e-4)
	assert_float(race.margin_pct).is_greater(25.0)
	assert_bool(race.meets_margin()).is_true()

	var best_before: float = race.best_time_sec
	race.restart_run()
	assert_float(race.t_run).is_equal_approx(0.0, 1e-9)
	assert_bool(race.running).is_true()
	assert_bool(race.finished).is_false()
	assert_float(race.best_time_sec).is_equal_approx(best_before, 1e-9)

	# Determinismo: el mismo input reproduce el mismo cronometro.
	var twin = auto_free(RaceScript.new())
	add_child(twin)
	twin.start_run()
	_run_for(twin, 2.0, 0.0, 0.0)
	assert_float(twin.t_run).is_equal_approx(2.0, 1e-4)
func test_ghost_replay_interpolates_best_trace() -> void:
	var race = auto_free(RaceScript.new())
	add_child(race)
	race.sample_interval = 0.25
	race.start_run()
	_run_for(race, 2.0, 0.0, -100.0)
	race.finish_run()
	assert_int(race.ghost_sample_count()).is_greater(1)
	assert_bool(race.has_ghost_visual()).is_true()
	assert_bool(race.get_ghost_material().flags_unshaded).is_true()
	assert_bool(race.get_ghost_material().flags_transparent).is_true()

	var sample: Dictionary = race.ghost_trace[2]
	var pose: Dictionary = race.get_ghost_pose(float(sample["t"]))
	assert_float((pose["position"] as Vector3).distance_to(sample["position"] as Vector3)) \
		.is_less(EPS)

	var first: Dictionary = race.ghost_trace[2]
	var second: Dictionary = race.ghost_trace[3]
	var mid: float = (float(first["t"]) + float(second["t"])) * 0.5
	var ratio: float = (mid - float(first["t"])) / (float(second["t"]) - float(first["t"]))
	var expected: Vector3 = (first["position"] as Vector3).linear_interpolate(second["position"], ratio)
	var interp: Dictionary = race.get_ghost_pose(mid)
	assert_float((interp["position"] as Vector3).distance_to(expected)).is_less(EPS)

	# Un intento mas rapido reemplaza el fantasma grabado.
	race.restart_run()
	_run_for(race, 1.0, 0.0, -200.0)
	race.finish_run()
	assert_float(race.best_time_sec).is_less(2.0)
	var new_sample: Dictionary = race.ghost_trace[1]
	var new_pose: Dictionary = race.get_ghost_pose(float(new_sample["t"]))
	assert_float((new_pose["position"] as Vector3).distance_to(new_sample["position"] as Vector3)) \
		.is_less(EPS)
	assert_float((new_sample["position"] as Vector3).z).is_less(0.0)
func test_cylindrical_camera_continuous_and_no_new_camera() -> void:
	var camera = auto_free(CameraScript.new())
	var pilot := Spatial.new()
	pilot.name = "Pilot"
	var rig := Spatial.new()
	rig.name = "CameraRig"
	var spring_arm := Spatial.new()
	spring_arm.name = "SpringArm"
	rig.add_child(spring_arm)
	pilot.add_child(rig)
	add_child(pilot)

	camera.blend_speed = 2.0
	camera.axial_speed = 1.6
	var dt := 1.0 / 60.0
	var previous: Basis = Basis.IDENTITY
	var previous_blend := 0.0
	var max_angle := 0.0
	var max_blend_step := 0.0
	var state: Dictionary = {}
	for index in range(240):
		var f: float = float(index) / 239.0
		var radius: float = lerp(240.0, 180.0, f)
		var pos := Vector3(radius, 0.0, 1000.0 * f)
		var progress: float = clamp((f - 0.4) / 0.6, 0.0, 1.0)
		state = camera.step_camera(pos, SpinFrame.up(pos, Vector3.UP), 240.0, dt, progress)
		var basis: Basis = state["basis"]
		assert_float(basis.determinant()).is_equal_approx(1.0, 1e-4)
		if index > 0:
			var dot: float = clamp(previous.z.normalized().dot(basis.z.normalized()), -1.0, 1.0)
			max_angle = max(max_angle, acos(dot))
			max_blend_step = max(max_blend_step, abs(float(state["blend_25d"]) - previous_blend))
		previous = basis
		previous_blend = float(state["blend_25d"])

	assert_float(max_angle).is_less(0.25)
	assert_float(max_blend_step).is_less_equal(camera.blend_speed * dt + EPS)
	assert_bool(camera.apply_to_rig(rig, state)).is_true()
	assert_bool(rig.find_node("Camera", true, false) == null).is_true()
	assert_int(rig.get_child_count()).is_equal(1) # solo el SpringArm existente
func test_gravity_shadow_follows_g_eff_rotation() -> void:
	var shadow = auto_free(ShadowScript.new())
	add_child(shadow)
	var pos := Vector3(240.0, 0.0, 0.0)
	var omega: float = SpinFrame.omega_for(9.8, 240.0)
	var upright: Dictionary = shadow.update_shadow(pos, omega, 0.0)
	var idle_dir: Vector3 = SpinFrame.g_eff(pos, omega, 0.0).normalized()
	assert_float((upright["normal"] as Vector3).distance_to(idle_dir)).is_less(EPS)
	assert_float((upright["normal"] as Vector3).angle_to(Vector3.RIGHT)).is_less(1e-4)

	var burning: Dictionary = shadow.update_shadow(pos, omega, 9.8)
	var burn_dir: Vector3 = SpinFrame.g_eff(pos, omega, 9.8).normalized()
	assert_float((burning["normal"] as Vector3).distance_to(burn_dir)).is_less(EPS)
	assert_float((burning["normal"] as Vector3).angle_to(Vector3(0.7071, 0.0, -0.7071))) \
		.is_less(1e-3)
	assert_float((upright["normal"] as Vector3).angle_to(burning["normal"] as Vector3)) \
		.is_equal_approx(deg2rad(45.0), 1e-3)
	var transform: Transform = shadow.get_shadow_transform()
	assert_float(transform.basis.y.normalized().dot(burn_dir)).is_greater(0.9999)

func test_lod_three_levels_deterministic_and_tron_materials() -> void:
	var lod = auto_free(LodScript.new())
	add_child(lod)
	lod.build_static()
	assert_int(lod.get_sector_count()).is_equal(10)
	var levels: Array = lod.update_lod_for_position(Vector3(240.0, 0.0, 0.0))
	var again: Array = lod.update_lod_for_position(Vector3(240.0, 0.0, 0.0))
	assert_array(levels).is_equal(again)
	assert_int(lod.get_level(4)).is_equal(LodScript.LEVEL_NEAR)
	assert_int(lod.get_level(5)).is_equal(LodScript.LEVEL_NEAR)
	assert_int(lod.get_level(3)).is_equal(LodScript.LEVEL_MEDIUM)
	assert_int(lod.get_level(6)).is_equal(LodScript.LEVEL_MEDIUM)
	assert_int(lod.get_level(0)).is_equal(LodScript.LEVEL_FAR)
	assert_int(lod.get_level(9)).is_equal(LodScript.LEVEL_FAR)

	var material: SpatialMaterial = lod.get_material()
	assert_bool(material.flags_unshaded).is_true()
	assert_bool(material.emission_enabled).is_true()
	assert_bool(lod.get_accent_material().flags_unshaded).is_true()
	var environment: Environment = lod.get_environment()
	assert_object(environment).is_not_null()
	assert_float(environment.background_color.v).is_less(0.2)
	var line: Spatial = lod.add_emissive_polyline(
		[Vector3.ZERO, Vector3(0.0, 0.0, 100.0)], Color(0.2, 0.9, 1.0, 1.0)
	)
	assert_object(line).is_not_null()

func test_predictor_preview_bounded_cheap_and_accurate() -> void:
	var omega: float = SpinFrame.omega_for()
	var p0 := Vector3(100.0, 0.0, 0.0)
	var v0 := Vector3(10.0, 0.0, 0.0)
	var fine: Dictionary = PredictorScript.predict_landing(p0, v0, omega, 240.0)
	var predictor = auto_free(PredictorScript.new())
	add_child(predictor)
	var preview: Dictionary = predictor.update_preview(p0, v0, omega, 240.0, true)

	assert_bool(preview["hit"]).is_true()
	assert_bool(fine["hit"]).is_true()
	assert_int(int(fine["steps"])).is_greater(PredictorScript.PREVIEW_MAX_STEPS)
	assert_int(int(preview["steps"])).is_less_equal(PredictorScript.PREVIEW_MAX_STEPS)
	var points: Array = preview["trajectory"]
	assert_int(points.size()).is_greater(1)
	assert_int(points.size()).is_less_equal(PredictorScript.MAX_TRAJECTORY_POINTS)
	var error: float = (preview["point"] as Vector3).distance_to(fine["point"] as Vector3)
	assert_float(error).is_less(0.5)

	var start: int = OS.get_ticks_usec()
	for _i in range(40):
		predictor.update_preview(p0, v0, omega, 240.0, true)
	var preview_us: int = (OS.get_ticks_usec() - start) / 40
	start = OS.get_ticks_usec()
	for _i in range(40):
		PredictorScript.predict_landing(p0, v0, omega, 240.0)
	var fine_us: int = (OS.get_ticks_usec() - start) / 40
	print("PREDICTOR preview_us=%d fine_us=%d steps=%d points=%d error_m=%.4f" \
		% [preview_us, fine_us, int(preview["steps"]), points.size(), error])

# FD-325 polish: el Motor es 100% alcanzable. Además del umbral z, la carrera cierra al
# llegar por distancia al destino (centro de la placa 0), aunque la cara interior de la
# tapa Aft quede más atrás.
func test_race_finishes_on_engine_target_distance() -> void:
	var race = auto_free(RaceScript.new())
	add_child(race)
	race.start_run()
	var engine_target := Vector3(240.0, 0.0, -1000.0)
	# Lejos del destino y sin cruzar engine_z_max: sigue corriendo.
	race.tick(0.5, Vector3(240.0, 0.0, -900.0), Basis.IDENTITY)
	race.observe_target(Vector3(240.0, 0.0, -900.0), engine_target, 45.0)
	assert_bool(race.running).is_true()
	assert_bool(race.finished).is_false()
	# Dentro del radio del destino: cierra.
	race.observe_target(Vector3(240.0, 0.0, -975.0), engine_target, 45.0)
	assert_bool(race.finished).is_true()
	assert_bool(race.running).is_false()
