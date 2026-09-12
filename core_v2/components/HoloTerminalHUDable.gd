extends HUDableComponent
class_name HoloTerminalHUDable

# HoloTerminalHUDable.gd - HoloTerminal bridge component for SuitOS / OdiseaOS (FD-296 F1.5)
# Exposes a HoloTerminalV2 instance as a HUDable screen source without modifying HoloTerminalV2.gd.

const DefaultWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")

export(NodePath) var terminal_path: NodePath = NodePath("")

var _last_active: bool = false
var _last_focused: bool = false
var _hidden_player_visual: Spatial = null
var _player_visual_was_visible: bool = true
var _shared_viewport: Viewport = null
var _shared_viewport_update_mode: int = Viewport.UPDATE_DISABLED

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	._ready()

func widget_scene() -> PackedScene:
	if hud_widget_scene != null:
		return hud_widget_scene
	return DefaultWidgetScene

func _physics_process(_delta: float) -> void:
	var terminal = _get_terminal()
	if is_instance_valid(terminal):
		var active_now: bool = terminal.get_is_open() if terminal.has_method("get_is_open") else bool(terminal.get("is_active"))
		var focused_now: bool = terminal.is_focused() if terminal.has_method("is_focused") else false
		if get_tree().paused and focused_now and terminal.has_method("_update_player_screen_occlusion"):
			terminal._update_player_screen_occlusion(_delta)
		if active_now != _last_active or focused_now != _last_focused:
			_last_active = active_now
			_last_focused = focused_now
			notify_state_changed()

func screen_id() -> String:
	if not hud_screen_id.empty():
		return hud_screen_id

	var target_node: Node = owner
	if target_node == null:
		target_node = get_parent()
	if target_node == null:
		target_node = self

	var path: String = ""
	if "scene_file_path" in target_node and not str(target_node.get("scene_file_path")).empty():
		path = str(target_node.get("scene_file_path"))
	elif target_node.filename != "":
		path = target_node.filename
	elif filename != "":
		path = filename

	if path.empty():
		path = String(target_node.get_path())

	return "holoterminal:" + path

func widget_snapshot() -> Dictionary:
	var terminal = _get_terminal()
	var is_active_val: bool = false
	var is_focused_val: bool = false
	var pos_array: Array = [0.0, 0.0, 0.0]
	var title_val: String = screen_title()
	var status_text_val: String = "ESTADO: OPERATIVO"

	if is_instance_valid(terminal):
		if terminal.has_method("get_is_open"):
			is_active_val = terminal.get_is_open()
		elif "is_active" in terminal:
			is_active_val = bool(terminal.get("is_active"))

		if terminal.has_method("is_focused"):
			is_focused_val = terminal.is_focused()
		elif "_is_focused" in terminal:
			is_focused_val = bool(terminal.get("_is_focused"))

		if terminal is Spatial:
			var origin: Vector3 = (terminal as Spatial).global_transform.origin
			pos_array = [origin.x, origin.y, origin.z]

		if not is_active_val:
			status_text_val = "ESTADO: INACTIVO"
		elif is_focused_val:
			status_text_val = "MODO: FOCO ACTIVO"
		else:
			status_text_val = "DIAGNOSTICO: ONLINE"

	return {
		"proto": 1,
		"id": screen_id(),
		"title": title_val,
		"active": is_active_val,
		"focused": is_focused_val,
		"status_text": status_text_val,
		"position": pos_array,
		"source": "online"
	}

# FD-296 F3: identifica la UI del Viewport para decidir si hay una vista completa. El HUD
# reutiliza el Viewport original mediante borrow_viewport(); no instancia una segunda UI.
func view_scene() -> PackedScene:
	if hud_view_scene != null:
		return hud_view_scene
	var terminal = _get_terminal()
	if not is_instance_valid(terminal) or not ("static_content" in terminal) or not terminal.static_content:
		return null
	var viewport = terminal.get_node_or_null("Viewport")
	if viewport == null:
		return null
	for child in viewport.get_children():
		if child is Control and not child.is_queued_for_deletion() and not child.filename.empty():
			return load(child.filename) as PackedScene
	return null

func view_is_source() -> bool:
	return view_scene() == null

# Resolucion de diseño de la vista: la del Viewport del terminal (1280x816 en el
# HangingDisplay). El overlay la instancia a ese tamaño y la escala entera; estirada al
# espacio de UI del juego (stretch viewport, ~1067x600) los diales se salen de sus paneles.
func view_size() -> Vector2:
	var terminal = _get_terminal()
	var viewport = terminal.get_node_or_null("Viewport") if is_instance_valid(terminal) else null
	return (viewport as Viewport).size if viewport is Viewport else Vector2.ZERO

func borrow_viewport() -> Viewport:
	if is_instance_valid(_shared_viewport):
		return _shared_viewport
	var terminal = _get_terminal()
	var viewport = terminal.get_node_or_null("Viewport") if is_instance_valid(terminal) else null
	if viewport is Viewport:
		_shared_viewport = viewport
		_shared_viewport_update_mode = viewport.render_target_update_mode
		viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	return _shared_viewport

func release_viewport() -> void:
	if is_instance_valid(_shared_viewport):
		_shared_viewport.render_target_update_mode = _shared_viewport_update_mode
	_shared_viewport = null

func forward_view_input(event: InputEvent) -> void:
	if not is_instance_valid(_shared_viewport):
		return
	if _shared_viewport.has_method("set_use_system_mouse"):
		_shared_viewport.set_use_system_mouse(Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED)
	var terminal = _get_terminal()
	if is_instance_valid(terminal) and terminal.has_method("_input"):
		terminal._input(event)

# FD-297: Devuelve la camara de foco del terminal si este permite modo foco y el rig existe.
func view_transition_origin() -> Dictionary:
	var terminal = _get_terminal()
	print("[DEBUG] view_transition_origin: terminal=", is_instance_valid(terminal),
		" can_focus=", terminal.can_focus() if is_instance_valid(terminal) else "N/A",
		" focused_rig=", is_instance_valid(terminal.get_node_or_null("CinematicSetup/FocusedRig")) if is_instance_valid(terminal) else "N/A")
	if is_instance_valid(terminal):
		var allow_focus: bool = false
		if terminal.has_method("can_focus"):
			allow_focus = terminal.can_focus()
		elif "allow_focus_mode" in terminal:
			allow_focus = bool(terminal.get("allow_focus_mode"))

		if allow_focus:
			var focused_rig = terminal.get_node_or_null("CinematicSetup/FocusedRig")
			if is_instance_valid(focused_rig) and focused_rig.is_inside_tree():
				return {
					"kind": "focus_rig",
					"path": focused_rig.get_path()
				}
	return {}

func enter_focus_mode() -> void:
	var terminal = _get_terminal()
	if is_instance_valid(terminal):
		if terminal.has_method("focus"):
			terminal.focus()
		elif terminal.has_method("_enter_focus_mode"):
			terminal._enter_focus_mode()

func exit_focus_mode() -> void:
	var terminal = _get_terminal()
	if is_instance_valid(terminal):
		if terminal.has_method("_exit_focus_mode"):
			terminal._exit_focus_mode()

func set_source_view_visible(visible: bool) -> void:
	var terminal = _get_terminal()
	if not is_instance_valid(terminal):
		return
	var mesh = terminal.get_node_or_null("ScreenContainer/ScreenMesh")
	if is_instance_valid(mesh):
		mesh.visible = visible
	var viewport = terminal.get_node_or_null("Viewport")
	if viewport is Viewport:
		if visible:
			viewport.render_target_update_mode = Viewport.UPDATE_ONCE
		elif viewport == _shared_viewport:
			viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
		else:
			viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	_set_player_visual_hidden(not visible, terminal)

func _set_player_visual_hidden(hidden: bool, terminal: Node) -> void:
	if not hidden:
		if is_instance_valid(_hidden_player_visual):
			_hidden_player_visual.visible = _player_visual_was_visible
		_hidden_player_visual = null
		return
	if is_instance_valid(_hidden_player_visual):
		return
	var player = terminal._find_player() if terminal.has_method("_find_player") else null
	var visual = player.get_node_or_null("Visual") as Spatial if is_instance_valid(player) else null
	if is_instance_valid(visual):
		_player_visual_was_visible = visual.visible
		visual.visible = false
		_hidden_player_visual = visual

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance

	var proximity_boost: float = 0.0
	if context.has("player_position") and typeof(context["player_position"]) == TYPE_ARRAY and context["player_position"].size() >= 3:
		var px: float = float(context["player_position"][0])
		var py: float = float(context["player_position"][1])
		var pz: float = float(context["player_position"][2])
		var player_pos: Vector3 = Vector3(px, py, pz)

		var term_pos: Vector3 = Vector3.ZERO
		var terminal = _get_terminal()
		if is_instance_valid(terminal) and terminal is Spatial:
			term_pos = (terminal as Spatial).global_transform.origin
		elif is_inside_tree() and get_parent() is Spatial:
			term_pos = (get_parent() as Spatial).global_transform.origin

		var dist: float = term_pos.distance_to(player_pos)
		proximity_boost = clamp(1.0 - (dist / 15.0), 0.0, 1.0) * 0.5

	var focus_boost: float = 0.0
	if context.has("focus_id") and String(context["focus_id"]) == screen_id():
		focus_boost = 0.4

	return clamp(rel + proximity_boost + focus_boost, 0.0, 1.0)

func _get_terminal() -> Node:
	if not String(terminal_path).empty():
		var node = get_node_or_null(terminal_path)
		if is_instance_valid(node):
			return node
	var parent = get_parent()
	if is_instance_valid(parent):
		return parent
	return null
