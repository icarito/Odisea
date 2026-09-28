extends GdUnitTestSuite

# test_signal_strength.gd - Tests for distance signal_strength degradation and FUERA_DE_RANGO state (FD-319 T2)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")
const InteractableSlotScreenScript = preload("res://core_v2/ui/hud/InteractableSlotScreen.gd")
const InteractableSlotWidgetScript = preload("res://core_v2/ui/hud/InteractableSlotWidget.gd")

func test_hudable_component_signal_strength_snapshot() -> void:
	var comp = auto_free(HUDableComponentScript.new())
	comp.hud_screen_id = "test_signal_comp"

	assert_float(comp.default_signal_strength).is_equal(1.0)
	assert_float(comp.signal_strength({})).is_equal(1.0)

	var snap: Dictionary = comp.widget_snapshot()
	assert_bool(snap.has("signal_strength")).is_true()
	assert_float(float(snap.get("signal_strength", 0.0))).is_equal(1.0)

func test_hudable_component_distance_calculation() -> void:
	var spatial = auto_free(Spatial.new())
	get_tree().root.add_child(spatial)
	spatial.transform.origin = Vector3(0, 0, 5)

	var comp = auto_free(HUDableComponentScript.new())
	comp.hud_screen_id = "test_dist_comp"
	spatial.add_child(comp)

	# Distance to player at (0, 0, 0) is 5.0m. Max distance is 10.0m.
	var context := {
		"player_position": Vector3.ZERO,
		"max_distance": 10.0
	}
	var sig: float = comp.signal_strength(context)
	assert_float(sig).is_equal_approx(0.5, 0.01)

	get_tree().root.remove_child(spatial)

func test_interactable_slot_screen_signal_strength() -> void:
	var spatial = auto_free(Spatial.new())
	spatial.name = "TestDoor"
	get_tree().root.add_child(spatial)
	spatial.transform.origin = Vector3(0, 0, 2)

	var screen = auto_free(InteractableSlotScreenScript.new())
	screen.bind(spatial)

	assert_bool(screen.is_valid()).is_true()

	var context := {
		"player_position": Vector3.ZERO,
		"max_distance": 4.0
	}
	assert_float(screen.signal_strength(context)).is_equal_approx(0.5, 0.01)

	var snap: Dictionary = screen.widget_snapshot()
	assert_bool(snap.has("signal_strength")).is_true()

	get_tree().root.remove_child(spatial)

func test_interactable_slot_widget_visual_states() -> void:
	var widget = auto_free(InteractableSlotWidgetScript.new())

	# 1. Solid state (in range, signal_strength = 1.0)
	widget.set_snapshot({"title": "Prop", "action": "Use", "signal_strength": 1.0})
	assert_float(widget.get_signal_strength()).is_equal(1.0)
	assert_bool(widget.is_fuera_de_rango()).is_false()
	assert_float(widget.modulate.a).is_equal(1.0)

	# 2. Boundary state (smooth fade, signal_strength = 0.5)
	widget.set_snapshot({"title": "Prop", "action": "Use", "signal_strength": 0.5})
	assert_float(widget.get_signal_strength()).is_equal(0.5)
	assert_bool(widget.is_fuera_de_rango()).is_false()
	assert_float(widget.modulate.a).is_equal_approx(0.5, 0.01)

	# 3. Lejano flicker state (low signal, signal_strength = 0.2)
	widget.set_snapshot({"title": "Prop", "action": "Use", "signal_strength": 0.2})
	assert_float(widget.get_signal_strength()).is_equal(0.2)
	assert_bool(widget.is_fuera_de_rango()).is_false()
	assert_bool(widget.modulate.a < 0.8).is_true()

	# 4. FUERA_DE_RANGO state
	widget.set_snapshot({
		"title": "Prop",
		"action": "Use",
		"signal_strength": 0.0,
		"out_of_range": true,
		"status": "FUERA_DE_RANGO"
	})
	assert_bool(widget.is_fuera_de_rango()).is_true()
	assert_float(widget.modulate.a).is_equal_approx(0.25, 0.01)
	var status_label = widget.get_node_or_null("Row/VBox/Status")
	assert_object(status_label).is_not_null()
	assert_str((status_label as Label).text).is_equal("[FUERA DE RANGO]")

	# 5. Offline state (FUERA_DE_RANGO does not overwrite is_offline)
	widget.set_snapshot({
		"title": "Prop",
		"source": "offline",
		"signal_strength": 0.0
	})
	assert_bool(widget.is_offline({"source": "offline"})).is_true()
	assert_str((status_label as Label).text).is_equal("[OFFLINE]")
	assert_float(widget.modulate.a).is_equal_approx(0.5, 0.01)

func test_signal_strength_determinism() -> void:
	var widget1 = auto_free(InteractableSlotWidgetScript.new())
	var widget2 = auto_free(InteractableSlotWidgetScript.new())

	var snap := {"title": "Determinism", "signal_strength": 0.15}
	widget1.set_snapshot(snap)
	widget2.set_snapshot(snap)

	assert_float(widget1.modulate.a).is_equal(widget2.modulate.a)
	assert_bool(widget1.is_fuera_de_rango()).is_equal(widget2.is_fuera_de_rango())
