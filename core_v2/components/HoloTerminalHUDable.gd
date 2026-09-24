extends HUDableComponent
class_name HoloTerminalHUDable

# HoloTerminalHUDable.gd - HoloTerminal bridge component for SuitOS / OdiseaOS (FD-296 F1.5)
# Exposes a HoloTerminalV2 instance as a HUDable screen source without modifying HoloTerminalV2.gd.

const DefaultWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")

export(NodePath) var terminal_path: NodePath = NodePath("")

# Telemetria de sala (temperatura/presion/toxicidad): Room3D emite por tick mientras se
# recupera de una excursion de frio, y cada notificacion se convierte en un reenvio de
# screen_list a todos los controles emparejados. El debounce junta la rafaga en 1
# mensaje cada 500 ms; los eventos discretos del circuito (valvula, parche, fuga) van
# directo, sin debounce.
const CRYO_TELEMETRY_DEBOUNCE_SEC := 0.5

var _last_active: bool = false
var _last_focused: bool = false
var _hidden_player_visual: Spatial = null
var _player_visual_was_visible: bool = true
var _shared_viewport: Viewport = null
var _shared_viewport_update_mode: int = Viewport.UPDATE_DISABLED
var _cryo_ui: Node = null
var _cryo_debounce_pending: bool = false

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	._ready()
	# Los paneles viven dentro del Viewport del terminal: en el mismo _ready pueden no
	# estar listos todavia. Diferido, igual que el resto de lo que depende de hijos.
	call_deferred("_connect_cryo_ui")

func _exit_tree() -> void:
	_disconnect_cryo_ui()

# La UI de diagnostico (si el terminal la trae) es la unica fuente de lectura del mundo:
# sus paneles ya se conectan a Room3D, valvulas y tanques con señales de cambio real.
# Aca solo se reenvian esos cambios al bus (notify_state_changed -> SuitOS -> red).
func _connect_cryo_ui() -> void:
	var terminal = _get_terminal()
	var viewport = terminal.get_node_or_null("Viewport") if is_instance_valid(terminal) else null
	if viewport == null:
		return
	for child in viewport.get_children():
		if child is Control and not child.is_queued_for_deletion() and child.has_method("collect_state"):
			_cryo_ui = child
			if child.has_signal("circuit_state_changed") \
					and not child.is_connected("circuit_state_changed", self, "notify_state_changed"):
				child.connect("circuit_state_changed", self, "notify_state_changed")
			# Telemetria de sala: puede llegar por tick; se agrupa con debounce.
			var dials = child.get_node_or_null("RoomDialsPanel")
			if dials != null and dials.has_signal("state_changed") \
					and not dials.is_connected("state_changed", self, "_on_cryo_telemetry_changed"):
				dials.connect("state_changed", self, "_on_cryo_telemetry_changed")
			return

func _disconnect_cryo_ui() -> void:
	if not is_instance_valid(_cryo_ui):
		return
	if _cryo_ui.has_signal("circuit_state_changed") \
			and _cryo_ui.is_connected("circuit_state_changed", self, "notify_state_changed"):
		_cryo_ui.disconnect("circuit_state_changed", self, "notify_state_changed")
	var dials = _cryo_ui.get_node_or_null("RoomDialsPanel")
	if dials != null and dials.has_signal("state_changed") \
			and dials.is_connected("state_changed", self, "_on_cryo_telemetry_changed"):
		dials.disconnect("state_changed", self, "_on_cryo_telemetry_changed")

func _on_cryo_telemetry_changed(_arg = null) -> void:
	if _cryo_debounce_pending:
		return
	_cryo_debounce_pending = true
	get_tree().create_timer(CRYO_TELEMETRY_DEBOUNCE_SEC).connect("timeout", self, "_flush_cryo_debounce")

func _flush_cryo_debounce() -> void:
	_cryo_debounce_pending = false
	notify_state_changed()

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

func default_screen_title() -> String:
	return tr("Terminal")

func widget_snapshot() -> Dictionary:
	var terminal = _get_terminal()
	var is_active_val: bool = false
	var is_focused_val: bool = false
	var can_focus_val: bool = false
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
		if terminal.has_method("can_focus"):
			can_focus_val = terminal.can_focus()

		if terminal is Spatial:
			var origin: Vector3 = (terminal as Spatial).global_transform.origin
			pos_array = [origin.x, origin.y, origin.z]

		if not is_active_val:
			status_text_val = "ESTADO: INACTIVO"
		elif is_focused_val:
			status_text_val = "MODO: FOCO ACTIVO"
		else:
			status_text_val = "DIAGNOSTICO: ONLINE"
	var snap := {
		"proto": 1,
		"id": screen_id(),
		"title": title_val,
		"active": is_active_val,
		"focused": is_focused_val,
		"can_focus": can_focus_val,
		"status_text": status_text_val,
		"position": pos_array,
		"source": "online"
	}
	# El estado del sistema que este terminal diagnostica (Criogenia: telemetria de sala,
	# valvulas, fugas, tanques) viaja como datos. El control remoto renderiza lo mismo con
	# las mismas escenas; nada de raster. Sin UI de diagnostico no hay clave: es un
	# HoloTerminal generico.
	if is_instance_valid(_cryo_ui) and _cryo_ui.has_method("collect_state"):
		var cryo: Dictionary = _cryo_ui.call("collect_state")
		if not cryo.empty():
			snap["cryo"] = cryo
	return snap

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

# El overlay tiene que tomar el input de la pantalla del terminal: el puntero real se proyecta a
# la superficie (surface_uv) y mueve el cursor del Viewport en ABSOLUTO. Sin esto el terminal
# manejaba el mouse por su cuenta con deltas relativos, que en la superficie se ve invertido.
func view_requires_input() -> bool:
	return is_instance_valid(_get_terminal())

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
		if viewport.has_method("set_hud_relative_cursor"):
			viewport.set_hud_relative_cursor(true)
		# Mientras el HUD es dueno del Viewport, el mouse lo maneja el overlay con la posicion
		# ABSOLUTA del puntero real proyectada a la superficie (process_surface_motion). Se apaga el
		# _input del terminal para que su camino relativo no compita (cursor invertido/saltando).
		if is_instance_valid(terminal):
			terminal.set_process_input(false)
	return _shared_viewport

func release_viewport() -> void:
	if is_instance_valid(_shared_viewport):
		_shared_viewport.render_target_update_mode = _shared_viewport_update_mode
		if _shared_viewport.has_method("set_hud_relative_cursor"):
			_shared_viewport.set_hud_relative_cursor(false)
	_shared_viewport = null
	var terminal = _get_terminal()
	if is_instance_valid(terminal) and terminal.has_method("_update_ui_mode"):
		terminal.call("_update_ui_mode")

# surface_uv >= 0 = el overlay ya resolvio DONDE cae el puntero real sobre la superficie
# de la pantalla. Ese camino no pasa por terminal._input(), que deduce el mapeo del modo
# del mouse y escala la ventana entera al Viewport (mal: la pantalla no ocupa la ventana).
func forward_view_input(event: InputEvent, surface_uv: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if not is_instance_valid(_shared_viewport):
		return
	if surface_uv.x >= 0.0:
		if event is InputEventMouseMotion and _shared_viewport.has_method("process_surface_motion"):
			# El cursor se dibuja DENTRO del Viewport: si el terminal quedo en static_content
			# (UPDATE_ONCE/DISABLED) el puntero se moveria a los saltos. Mientras el HUD lo
			# presta, se mantiene ALWAYS para que siga al mouse suave.
			if _shared_viewport.render_target_update_mode != Viewport.UPDATE_ALWAYS:
				_shared_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
			_shared_viewport.process_surface_motion(surface_uv)
			return
		if event is InputEventMouseButton and _shared_viewport.has_method("process_surface_click"):
			_shared_viewport.process_surface_click(surface_uv, event.button_index, event.pressed, event.doubleclick)
			return
	# Mouse del sistema NO: en el modo Pantalla del HUD lo que se ve no es el Viewport
	# ocupando la ventana entera, es el mesh del presentador pegado a la camara. El mapeo
	# absoluto (process_system_mouse_*) escala la posicion del puntero de la ventana
	# completa al Viewport, asi que el clic caia lejos del boton que se estaba apuntando.
	# Aca el cursor correcto es el del propio Viewport, movido por delta: para eso el
	# overlay esconde el cursor virtual y le pone relative_target_scale.
	#
	# La condicion vieja miraba el modo del mouse, pero el overlay SIEMPRE lo libera al
	# abrir la pantalla (_release_mouse_for_screen), asi que daba true siempre.
	if _shared_viewport.has_method("set_hud_relative_cursor"):
		_shared_viewport.set_hud_relative_cursor(true)
	var terminal = _get_terminal()
	if is_instance_valid(terminal) and terminal.has_method("_input"):
		terminal._input(event)

# FD-297: Devuelve la camara de foco del terminal si este permite modo foco y el rig existe.
# El puntero entro o salio de la superficie: adentro manda el cursor del Viewport, afuera
# el mouse virtual 2D del overlay.
func set_view_cursor_visible(visible: bool) -> void:
	if is_instance_valid(_shared_viewport) and _shared_viewport.has_method("set_surface_hover"):
		_shared_viewport.set_surface_hover(visible)

func view_transition_origin() -> Dictionary:
	var terminal = _get_terminal()
	if is_instance_valid(terminal):
		var allow_focus: bool = false
		if terminal.has_method("can_focus"):
			allow_focus = terminal.can_focus()
		elif "allow_focus_mode" in terminal:
			allow_focus = bool(terminal.get("allow_focus_mode"))

		if allow_focus:
			var focused_rig = terminal.call("_pick_focus_rig") if terminal.has_method("_pick_focus_rig") else null
			# El terminal puede no tener un rig elegido todavia (el nodo se armó despues del
			# _ready, o no hay jugador que decida adentro/afuera): se cae al rig de la escena.
			if not is_instance_valid(focused_rig):
				focused_rig = terminal.get_node_or_null("CinematicSetup/FocusedRig")
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

# La vista remota no entra al HUD local ni pausa el host. Esta accion queda reservada al
# ojito del control: usa exactamente el mismo foco que el radial local de la pantalla.
func allowed_actions() -> Array:
	var actions: Array = .allowed_actions()
	if not actions.has("toggle_focus"):
		actions.append("toggle_focus")
	return actions

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op != "toggle_focus":
		return .perform_action(op, args)
	var terminal = _get_terminal()
	if not is_instance_valid(terminal) or not terminal.has_method("can_focus") or not terminal.can_focus():
		return {"ok": false, "error": "Terminal sin modo foco"}
	if terminal.has_method("is_focused") and terminal.is_focused():
		exit_focus_mode()
	else:
		enter_focus_mode()
	notify_state_changed()
	return {"ok": true, "focused": terminal.is_focused() if terminal.has_method("is_focused") else false}

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
