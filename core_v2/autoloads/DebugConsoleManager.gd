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
	# El input lo maneja el overlay (surface_uv, absoluto). Sin esto el Viewport procesaba el mouse
	# real por su cuenta ademas del cursor de la superficie (mismo estandar que HoloTerminalV2).
	_viewport.gui_disable_input = true
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
	# Mismo contrato que HoloTerminalHUDable.borrow_viewport: mientras el HUD es dueno del
	# Viewport, el mouse lo maneja el overlay con la posicion ABSOLUTA proyectada a la
	# superficie. Se fuerza el cursor relativo del Viewport (bloquea set_use_system_mouse(true))
	# y se apaga el input propio de la pantalla para que su camino no compita con el de la
	# superficie (cursor invertido/saltando).
	if _viewport.has_method("set_hud_relative_cursor"):
		_viewport.set_hud_relative_cursor(true)
	if has_method("set_process_input"):
		set_process_input(false)
	return _viewport

func enter_focus_mode() -> void:
	_ensure_viewport()
	_viewport.set_ui_mode(true)
	_viewport.set_use_system_mouse(false)
	_viewport.call_deferred("focus_command_input")

func exit_focus_mode() -> void:
	if is_instance_valid(_viewport):
		_viewport.set_ui_mode(false)

# surface_uv >= 0: el overlay resolvio donde cae el puntero real sobre la superficie de la
# pantalla (modo Pantalla del HUD). Sin uv se mantiene el camino relativo de siempre.
func forward_view_input(event: InputEvent, surface_uv: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if not is_instance_valid(_viewport):
		return
	if event is InputEventKey:
		_viewport.process_key_event(event)
		return
	_viewport.set_use_system_mouse(false)
	if surface_uv.x >= 0.0:
		if event is InputEventMouseMotion:
			_viewport.process_surface_motion(surface_uv)
			return
		if event is InputEventMouseButton:
			_viewport.process_surface_click(surface_uv, event.button_index, event.pressed, event.doubleclick)
			return
	if event is InputEventMouseMotion:
		_viewport.process_mouse_motion(event.relative)
	elif event is InputEventMouseButton:
		_viewport.process_mouse_click(event.button_index, event.pressed, event.doubleclick)

func set_view_cursor_visible(visible: bool) -> void:
	if is_instance_valid(_viewport) and _viewport.has_method("set_surface_hover"):
		_viewport.set_surface_hover(visible)

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
