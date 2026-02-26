tool
extends BaseZoneV2

class_name TransferZoneV2

export(String, FILE, "*.tscn") var target_scene_path := ""
export(String) var target_spawn_id := ""
export(String, "fade", "loading", "none") var transition := "fade"
export(bool) var preserve_player_state := true
export(bool) var show_loading := true
export(bool) var trigger_once := true

var _consumed := false

func _on_zone_entered(body: Node):
	if not body or not body.is_in_group("player"):
		return
	if trigger_once and _consumed:
		return

	if target_scene_path.strip_edges() == "":
		printerr("[TransferZoneV2] Missing target_scene_path on ", name)
		return

	var scene_manager = get_node_or_null("/root/SceneManager")
	if not scene_manager or not scene_manager.has_method("goto_scene"):
		printerr("[TransferZoneV2] SceneManager autoload missing")
		return

	_consumed = true
	var state = scene_manager.goto_scene(target_scene_path, {
		"transition": transition,
		"target_spawn_id": target_spawn_id,
		"preserve_player_state": preserve_player_state,
		"show_loading": show_loading
	})
	if state is GDScriptFunctionState:
		yield(state, "completed")

	if not trigger_once:
		_consumed = false
