extends GdUnitTestSuite

# FD-325 T4 — feedback diegético de propulsión y cuerda.
# Jet: doble boquilla visible sólo propulsando con Δv, orientada a -thrust_dir;
# arco Δv oculto en suelo al 100%, cian/ámbar/rojo según nivel y vacío. Cuerda:
# badge por dispositivo, tether SWING(cian)→REELING(dorado) y FOV de catapulta
# suave y acotado. Sin cámara real: la proyección se salta sin crash.

const JetScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticJetV2.gd")
const RopeScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticRopeV2.gd")
const DT := 1.0 / 60.0
const EPS := 1e-4
const PILOT := Transform(Basis.IDENTITY, Vector3(240.0, 0.0, 0.0))

func test_jet_nozzles_visible_only_when_thrusting_with_dv() -> void:
	var jet = auto_free(JetScript.new())
	add_child(jet)
	var thrust := Vector3(0.0, 0.0, -1.0)
	assert_int(jet.get_nozzles().size()).is_equal(2) # doble boquilla izq/der
	var idle: Dictionary = jet.update_jet(PILOT, thrust, false, 0.8, false, null, DT)
	assert_bool(idle["jet_visible"]).is_false()
	assert_bool(jet.is_jet_visible()).is_false()

	var burning: Dictionary = jet.update_jet(PILOT, thrust, true, 0.8, false, null, DT)
	assert_bool(burning["jet_visible"]).is_true()
	assert_bool(jet.is_jet_visible()).is_true()
	var transforms: Array = jet.get_nozzle_transforms()
	# +Y local del cono = escape = -thrust_dir; uno a cada lado de la espalda.
	assert_float((transforms[0] as Transform).basis.y.normalized().dot(thrust)).is_less(-0.9999)
	assert_float((transforms[1] as Transform).basis.y.normalized().dot(thrust)).is_less(-0.9999)
	var left: Vector3 = (transforms[0] as Transform).origin - PILOT.origin
	var right: Vector3 = (transforms[1] as Transform).origin - PILOT.origin
	assert_float(abs(left.x + right.x)).is_less(EPS)

	var empty: Dictionary = jet.update_jet(PILOT, thrust, true, 0.0, false, null, DT)
	assert_bool(empty["jet_visible"]).is_false() # sin Δv no hay jet
	assert_bool(empty["empty"]).is_true()
	assert_bool(jet.is_jet_visible()).is_false()

func test_jet_arc_hidden_on_ground_and_colors_by_level() -> void:
	var jet = auto_free(JetScript.new())
	add_child(jet)
	var thrust := Vector3(0.0, 0.0, -1.0)
	# Suelo con Δv al 100% y sin propulsar: pantalla limpia.
	var walk: Dictionary = jet.update_jet(PILOT, thrust, false, 1.0, true, null, DT)
	assert_bool(walk["arc_visible"]).is_false()
	assert_bool(jet.is_arc_visible()).is_false()

	# En aire con Δv alto: visible cian.
	var air: Dictionary = jet.update_jet(PILOT, thrust, false, 0.8, false, null, DT)
	assert_bool(air["arc_visible"]).is_true()
	assert_bool(jet.get_arc_color().is_equal_approx(JetScript.FILL_COLOR)).is_true()

	# Consumo por debajo de 0.30: ámbar.
	jet.update_jet(PILOT, thrust, true, 0.2, false, null, DT)
	assert_bool(jet.get_arc_color().is_equal_approx(JetScript.WARN_COLOR)).is_true()

	# Suelo consumiendo Δv: sigue visible (no se oculta mientras recarga/consume).
	var ground_low: Dictionary = jet.update_jet(PILOT, thrust, false, 0.2, true, null, DT)
	assert_bool(ground_low["arc_visible"]).is_true()

	# Vacío apretando propulsor: rojo parpadeante.
	var empty_jet = auto_free(JetScript.new())
	add_child(empty_jet)
	var empty: Dictionary = empty_jet.update_jet(PILOT, thrust, true, 0.0, true, null, DT)
	assert_bool(empty["arc_visible"]).is_true()
	assert_bool(empty_jet.get_arc_color().is_equal_approx(JetScript.EMPTY_COLOR)).is_true()
	assert_bool(empty["empty"]).is_true()

func test_rope_badge_matches_active_device() -> void:
	assert_str(RopeScript.badge_for_device("gamepad")).is_equal("RT")
	assert_str(RopeScript.badge_for_device("keyboard")).is_equal("E")
	assert_str(RopeScript.badge_for_device("touch")).is_equal("CUERDA")
	assert_str(RopeScript.badge_for_device("desconocido")).is_equal("E")

	var rope = auto_free(RopeScript.new())
	add_child(rope)
	var anchor := Vector3(240.0, 30.0, 0.0)
	var result: Dictionary = rope.update_rope_feedback(
		PILOT.origin, anchor, 64.0, true, false, false, "gamepad", null, DT)
	assert_str(result["badge"]).is_equal("RT")
	rope.update_rope_feedback(PILOT.origin, anchor, 64.0, true, false, false, "keyboard", null, DT)
	assert_str(rope.get_badge()).is_equal("E")
	rope.update_rope_feedback(PILOT.origin, anchor, 64.0, true, false, false, "touch", null, DT)
	assert_str(rope.get_badge()).is_equal("CUERDA")
	assert_str(RopeScript.format_distance(64.4)).is_equal("64 m")

func test_rope_tether_swing_cyan_to_reeling_gold() -> void:
	var rope = auto_free(RopeScript.new())
	add_child(rope)
	var anchor := Vector3(240.0, 20.0, 0.0)
	var swing: Dictionary = rope.update_rope_feedback(
		PILOT.origin, anchor, 20.0, true, true, false, "keyboard", null, DT)
	assert_str(swing["state"]).is_equal("SWING")
	assert_bool((swing["tether_color"] as Color).is_equal_approx(RopeScript.SWING_COLOR)).is_true()
	assert_bool(rope.get_tether_color().is_equal_approx(Color(0.15, 0.92, 1.0))).is_true()
	assert_bool(swing["tether_visible"]).is_true()
	assert_bool(swing["reticle_visible"]).is_false() # enganchada: sin retícula

	var reel: Dictionary = rope.update_rope_feedback(
		PILOT.origin, anchor, 20.0, true, true, true, "gamepad", null, DT)
	assert_str(reel["state"]).is_equal("REELING")
	assert_bool((reel["tether_color"] as Color).is_equal_approx(RopeScript.REEL_COLOR)).is_true()
	assert_bool(rope.get_tether_color().is_equal_approx(Color(1.0, 0.62, 0.12))).is_true()

	# Sin objetivo y suelta: IDLE, sin tether ni retícula.
	var idle: Dictionary = rope.update_rope_feedback(
		PILOT.origin, anchor, 0.0, false, false, false, "keyboard", null, DT)
	assert_str(idle["state"]).is_equal("IDLE")
	assert_bool(idle["tether_visible"]).is_false()

func test_catapult_fov_offset_smooth_and_bounded() -> void:
	var rope = auto_free(RopeScript.new())
	add_child(rope)
	assert_float(RopeScript.step_catapult_fov_offset(0.0, false, 0.0, DT)).is_equal_approx(0.0, EPS)
	var offset := 0.0
	var max_step := 0.0
	var previous := 0.0
	for _i in range(180):
		offset = RopeScript.step_catapult_fov_offset(offset, true, 0.0, DT)
		max_step = max(max_step, abs(offset - previous))
		previous = offset
		assert_bool(offset >= 0.0 and offset <= 5.0).is_true()
	assert_float(offset).is_equal_approx(5.0, 1e-3)
	assert_float(max_step).is_less_equal(RopeScript.FOV_RISE_RATE * DT + EPS)

	var fall_step := 0.0
	for _i in range(240):
		offset = RopeScript.step_catapult_fov_offset(offset, false, 0.0, DT)
		fall_step = max(fall_step, abs(offset - previous))
		previous = offset
		assert_bool(offset >= 0.0 and offset <= 5.0).is_true()
	assert_float(offset).is_equal_approx(0.0, 1e-3)
	assert_float(fall_step).is_less_equal(RopeScript.FOV_FALL_RATE * DT + EPS)

	# Alta velocidad sin retracción da un empuje parcial, nunca el máximo.
	var fast: float = RopeScript.step_catapult_fov_offset(0.0, false, 30.0, DT)
	assert_float(fast).is_less(5.0)
	assert_float(fast).is_greater(0.0)

func test_feedback_safe_in_headless_without_camera() -> void:
	var jet = auto_free(JetScript.new())
	var rope = auto_free(RopeScript.new())
	add_child(jet)
	add_child(rope)
	var jet_result: Dictionary = jet.update_jet(PILOT, Vector3.FORWARD, true, 0.6, false, null, DT)
	var rope_result: Dictionary = rope.update_rope_feedback(
		PILOT.origin, Vector3(240.0, 10.0, 0.0), 10.0, true, false, false, "keyboard", null, DT)
	assert_bool(jet_result["jet_visible"]).is_true()
	assert_bool(rope_result["reticle_visible"]).is_false() # sin cámara no proyecta
	assert_float(float(rope_result["fov_offset"])).is_greater_equal(0.0)
	print("FD325_T4 diegetic feedback: nozzles=%d arc=%s rope=%s fov=%.2f" % [
		jet.get_nozzles().size(), str(jet.is_arc_visible()), rope.get_state(),
		rope.get_fov_offset()])
