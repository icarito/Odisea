extends GdUnitTestSuite

# test_holoterminal_hudable.gd - Unit tests for HoloTerminalHUDable (FD-296 F1.5)

const HoloTerminalHUDableScript = preload("res://core_v2/components/HoloTerminalHUDable.gd")

var _terminal: HoloTerminalV2 = null
var _hudable: Node = null

func before_test() -> void:
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)

	_terminal = HoloTerminalV2.new()
	_terminal.name = "TestTerminal"
	_terminal.filename = "res://core_v2/tests/fixtures/test_terminal.tscn"

	_hudable = HoloTerminalHUDableScript.new()
	_hudable.name = "HoloTerminalHUDable"
	_terminal.add_child(_hudable)
	add_child(_terminal)

func after_test() -> void:
	if is_instance_valid(_terminal):
		_terminal.free()

func test_screen_id_stability() -> void:
	var id1: String = _hudable.screen_id()
	assert_str(id1).starts_with("holoterminal:")
	assert_str(id1).is_equal("holoterminal:res://core_v2/tests/fixtures/test_terminal.tscn")

	# Override check
	_hudable.hud_screen_id = "custom:id_override"
	assert_str(_hudable.screen_id()).is_equal("custom:id_override")

func test_widget_snapshot_json_safe() -> void:
	_terminal.is_active = true
	var snap: Dictionary = _hudable.widget_snapshot()

	assert_bool(_is_json_safe(snap)).is_true()
	assert_int(int(snap.get("proto", 0))).is_equal(1)
	assert_str(String(snap.get("id", ""))).is_equal(_hudable.screen_id())
	assert_bool(bool(snap.get("active", false))).is_true()
	assert_bool(bool(snap.get("focused", false))).is_false()
	assert_array(snap.get("position", [])).has_size(3)

func test_view_scene_null_and_view_is_source_true() -> void:
	assert_object(_hudable.view_scene()).is_null()
	assert_bool(_hudable.view_is_source()).is_true()

func test_view_transition_origin_without_rig_returns_empty() -> void:
	_terminal.allow_focus_mode = true
	var origin: Dictionary = _hudable.view_transition_origin()
	assert_dict(origin).is_empty()

func test_view_transition_origin_with_focused_rig_returns_path() -> void:
	_terminal.allow_focus_mode = true
	var cinematic_setup := Spatial.new()
	cinematic_setup.name = "CinematicSetup"
	var focused_rig := Spatial.new()
	focused_rig.name = "FocusedRig"
	cinematic_setup.add_child(focused_rig)
	_terminal.add_child(cinematic_setup)

	var origin: Dictionary = _hudable.view_transition_origin()
	assert_str(String(origin.get("kind", ""))).is_equal("focus_rig")
	assert_str(String(origin.get("path", ""))).is_equal(String(focused_rig.get_path()))

	_terminal.allow_focus_mode = false
	assert_dict(_hudable.view_transition_origin()).is_empty()

func test_relevance_monotonic_with_distance() -> void:
	_terminal.translation = Vector3(0, 0, 0)
	_hudable.default_relevance = 0.1

	var context_close := {"player_position": [1.0, 0.0, 0.0]}
	var context_far := {"player_position": [10.0, 0.0, 0.0]}
	var context_focus := {"player_position": [1.0, 0.0, 0.0], "focus_id": _hudable.screen_id()}

	var rel_close: float = _hudable.relevance(context_close)
	var rel_far: float = _hudable.relevance(context_far)
	var rel_focus: float = _hudable.relevance(context_focus)

	assert_bool(rel_close > rel_far).is_true()
	assert_bool(rel_focus > rel_close).is_true()

func _is_json_safe(value) -> bool:
	var t = typeof(value)
	if t in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_REAL, TYPE_STRING]:
		return true
	elif t == TYPE_ARRAY:
		for item in value:
			if not _is_json_safe(item):
				return false
		return true
	elif t == TYPE_DICTIONARY:
		for key in value.keys():
			if typeof(key) != TYPE_STRING:
				return false
			if not _is_json_safe(value[key]):
				return false
		return true
	return false
