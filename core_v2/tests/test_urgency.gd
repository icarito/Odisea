extends GdUnitTestSuite

# test_urgency.gd - FD-319 T3: el canal de urgencia, ortogonal al color.
#
# Cubre los dos contratos de la tarea:
#   1) los tokens de nivel y la regla pura OdiseaOSTheme.resolve_urgency();
#   2) HudWidget: el snapshot trae "urgency" (y opcional "default_urgency") y el widget lo pinta.

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")
const HudWidgetScript = preload("res://core_v2/ui/hud/HudWidget.gd")

func test_four_levels_are_ordered_and_orthogonal_to_color() -> void:
	assert_int(OdiseaOSTheme.urgency_level(OdiseaOSTheme.URGENCY_QUIET)).is_equal(0)
	assert_int(OdiseaOSTheme.urgency_level(OdiseaOSTheme.URGENCY_NOTICE)).is_equal(1)
	assert_int(OdiseaOSTheme.urgency_level(OdiseaOSTheme.URGENCY_URGENT)).is_equal(2)
	assert_int(OdiseaOSTheme.urgency_level(OdiseaOSTheme.URGENCY_ALARM)).is_equal(3)
	# La urgencia nunca trae color propio: si lo trajera, pisaria la identidad del sistema.
	for level_name in OdiseaOSTheme.URGENCY_ORDER:
		var token: Dictionary = OdiseaOSTheme.urgency_token(level_name)
		for value in token.values():
			assert_bool(typeof(value) == TYPE_COLOR) \
				.override_failure_message("%s no puede traer color" % level_name).is_false()
	# La progresion que pide el diseno: notice = borde sutil; urgent = pulso lento; alarm = rapido + badge.
	assert_float(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_QUIET).border_alpha).is_equal(0.0)
	assert_float(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_NOTICE).border_alpha).is_greater(0.0)
	assert_bool(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_ALARM).badge).is_true()
	assert_bool(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_URGENT).badge).is_false()
	assert_float(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_URGENT).pulse_hz) \
		.is_less(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_ALARM).pulse_hz)

func test_unknown_level_falls_back_to_quiet() -> void:
	assert_str(OdiseaOSTheme.normalize_urgency("banana")).is_equal(OdiseaOSTheme.URGENCY_QUIET)
	assert_int(OdiseaOSTheme.urgency_level("")).is_equal(0)

func test_resolve_never_goes_below_the_base() -> void:
	assert_str(OdiseaOSTheme.resolve_urgency("urgent", "quiet", "quiet")).is_equal("urgent")
	assert_str(OdiseaOSTheme.resolve_urgency("notice", "quiet", "")).is_equal("notice")

func test_resolve_elevates_at_most_one_level_per_tick() -> void:
	var step_1 := OdiseaOSTheme.resolve_urgency("quiet", "alarm", "quiet")
	assert_str(step_1).is_equal("notice")
	var step_2 := OdiseaOSTheme.resolve_urgency("quiet", "alarm", step_1)
	assert_str(step_2).is_equal("urgent")
	var step_3 := OdiseaOSTheme.resolve_urgency("quiet", "alarm", step_2)
	assert_str(step_3).is_equal("alarm")
	# Ya en el techo, un tick mas lo deja igual.
	assert_str(OdiseaOSTheme.resolve_urgency("quiet", "alarm", step_3)).is_equal("alarm")

func test_resolve_drops_immediately_but_not_below_the_base() -> void:
	assert_str(OdiseaOSTheme.resolve_urgency("quiet", "quiet", "alarm")).is_equal("quiet")
	assert_str(OdiseaOSTheme.resolve_urgency("urgent", "quiet", "alarm")).is_equal("urgent")

func test_resolve_first_evaluation_starts_at_base_and_climbs_one_step() -> void:
	assert_str(OdiseaOSTheme.resolve_urgency("notice", "alarm", "")).is_equal("urgent")
	assert_str(OdiseaOSTheme.resolve_urgency("quiet", "urgent", "")).is_equal("notice")

func test_pulse_alpha_is_flat_without_pulse_and_bounded_with_it() -> void:
	assert_float(OdiseaOSTheme.urgency_pulse_alpha(OdiseaOSTheme.URGENCY_NOTICE, 3.7)).is_equal(1.0)
	var min_alpha := float(OdiseaOSTheme.urgency_token(OdiseaOSTheme.URGENCY_ALARM).pulse_min_alpha)
	var seen := {}
	for i in range(24):
		var alpha := OdiseaOSTheme.urgency_pulse_alpha(OdiseaOSTheme.URGENCY_ALARM, float(i) * 0.05)
		assert_float(alpha).is_greater_equal(min_alpha)
		assert_float(alpha).is_less_equal(1.0)
		seen[int(round(alpha * 1000.0))] = true
	# El pulso realmente oscila dentro del periodo muestreado.
	assert_int(seen.size()).is_greater(1)

func _new_widget() -> Control:
	var widget: Control = auto_free(HudWidgetScript.new())
	add_child(widget)
	return widget

func test_widget_paints_the_urgency_that_comes_in_the_snapshot() -> void:
	var widget: Control = _new_widget()
	widget.set_snapshot({"urgency": "alarm"})
	assert_str(widget.urgency()).is_equal("alarm")
	assert_bool(widget.urgency_token().badge).is_true()
	widget.set_snapshot({"urgency": "notice"})
	assert_str(widget.urgency()).is_equal("notice")

func test_widget_applies_the_base_floor_with_a_one_step_ramp() -> void:
	var widget: Control = _new_widget()
	# Primera evaluacion: un escalon por tick desde la base.
	widget.set_snapshot({"default_urgency": "quiet", "urgency": "alarm"})
	assert_str(widget.urgency()).is_equal("notice")
	widget.set_snapshot({"default_urgency": "quiet", "urgency": "alarm"})
	assert_str(widget.urgency()).is_equal("urgent")
	# El prop nunca baja de su base aunque el contexto pida menos.
	widget.set_snapshot({"default_urgency": "urgent", "urgency": "quiet"})
	assert_str(widget.urgency()).is_equal("urgent")

func test_widget_is_quiet_when_offline() -> void:
	var widget: Control = _new_widget()
	widget.set_snapshot({"urgency": "alarm"})
	assert_str(widget.urgency()).is_equal("alarm")
	widget.set_snapshot({"source": "offline", "urgency": "alarm"})
	assert_str(widget.urgency()).is_equal("quiet")

func test_widget_exposes_the_pulse_curve_of_its_level() -> void:
	var widget: Control = _new_widget()
	widget.set_snapshot({"urgency": "alarm"})
	assert_float(widget.urgency_pulse_alpha(0.0)).is_greater_equal(0.35)
	assert_float(widget.urgency_pulse_alpha(0.25)).is_less_equal(1.0)
