extends GdUnitTestSuite

const PlayerHintManager = preload("res://core_v2/autoloads/PlayerHintManager.gd")

func test_interaction_hint_is_visible_text_when_interactive() -> void:
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_interaction_hint("[F] Open Door")
	assert_str(manager.get_visible_text()).is_equal("[F] Open Door")
	manager.queue_free()

func test_manual_hint_suppresses_interaction_until_cleared() -> void:
	var manager = PlayerHintManager.new()
	add_child(manager)
	manager.show_interaction_hint("[F] Open Door")
	manager.show_manual_hint("Read the panel", 5.0)
	assert_str(manager.get_visible_text()).is_equal("Read the panel")
	manager.clear_manual_hint()
	assert_str(manager.get_visible_text()).is_equal("[F] Open Door")
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
	manager.show_interaction_hint("[F] Open Door")
	manager.set_interactive(false)
	assert_str(manager.get_visible_text()).is_equal("")
	manager.show_manual_hint("Should not show", 5.0)
	assert_str(String(manager.get("_manual_text"))).is_equal("")
	manager.set_interactive(true)
	assert_str(manager.get_visible_text()).is_equal("[F] Open Door")
	manager.queue_free()
