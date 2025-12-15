extends CanvasLayer

onready var item_list: ItemList = find_node("ItemList", true, false)
onready var start_recording_button: Button = find_node("StartRecordingButton", true, false)
onready var load_button: Button = find_node("LoadReplayButton", true, false)
onready var reset_button: Button = find_node("ResetButton", true, false)
onready var restart_level_button: Button = find_node("RestartLevelButton", true, false)
onready var return_to_menu_button: Button = find_node("ReturnToMenuButton", true, false)

func _ready() -> void:
	visible = false
	if start_recording_button:
		start_recording_button.connect("pressed", self, "_on_StartRecordingButton_pressed")
	if load_button:
		load_button.connect("pressed", self, "_on_LoadReplayButton_pressed")
		load_button.disabled = true
	if reset_button:
		reset_button.connect("pressed", self, "_on_ResetButton_pressed")
	if restart_level_button:
		restart_level_button.connect("pressed", self, "_on_RestartLevelButton_pressed")
	if return_to_menu_button:
		return_to_menu_button.connect("pressed", self, "_on_ReturnToMenuButton_pressed")
	if item_list:
		item_list.connect("item_selected", self, "_on_ItemList_item_selected")
	ReplayManager.connect("mode_changed", self, "_on_mode_changed")
	# MouseCapture.connect("capture_changed", self, "_on_capture_changed") # REMOVED
	_refresh_replay_list()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_panel()
		get_tree().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_debug_menu"):
		if get_tree().current_scene.name != "Menu":
			if visible:
				hide_panel()
			else:
				show_panel()
		get_tree().set_input_as_handled()

func show_panel():
	visible = true
	_set_touch_controls_active(false)
	MouseCapture.show_cursor(true) # Release mouse
	_refresh_replay_list()
	
	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		ReplayManager.recorder.recording_paused = true
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.get_playback_node().pause_playback()

func hide_panel():
	visible = false
	_set_touch_controls_active(true)
	MouseCapture.show_cursor(false) # Capture mouse

	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		if ReplayManager.recorder: ReplayManager.recorder.recording_paused = false
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		if ReplayManager.get_playback_node(): ReplayManager.get_playback_node().resume_playback()
	# In NONE or STOPPED mode, hiding the panel just captures the mouse and enables camera control.

func _set_touch_controls_active(active: bool) -> void:
	var touch_controls = get_tree().get_root().find_node("TouchControls", true, false)
	if touch_controls:
		touch_controls.visible = active
		touch_controls.set_process_input(active)


func _refresh_replay_list() -> void:
	if item_list:
		item_list.clear()
		var replays = ReplayManager.get_available_replays()
		for replay in replays:
			item_list.add_item(replay.get_basename())


func _on_mode_changed(new_mode: int) -> void:
	if new_mode == ReplayManager.ReplayMode.RECORDING or new_mode == ReplayManager.ReplayMode.PLAYBACK or new_mode == ReplayManager.ReplayMode.STOPPED:
		visible = false
	elif new_mode == ReplayManager.ReplayMode.NONE:
		visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	# This panel is now only for management, not status display.


func _on_StartRecordingButton_pressed() -> void:
	ReplayManager.start_recording()
	# The on_mode_changed signal will hide this panel

func _on_LoadReplayButton_pressed() -> void:
	if item_list:
		var selected = item_list.get_selected_items()
		if selected.size() > 0:
			var index = selected[0]
			if index < item_list.get_item_count():
				var replay_name = item_list.get_item_text(index)
				var path = "res://replays/" + replay_name + ".json"
				ReplayManager.start_playback(path)
				visible = false  # Hide panel after loading

func _on_ResetButton_pressed() -> void:
	ReplayManager.reset_replay()
	visible = false

func _on_RestartLevelButton_pressed() -> void:
	ReplayManager.reset_replay()
	SceneManager.restart_level()

func _on_ReturnToMenuButton_pressed() -> void:
	ReplayManager.reset_replay()
	SceneManager.return_to_menu()

func _on_ItemList_item_selected(index: int) -> void:
	load_button.disabled = false

# This function is removed as it conflicts with the desired UI behavior
#func _on_capture_changed(is_captured: bool) -> void:
#	if not is_captured and visible:
#		# Si el mouse se libera mientras el panel está abierto, cerrarlo
#		visible = false
#		_set_touch_controls_active(true)
#		MouseCapture.show_cursor(true)
#		if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
#			ReplayManager.recorder.recording_paused = false
#		elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
#			ReplayManager.get_playback_node().resume_playback()
#		else: # ReplayMode.NONE
#			ReplayManager.reset_replay()
