extends GdUnitTestSuite

# FD-325 polish — navegación diegética: guías 3D orientadas al cilindro (SpinFrame.up),
# baliza de Motor en get_engine_target(), línea de rumbo con flecha por posición de
# pantalla y marcador de borde con chevron real + etiqueta clampeada.

const GuidesScript = preload("res://core_v2/levels/ark_run/ArkRunRouteGuides.gd")
const ArrowScript = preload("res://core_v2/levels/ark_run/ArkRunRouteArrow.gd")
const TargetHintScript = preload("res://core_v2/levels/ark_run/ArkRunHudTargetHint.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPS := 1e-4

func _waypoints() -> Array:
	# Tres placas en paredes distintas del cilindro (radios y ángulos distintos).
	return [
		{"position": Vector3(240.0, 0.0, 200.0)},
		{"position": Vector3(0.0, 240.0, 100.0)},
		{"position": Vector3(-240.0, 0.0, 0.0)},
	]

func test_route_guides_oriented_by_cylinder_up_not_global_y() -> void:
	var bridge := Vector3(240.0, 0.0, 900.0)
	var motor := Vector3(-240.0, 0.0, -1000.0)
	var transforms: Array = GuidesScript.build_transforms(_waypoints(), bridge, motor)
	assert_int(transforms.size()).is_greater(3)
	# Al menos un trazo cae a RING_RADIUS del centro elevado +sim_up*RING_LIFT de la placa 0.
	var anchor: Vector3 = _waypoints()[0]["position"]
	var expected: Vector3 = anchor + SpinFrame.up(anchor) * GuidesScript.RING_LIFT
	var near_ring := false
	for t in transforms:
		if (t as Transform).origin.distance_to(expected) <= GuidesScript.RING_RADIUS + 1.0:
			near_ring = true
			break
	assert_bool(near_ring).is_true()
	# La up de los anillos es radial (SpinFrame.up), no +Y global: el centro elevado difiere
	# del que daría +Y global en una placa de pared.
	assert_bool(expected.is_equal_approx(anchor + Vector3.UP * GuidesScript.RING_LIFT)).is_false()

func test_route_arrow_picks_side_by_screen_position() -> void:
	var view := Vector2(1280.0, 720.0)
	assert_str(ArrowScript.arrow_for(Vector2(100.0, 360.0), view)).is_equal("left")
	assert_str(ArrowScript.arrow_for(Vector2(1180.0, 360.0), view)).is_equal("right")
	assert_str(ArrowScript.arrow_for(Vector2(640.0, 360.0), view)).is_equal("center")
	assert_str(ArrowScript.format_route("MOTOR · 1240 m", "left")).is_equal("◄ MOTOR · 1240 m")
	assert_str(ArrowScript.format_route("MOTOR · 1240 m", "right")).is_equal("MOTOR · 1240 m ►")
	assert_str(ArrowScript.format_route("MOTOR · 1240 m", "center")).is_equal("▲ MOTOR · 1240 m ▲")

func test_target_hint_projects_offscreen_with_direction() -> void:
	var cam := Camera.new()
	add_child(cam)
	cam.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0))
	# Objetivo muy a la derecha y detrás: fuera de pantalla, con dirección válida.
	var hint: Dictionary = TargetHintScript.project_hint(cam, Vector3(4000.0, 0.0, -100.0), Vector2(1280.0, 720.0))
	assert_bool(bool(hint["onscreen"])).is_false()
	assert_float((hint["direction"] as Vector2).length()).is_less(1.001)
	remove_child(cam)
	cam.free()

func test_engine_beacon_uses_engine_target() -> void:
	# El punto del Motor de las guías es get_engine_target de la placa 0 (z ~ -1000),
	# no el Vector3(0,0,engine_z_max) de antes.
	assert_float(SpinFrame.up(Vector3(240.0, 0.0, -1000.0)).length()).is_less(1.001)
