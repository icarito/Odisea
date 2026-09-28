extends GdUnitTestSuite

# test_signal_strength.gd - FD-319 Tarea 2: eje de senal por distancia del widget contextual.
# El estado sale de la lectura (signal_strength en el snapshot, o la distancia al prop fuente) y el
# parpadeo es solo presentacion: animar no cambia la lectura ni su estado.

const SuitOSWidgetHostScript = preload("res://core_v2/ui/hud/SuitOSWidgetHost.gd")
const HudWidgetScript = preload("res://core_v2/ui/hud/HudWidget.gd")
const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")

class FakeSource extends Spatial:
	pass

class FakeScreen extends Node:
	var declared_strength := 1.0
	func screen_id() -> String:
		return "test:signal_valve"
	func get_hud_signal_strength(_context: Dictionary = {}) -> float:
		return declared_strength

var _widget_host: Node = null

func before() -> void:
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)

func before_test() -> void:
	_widget_host = auto_free(SuitOSWidgetHostScript.new())
	_widget_host.name = "SuitOSWidgetHost"
	get_tree().root.add_child(_widget_host)
	_widget_host.signal_full_distance = 2.0
	_widget_host.signal_lost_distance = 10.0

func after_test() -> void:
	if is_instance_valid(_widget_host):
		_widget_host.free()
	_widget_host = null
	yield(await_idle_frame(), "completed")

# --- contrato de lectura: signal_strength en el snapshot decide el estado ---

func test_declared_strength_maps_to_states() -> void:
	_widget_host.show_context({"title": "V", "signal_strength": 0.9})
	assert_str(_widget_host.context_signal_state()).is_equal("in_range")
	assert_float(_widget_host.context_signal_strength()).is_equal(0.9)

	_widget_host.show_context({"title": "V", "signal_strength": 0.4})
	assert_str(_widget_host.context_signal_state()).is_equal("borderline")
	assert_float(_widget_host.context_signal_strength()).is_equal(0.4)

	_widget_host.show_context({"title": "V", "signal_strength": 0.05})
	assert_str(_widget_host.context_signal_state()).is_equal("out_of_range")
	assert_float(_widget_host.context_signal_strength()).is_equal(0.05)
	_widget_host.clear_context()

func test_thresholds_are_the_boundaries() -> void:
	_widget_host.signal_solid_threshold = 0.6
	_widget_host.signal_lost_threshold = 0.2
	assert_str(_widget_host._signal_state_for(0.6)).is_equal("in_range")
	assert_str(_widget_host._signal_state_for(0.59)).is_equal("borderline")
	assert_str(_widget_host._signal_state_for(0.2)).is_equal("borderline")
	assert_str(_widget_host._signal_state_for(0.19)).is_equal("out_of_range")

func test_distance_curve_is_linear_between_thresholds() -> void:
	_widget_host.signal_full_distance = 2.0
	_widget_host.signal_lost_distance = 10.0
	assert_float(_widget_host._signal_strength_for_distance(-1.0)).is_equal(1.0)
	assert_float(_widget_host._signal_strength_for_distance(0.5)).is_equal(1.0)
	assert_float(_widget_host._signal_strength_for_distance(2.0)).is_equal(1.0)
	assert_float(_widget_host._signal_strength_for_distance(6.0)).is_equal(0.5)
	assert_float(_widget_host._signal_strength_for_distance(10.0)).is_equal(0.0)
	assert_float(_widget_host._signal_strength_for_distance(50.0)).is_equal(0.0)

# --- integracion: sin signal_strength, se deriva de la distancia al prop fuente ---

func test_far_source_is_out_of_range_and_not_offline() -> void:
	var player: Spatial = _widget_host._signal_player()
	if player == null:
		player = KinematicBody.new()
		player.name = "SignalTestPlayer"
		add_child(player)
		player.add_to_group("player")
	var source := FakeSource.new()
	source.name = "ValveFar"
	add_child(source)
	source.global_transform.origin = player.global_transform.origin + Vector3(0.0, 0.0, 50.0)

	_widget_host.show_context({"title": "Válvula", "interactable": source})
	assert_str(_widget_host.context_signal_state()).is_equal("out_of_range")
	assert_float(_widget_host.context_signal_strength()).is_equal(0.0)
	# FUERA_DE_RANGO sigue mostrando el widget: es un estado previo a irse, no la desaparicion.
	var widget = _widget_host.get_widget_root().get_node_or_null("SuitOS_Context")
	assert_object(widget).is_not_null()
	assert_bool(widget.visible).is_true()
	# No es offline (Manual §7): el contrato de HudWidget.is_offline es otro eje.
	assert_bool(HudWidgetScript.is_offline({"source": "online"})).is_false()
	source.queue_free()
	_widget_host.clear_context()

func test_near_source_is_solid() -> void:
	var player: Spatial = _widget_host._signal_player()
	if player == null:
		player = KinematicBody.new()
		player.name = "SignalTestPlayer"
		add_child(player)
		player.add_to_group("player")
	var source := FakeSource.new()
	source.name = "ValveNear"
	add_child(source)
	source.global_transform.origin = player.global_transform.origin

	_widget_host.show_context({"title": "Válvula", "interactable": source})
	assert_str(_widget_host.context_signal_state()).is_equal("in_range")
	assert_float(_widget_host.context_signal_strength()).is_equal(1.0)
	source.queue_free()
	_widget_host.clear_context()

# --- presentacion: flicker y alpha no son fuente de estado ---

func test_borderline_flickers_but_reading_stays_put() -> void:
	_widget_host.show_context({"title": "V", "signal_strength": 0.4})
	var before: float = _widget_host.context_signal_strength()
	var widget = _widget_host.get_widget_root().get_node_or_null("SuitOS_Context")
	var lows := []
	var highs := []
	for i in range(16):
		_widget_host._tick_context_signal(0.05)
		lows.append(widget.modulate.a)
		highs.append(widget.modulate.a)
		# La lectura es data: animar no la mueve.
		assert_float(_widget_host.context_signal_strength()).is_equal(before)
		assert_str(_widget_host.context_signal_state()).is_equal("borderline")
	var spread: float = float(highs.max()) - float(lows.min())
	assert_float(spread).is_greater(0.05)
	_widget_host.clear_context()

func test_in_range_is_solid() -> void:
	_widget_host.show_context({"title": "V", "signal_strength": 1.0})
	var widget = _widget_host.get_widget_root().get_node_or_null("SuitOS_Context")
	_widget_host._tick_context_signal(0.1)
	assert_float(widget.modulate.a).is_equal(1.0)
	_widget_host.clear_context()

func test_clear_context_resets_signal() -> void:
	_widget_host.show_context({"title": "V", "signal_strength": 0.05})
	_widget_host.clear_context()
	assert_str(_widget_host.context_signal_state()).is_equal("in_range")
	assert_float(_widget_host.context_signal_strength()).is_equal(1.0)

# --- HUDableComponent: el prop declara la senal y viaja en la lectura ---

func test_hudable_declares_signal_strength() -> void:
	var parent := FakeScreen.new()
	parent.name = "SignalValve"
	add_child(parent)
	var comp = HUDableComponentScript.new()
	parent.add_child(comp)
	parent.declared_strength = 0.35
	assert_float(comp.signal_strength({})).is_equal(0.35)
	var snap: Dictionary = comp.widget_snapshot()
	assert_float(float(snap.get("signal_strength", -1.0))).is_equal(0.35)
	# Un valor fuera de rango se recorta a 0..1.
	parent.declared_strength = 1.8
	assert_float(comp.signal_strength({})).is_equal(1.0)
	parent.queue_free()

func test_hudable_defaults_signal_strength_to_full() -> void:
	var bare := Node.new()
	add_child(bare)
	var comp = HUDableComponentScript.new()
	bare.add_child(comp)
	assert_float(comp.signal_strength({})).is_equal(1.0)
	var snap: Dictionary = comp.widget_snapshot()
	assert_float(float(snap.get("signal_strength", -1.0))).is_equal(1.0)
	bare.queue_free()
