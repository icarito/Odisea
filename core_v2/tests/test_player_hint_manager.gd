extends GdUnitTestSuite

class FakeReactive extends Node:
	signal activated()
	signal deactivated()
	var is_active := true
	func get_interaction_prompt() -> String:
		return "Cerrar" if is_active else "Abrir"
	func interact() -> void:
		set_active(not is_active)
	func set_active(value: bool) -> void:
		is_active = value
		if value:
			emit_signal("activated")
		else:
			emit_signal("deactivated")

const PlayerHintManager = preload("res://core_v2/autoloads/PlayerHintManager.gd")

func before_test() -> void:
	var screen_fx = get_tree().root.get_node_or_null("ScreenEffectsManager")
	if screen_fx and screen_fx.has_method("reset"):
		screen_fx.reset(true)
	var session = get_tree().root.get_node_or_null("SessionManager")
	if session and "player" in session and is_instance_valid(session.player):
		if "input_provider" in session.player and is_instance_valid(session.player.input_provider):
			session.player.input_provider.hardware_input_enabled = true

func test_interaction_hint_is_visible_text_when_interactive() -> void:
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_interaction_hint("Abrir puerta")
	assert_str(manager.get_visible_text()).is_equal("Abrir puerta")
	manager.queue_free()

func test_manual_hint_suppresses_interaction_until_cleared() -> void:
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_interaction_hint("Abrir puerta")
	manager.show_manual_hint("Read the panel", 5.0)
	assert_str(manager.get_visible_text()).is_equal("Read the panel")
	manager.clear_manual_hint()
	assert_str(manager.get_visible_text()).is_equal("Abrir puerta")
	manager.queue_free()

func test_manual_hint_duration_clamps_to_thirty_seconds() -> void:
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_manual_hint("Too long", 120.0)
	var expires_at := float(manager.get("_manual_expires_at"))
	var now := OS.get_ticks_msec() / 1000.0
	assert_bool(expires_at - now <= 30.1).is_true()
	assert_bool(expires_at - now > 29.0).is_true()
	manager.queue_free()

func test_non_interactive_mode_hides_and_rejects_manual_hints() -> void:
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_interaction_hint("Abrir puerta")
	manager.set_interactive(false)
	assert_str(manager.get_visible_text()).is_equal("")
	manager.show_manual_hint("Should not show", 5.0)
	assert_str(String(manager.get("_manual_text"))).is_equal("")
	manager.set_interactive(true)
	assert_str(manager.get_visible_text()).is_equal("Abrir puerta")
	manager.queue_free()


func test_interaction_hint_uses_the_context_widget_and_clears_it() -> void:
	# FD-310: con un interactuable en rango y un slot libre, el hint de interaccion va como widget
	# de contexto; el texto sigue disponible (lo replica el control remoto).
	for i in range(4):
		SuitOS.clear_slot(i)
	var manager = PlayerHintManager.new()
	add_child(manager)
	var source := Node.new()
	source.name = "Caja_Herramientas"
	add_child(source)
	manager.show_interaction_hint("Interactuar", source)
	assert_bool(bool(manager.get("_context_showing"))).is_true()
	assert_str(manager.get_visible_text()).is_equal("Interactuar")
	manager.clear_interaction_hint()
	assert_bool(bool(manager.get("_context_showing"))).is_false()
	var host = manager.call("_context_host")
	if is_instance_valid(host):
		var context = host.get_widget_root().get_node_or_null("SuitOS_Context")
		assert_bool(context == null or context.is_queued_for_deletion()).is_true()
	source.queue_free()
	manager.queue_free()


func test_interaction_hint_widget_sits_at_the_bottom_centered() -> void:
	# Ya no hay subtitulo propio: todo sale por el widget de contexto, abajo-centro.
	for i in range(4):
		SuitOS.clear_slot(i)
	var manager = PlayerHintManager.new()
	add_child(manager)
	var source := Node.new()
	source.name = "Caja_Herramientas"
	add_child(source)
	manager.show_interaction_hint("Interactuar", source)
	var host = manager.call("_context_host")
	if is_instance_valid(host):
		var widget = host.get_widget_root().get_node_or_null("SuitOS_Context")
		assert_object(widget).is_not_null()
		var viewport_size: Vector2 = host.get_viewport_rect().size
		assert_float(widget.rect_position.y).is_greater(viewport_size.y * 0.5)
		assert_float(widget.rect_position.x).is_greater(viewport_size.x * 0.1)
		assert_float(widget.rect_position.x).is_less(viewport_size.x * 0.9)
	manager.clear_interaction_hint()
	source.queue_free()
	manager.queue_free()


func test_freed_interaction_source_drops_the_context_widget() -> void:
	# En low-tier el prop puede salir del stream y liberarse con el jugador todavia en rango:
	# el hint no debe quedar pegado mostrando una fuente muerta.
	for i in range(4):
		SuitOS.clear_slot(i)
	var manager = PlayerHintManager.new()
	add_child(manager)
	var source := Node.new()
	source.name = "Caja_Herramientas"
	add_child(source)
	manager.show_interaction_hint("Interactuar", source)
	assert_bool(bool(manager.get("_context_showing"))).is_true()
	source.free()
	manager.call("_refresh_visible_hint")
	assert_str(manager.get_visible_text()).is_equal("")
	assert_bool(bool(manager.get("_context_showing"))).is_false()
	manager.queue_free()


func test_interaction_hint_without_source_still_shows() -> void:
	# El hint de interaccion sin nodo (p. ej. SignagePanel) no debe confundirse con
	# una fuente liberada: su texto sigue vigente.
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_interaction_hint("Leer cartel")
	assert_str(manager.get_visible_text()).is_equal("Leer cartel")
	manager.call("_refresh_visible_hint")
	assert_str(manager.get_visible_text()).is_equal("Leer cartel")
	manager.queue_free()


func test_context_widget_is_reactive_to_the_source_state() -> void:
	# El verbo del pie cambia solo cuando el prop cambia de estado (Abrir <-> Cerrar).
	for i in range(4):
		SuitOS.clear_slot(i)
	var manager = PlayerHintManager.new()
	add_child(manager)
	var source := FakeReactive.new()
	source.name = "Valve"
	add_child(source)
	manager.show_interaction_hint("Cerrar", source)
	assert_str(manager.get_visible_text()).is_equal("Cerrar")
	source.set_active(false)
	assert_str(manager.get_visible_text()).is_equal("Abrir")
	source.set_active(true)
	assert_str(manager.get_visible_text()).is_equal("Cerrar")
	manager.clear_interaction_hint()
	source.queue_free()
	manager.queue_free()
