extends Node

# DebugConsoleManager.gd - Console screen registered in SuitOS.

const OYSShellScene = preload("res://core_v2/ui/retro/OYSShell.tscn")
const WidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
const ViewportInputScript = preload("res://core_v2/things/HoloTerminalViewportInput.gd")
const SHELL_FONT_SIZE := 28

signal state_changed()

var status_text: String = "OK"
var _viewport: Viewport = null

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	_ensure_viewport()
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager != null:
		if not scene_manager.is_connected("pre_scene_swap", self, "_on_pre_scene_swap"):
			scene_manager.connect("pre_scene_swap", self, "_on_pre_scene_swap")
		if not scene_manager.is_connected("scene_ready", self, "_on_scene_ready"):
			scene_manager.connect("scene_ready", self, "_on_scene_ready")
	call_deferred("_sync_registration")

func _ensure_viewport() -> void:
	if is_instance_valid(_viewport):
		return
	_viewport = ViewportInputScript.new()
	_viewport.name = "ConsoleViewport"
	_viewport.size = view_size()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(_viewport)
	var shell: Control = OYSShellScene.instance()
	shell.font_size = SHELL_FONT_SIZE
	_viewport.add_child(shell)
	shell.set_anchors_and_margins_preset(Control.PRESET_WIDE)

func _sync_registration(scene_root: Node = null) -> void:
	var suit_os = get_node_or_null("/root/SuitOS")
	if not is_instance_valid(suit_os):
		return
	var scene = scene_root if is_instance_valid(scene_root) else get_tree().current_scene
	if _is_gameplay_scene(scene):
		suit_os.register_screen(self)
	else:
		suit_os.unregister_screen(screen_id())

func _is_gameplay_scene(scene: Node) -> bool:
	if not is_instance_valid(scene):
		return true
	var path: String = String(scene.filename)
	return path.find("Menu.tscn") == -1 and path.find("Boot.tscn") == -1 \
		and path.find("RemoteControlHome.tscn") == -1

func _on_pre_scene_swap(_old_scene: Node, new_scene: Node, _params: Dictionary) -> void:
	if not _is_gameplay_scene(new_scene):
		_sync_registration(new_scene)

func _on_scene_ready(_path: String, scene_root: Node, _params: Dictionary) -> void:
	_sync_registration(scene_root)

func screen_id() -> String:
	return "system:console"

func screen_title() -> String:
	return "Consola"

func widget_scene() -> PackedScene:
	return WidgetScene

func view_scene() -> PackedScene:
	return OYSShellScene

func view_size() -> Vector2:
	return Vector2(1024, 576)

func view_hud_config() -> Dictionary:
	return {"depth": 0.4, "scale": 0.55, "background_alpha": 0.42}

func view_requires_input() -> bool:
	return true

func borrow_viewport() -> Viewport:
	_ensure_viewport()
	return _viewport

func enter_focus_mode() -> void:
	_ensure_viewport()
	_viewport.set_ui_mode(true)
	_viewport.set_use_system_mouse(false)
	_viewport.call_deferred("focus_command_input")

func exit_focus_mode() -> void:
	if is_instance_valid(_viewport):
		_viewport.set_ui_mode(false)

func forward_view_input(event: InputEvent) -> void:
	if not is_instance_valid(_viewport):
		return
	if event is InputEventKey:
		_viewport.process_key_event(event)
		return
	_viewport.set_use_system_mouse(false)
	if event is InputEventMouseMotion:
		_viewport.process_mouse_motion(event.relative)
	elif event is InputEventMouseButton:
		_viewport.process_mouse_click(event.button_index, event.pressed, event.doubleclick)

func widget_snapshot() -> Dictionary:
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"active": true,
		"focused": false,
		"can_focus": false,
		"status_text": status_text,
		"source": "online"
	}

func set_status_text(value: String) -> void:
	if status_text == value:
		return
	status_text = value
	emit_signal("state_changed")
