extends GdUnitTestSuite

# test_hudable.gd - Tests for HUDableComponent and InteractableEntity integration (FD-296 F1)

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")

class CustomParent:
	extends Spatial

	var relevance_value: float = 0.85
	var last_action: String = ""

	func get_hud_relevance(_context: Dictionary) -> float:
		return relevance_value

	func get_hud_allowed_actions() -> Array:
		return ["ping", "reboot"]

	func perform_hud_action(op: String, _args: Dictionary) -> Dictionary:
		if op in get_hud_allowed_actions():
			last_action = op
			return {"ok": true, "result": "parent_executed"}
		return {"ok": false, "error": "Denied"}

	func get_hud_snapshot() -> Dictionary:
		return {
			"proto": 1,
			"id": "custom_parent",
			"status": "OK",
			"custom_data": 42
		}

func before_test() -> void:
	SuitOS.unpin_screen()
	SuitOS.close_screen()
	SuitOS.set_hud_mode_active(false)
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

func test_hudable_component_lifecycle_and_auto_registration() -> void:
	var comp = auto_free(HUDableComponentScript.new())
	comp.hud_screen_id = "term_01"
	comp.hud_screen_title = "Terminal Alpha"
	comp.default_relevance = 0.6

	assert_bool(SuitOS.has_screen("term_01")).is_false()

	get_tree().root.add_child(comp)
	yield(get_tree(), "idle_frame")

	assert_bool(SuitOS.has_screen("term_01")).is_true()
	assert_str(SuitOS.get_screen("term_01").screen_title()).is_equal("Terminal Alpha")

	get_tree().root.remove_child(comp)
	yield(get_tree(), "idle_frame")

	assert_bool(SuitOS.has_screen("term_01")).is_false()

func test_hudable_contract_defaults() -> void:
	var comp = auto_free(HUDableComponentScript.new())
	comp.hud_screen_id = "sys_default"
	comp.hud_screen_title = "Default System"
	comp.default_relevance = 0.45
	comp.allowed_actions = ["reset", "calibrate"]

	assert_str(comp.screen_id()).is_equal("sys_default")
	assert_str(comp.screen_title()).is_equal("Default System")
	assert_float(comp.relevance({})).is_equal(0.45)
	assert_array(comp.allowed_actions()).contains(["reset", "calibrate"])

	var snap = comp.widget_snapshot()
	assert_int(snap.get("proto", 0)).is_equal(1)
	assert_str(snap.get("id", "")).is_equal("sys_default")
	assert_str(snap.get("source", "")).is_equal("online")

	var act_res = comp.perform_action("reset", {})
	assert_bool(act_res.get("ok", false)).is_true()

	var act_fail = comp.perform_action("invalid_op", {})
	assert_bool(act_fail.get("ok", true)).is_false()

func test_hudable_parent_delegation() -> void:
	var parent: CustomParent = auto_free(CustomParent.new())
	var comp = auto_free(HUDableComponentScript.new())
	comp.hud_screen_id = "custom_parent"
	parent.add_child(comp)

	get_tree().root.add_child(parent)
	yield(get_tree(), "idle_frame")

	assert_bool(SuitOS.has_screen("custom_parent")).is_true()
	assert_float(comp.relevance({})).is_equal(0.85)
	assert_array(comp.allowed_actions()).contains(["ping", "reboot"])

	var snap = comp.widget_snapshot()
	assert_int(snap.get("custom_data", 0)).is_equal(42)

	var res = SuitOS.perform_action("custom_parent", "ping", {})
	assert_bool(res.get("ok", false)).is_true()
	assert_str(parent.last_action).is_equal("ping")

	get_tree().root.remove_child(parent)

func test_view_transition_origin_default_returns_empty_dict() -> void:
	var comp = auto_free(HUDableComponentScript.new())
	var origin: Dictionary = comp.view_transition_origin()
	assert_dict(origin).is_empty()

func test_interactable_entity_integration() -> void:
	var entity: InteractableEntity = auto_free(InteractableEntity.new())
	var comp = auto_free(HUDableComponentScript.new())
	comp.hud_screen_id = "entity_hud"
	comp.hud_screen_title = "Entity HUD"
	entity.add_child(comp)

	get_tree().root.add_child(entity)
	yield(get_tree(), "idle_frame")

	assert_object(entity.get_hudable()).is_equal(comp)
	assert_bool(SuitOS.has_screen("entity_hud")).is_true()

	get_tree().root.remove_child(entity)
