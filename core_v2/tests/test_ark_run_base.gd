extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-324 F0 — base de ArkRunSlice: escena limpia sin rotadores, espiral de 50
# placas, hub axial ZERO_G, zonas Puente/Motor y contención física real del
# casco contra un cuerpo lanzado radialmente.

const SliceScene = preload("res://core_v2/levels/ark_run/ArkRunSlice.tscn")
const SliceScript = preload("res://core_v2/levels/ark_run/ArkRunSlice.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPS := 0.000001

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
	assert_float(float(SliceScript.R_HULL)).is_equal_approx(300.0, 1e-9)
	assert_float(float(SliceScript.R_HUB)).is_equal_approx(8.0, 1e-9)

	# Espiral: 1 campo, 50 placas, z de -1000 a +960.
	var field = slice.get_node_or_null("DomeSpiralField")
	assert_object(field).is_not_null()
	assert_int(field.get_spiral_count()).is_equal(1)
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
	assert_float(hull.get_hull_radius()).is_equal_approx(300.0, EPS)
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
	assert_bool(pilot.is_spin_real_active()).is_true()

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
	# Arranca pasado r=260, por fuera de la espiral, y va hacia la pared.
	body.translation = Vector3(270.0, 0.0, 0.0)
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

	# Impacta el casco (pared interior r=300) y no escapa del mundo.
	assert_float(max_radial).is_greater(290.0)
	assert_float(max_radial).is_less(310.0)
	assert_float(final_radial).is_greater(294.0)
	assert_float(final_radial).is_less(310.0)
	assert_float(abs(body.global_transform.origin.z)).is_less(1050.0)
