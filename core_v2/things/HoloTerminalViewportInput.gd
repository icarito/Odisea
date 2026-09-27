extends Viewport

export(float) var cursor_sensitivity := 1.0
export(Texture) var cursor_texture = preload("res://assets/cursor_none.svg")
export(Vector2) var cursor_hotspot := Vector2(7, 10)
# Paso 12: el contenido (CryoPodImGui, etc.) puede optar por un cursor dibujado en
# HoloScreen.shader (cursor_uv), a la tasa del juego, en vez del Sprite de aca adentro de
# la textura del Viewport (que con contenido a baja Hz salta). Con esto en true el Sprite
# de cursor de este Viewport no se dibuja nunca: HoloTerminalV2 lee _cursor_position con
# get_cursor_position() y la vuelca al shader.
var shader_cursor := false

var _ui_mode_active := false
var _cursor_position := Vector2.ZERO
var _cursor_layer: CanvasLayer = null
var _cursor_visual: Sprite = null
var _mouse_button_mask := 0
var _use_system_mouse := false
# El HUD presta este Viewport para dibujarlo en el mesh del presentador, que NO ocupa la
# ventana: ahi el mapeo absoluto del puntero del sistema (process_system_mouse_*) cae
# donde no es, y con el puntero quieto el cursor queda clavado donde lo dejaron. Mientras
# dure el prestamo el cursor es este, movido por delta.
var _hud_relative_cursor := false
# El puntero esta sobre la superficie de la pantalla. Fuera de ella el cursor de este
# Viewport no se dibuja: el que manda es el mouse virtual 2D del overlay. Nunca los dos.
var _surface_hover := true
# Ultimo evento de teclado inyectado, por id de instancia.
var _last_key_event_id := 0

# Paso 12: ImGuiCanvas no es un Control, asi que el pipeline normal de GUI de este
# Viewport (input()) no lo alcanza — la demo de gdtk lo resuelve reenviando el MISMO
# InputEvent directo con `_input()`. CryoPodImGui.gd (u otro contenido ImGui) se registra
# aca en su _ready(); sin registro nada cambia (el reenvio es opcional).
var _imgui_forward_target: Node = null

func set_imgui_forward_target(node: Node) -> void:
	_imgui_forward_target = node

func _forward_to_imgui(evt: InputEvent) -> void:
	if _imgui_forward_target != null and is_instance_valid(_imgui_forward_target):
		_imgui_forward_target.call("_input", evt)

func _ready() -> void:
	_cursor_position = get_visible_rect().size * 0.5
	_ensure_cursor_visual()
	_update_cursor_visual()

func set_ui_mode(active: bool) -> void:
	_ui_mode_active = active
	if active:
		call_deferred("focus_command_input")
	_ensure_cursor_visual()
	if _cursor_visual:
		_cursor_visual.visible = active and not _use_system_mouse
	_update_cursor_visual()

func set_hud_relative_cursor(enabled: bool) -> void:
	_hud_relative_cursor = enabled
	if enabled:
		_use_system_mouse = false
	_ensure_cursor_visual()
	if _cursor_visual:
		_cursor_visual.visible = _ui_mode_active and not _use_system_mouse
	_update_cursor_visual()

func set_surface_hover(enabled: bool) -> void:
	_surface_hover = enabled
	_ensure_cursor_visual()
	_update_cursor_visual()

# Punto absoluto sobre la superficie, en uv [0,1]. Es el camino del modo Pantalla del HUD:
# el overlay proyecta el mesh del presentador y traduce la posicion REAL del mouse (o la
# del cursor del joypad) a esta uv, asi que no hay deriva ni mapeo de ventana completa.
func process_surface_motion(uv: Vector2) -> void:
	if not _ui_mode_active:
		return
	_ensure_cursor_visual()
	var size = get_visible_rect().size
	_cursor_position = Vector2(clamp(uv.x, 0.0, 1.0) * size.x, clamp(uv.y, 0.0, 1.0) * size.y)
	var evt = InputEventMouseMotion.new()
	evt.position = _cursor_position
	evt.global_position = _cursor_position
	evt.button_mask = _mouse_button_mask
	input(evt)
	_forward_to_imgui(evt)
	_update_cursor_visual()

func process_surface_click(uv: Vector2, button_index: int, pressed: bool, is_doubleclick: bool) -> void:
	if not _ui_mode_active:
		return
	process_surface_motion(uv)
	var evt = InputEventMouseButton.new()
	evt.button_index = button_index
	evt.pressed = pressed
	evt.doubleclick = is_doubleclick and pressed
	evt.position = _cursor_position
	evt.global_position = _cursor_position
	var bit = int(1 << (button_index - 1))
	if pressed:
		_mouse_button_mask |= bit
	else:
		_mouse_button_mask &= ~bit
	evt.button_mask = _mouse_button_mask
	input(evt)
	_forward_to_imgui(evt)
	_update_cursor_visual()

func forces_relative_cursor() -> bool:
	return _hud_relative_cursor

func uses_shader_cursor() -> bool:
	return shader_cursor

func set_uses_shader_cursor(enabled: bool) -> void:
	shader_cursor = enabled
	_update_cursor_visual()

# Posicion actual del cursor en pixeles de este Viewport (mismo espacio que
# get_visible_rect().size), para que HoloTerminalV2 la convierta a UV del shader.
func get_cursor_position() -> Vector2:
	return _cursor_position

func has_surface_hover() -> bool:
	return _surface_hover

func set_use_system_mouse(enabled: bool) -> void:
	if _hud_relative_cursor:
		enabled = false
	_use_system_mouse = enabled
	_ensure_cursor_visual()
	if _cursor_visual:
		_cursor_visual.visible = _ui_mode_active and not _use_system_mouse
	_update_cursor_visual()

func process_mouse_motion(relative: Vector2) -> void:
	if not _ui_mode_active:
		return
	if _use_system_mouse:
		return
	_ensure_cursor_visual()
	_cursor_position += relative * cursor_sensitivity
	var size = get_visible_rect().size
	_cursor_position.x = clamp(_cursor_position.x, 0.0, size.x)
	_cursor_position.y = clamp(_cursor_position.y, 0.0, size.y)

	var evt = InputEventMouseMotion.new()
	evt.position = _cursor_position
	evt.global_position = _cursor_position
	evt.relative = relative * cursor_sensitivity
	evt.button_mask = _mouse_button_mask
	input(evt)
	_forward_to_imgui(evt)
	_update_cursor_visual()

func process_mouse_click(button_index: int = BUTTON_LEFT, pressed: bool = true, is_doubleclick: bool = false) -> void:
	if not _ui_mode_active:
		return
	if _use_system_mouse:
		return
	_ensure_cursor_visual()
	var evt = InputEventMouseButton.new()
	evt.button_index = button_index
	evt.pressed = pressed
	evt.doubleclick = is_doubleclick and pressed
	evt.position = _cursor_position
	evt.global_position = _cursor_position
	var bit = int(1 << (button_index - 1))
	if pressed:
		_mouse_button_mask |= bit
	else:
		_mouse_button_mask &= ~bit
	evt.button_mask = _mouse_button_mask
	input(evt)
	_forward_to_imgui(evt)
	_update_cursor_visual()

func process_system_mouse_motion(position: Vector2, global_position: Vector2, relative: Vector2, root_size: Vector2) -> void:
	if not _ui_mode_active:
		return
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return
	var viewport_pos = _map_root_to_viewport(position, root_size)
	var viewport_global = _map_root_to_viewport(global_position, root_size)
	_cursor_position = viewport_pos
	var evt = InputEventMouseMotion.new()
	evt.position = viewport_pos
	evt.global_position = viewport_global
	evt.relative = relative
	evt.button_mask = _mouse_button_mask
	input(evt)
	_forward_to_imgui(evt)
	_update_cursor_visual()

func process_system_mouse_button(button_index: int, pressed: bool, is_doubleclick: bool, position: Vector2, global_position: Vector2, root_size: Vector2) -> void:
	if not _ui_mode_active:
		return
	if root_size.x <= 0.0 or root_size.y <= 0.0:
		return
	var viewport_pos = _map_root_to_viewport(position, root_size)
	var viewport_global = _map_root_to_viewport(global_position, root_size)
	_cursor_position = viewport_pos
	var evt = InputEventMouseButton.new()
	evt.button_index = button_index
	evt.pressed = pressed
	evt.doubleclick = is_doubleclick and pressed
	evt.position = viewport_pos
	evt.global_position = viewport_global
	var bit = int(1 << (button_index - 1))
	if pressed:
		_mouse_button_mask |= bit
	else:
		_mouse_button_mask &= ~bit
	evt.button_mask = _mouse_button_mask
	input(evt)
	_forward_to_imgui(evt)
	_update_cursor_visual()

func process_key_event(event: InputEventKey) -> void:
	if not _ui_mode_active:
		return
	if not event.pressed:
		return
	# Un HUD que se reparenta al rig de camara activo termina recibiendo _input DOS veces
	# por evento —queda registrado para recibir input en dos viewports—, asi que cada tecla
	# llegaba aca duplicada y el LineEdit escribia dos caracteres. Medido: una sola
	# pulsacion sintetica producia dos process_key_event desde el MISMO nodo, con un unico
	# sitio de llamada en HoloTerminalV2._input.
	#
	# Se descarta la segunda entrega del MISMO evento. La comparacion es por INSTANCIA, no
	# por contenido: una tecla repetida de verdad (autorepeat, o pulsarla dos veces rapido)
	# es otro objeto y sigue pasando.
	var event_id: int = event.get_instance_id()
	if event_id == _last_key_event_id:
		return
	_last_key_event_id = event_id
	focus_command_input()
	if event.scancode == KEY_BACKSPACE:
		if _apply_backspace_to_line_edit():
			return
	input(event)

func focus_command_input() -> void:
	var shell = find_node("OYSShell", true, false)
	if shell and shell.has_method("focus_command_input"):
		shell.call("focus_command_input")
		return
	var line = find_node("CommandInput", true, false)
	if line and line is LineEdit:
		(line as LineEdit).grab_focus()

func _apply_backspace_to_line_edit() -> bool:
	var line = _find_focused_line_edit(self)
	if line == null:
		var fallback = find_node("CommandInput", true, false)
		if fallback and fallback is LineEdit:
			line = fallback as LineEdit
	if line == null:
		return false

	var text = String(line.text)
	var caret = int(line.caret_position)
	if caret <= 0 or text.length() <= 0:
		return true

	var left = text.substr(0, caret - 1)
	var right = text.substr(caret, text.length() - caret)
	line.text = left + right
	line.caret_position = caret - 1
	return true

func _find_focused_line_edit(node: Node) -> LineEdit:
	for child in node.get_children():
		if child is LineEdit and (child as LineEdit).has_focus():
			return child as LineEdit
		var found = _find_focused_line_edit(child)
		if found:
			return found
	return null

func _ensure_cursor_visual() -> void:
	if _cursor_visual and is_instance_valid(_cursor_visual):
		return
	if not _cursor_layer or not is_instance_valid(_cursor_layer):
		_cursor_layer = CanvasLayer.new()
		_cursor_layer.name = "VirtualCursorLayer"
		_cursor_layer.layer = 4096
		_cursor_layer.set_meta("persistent_viewport_cursor", true)
		add_child(_cursor_layer)
	_cursor_visual = Sprite.new()
	_cursor_visual.name = "VirtualCursor"
	_cursor_visual.texture = cursor_texture if cursor_texture else preload("res://assets/cursor_none.svg")
	_cursor_visual.centered = false
	_cursor_visual.offset = -cursor_hotspot
	_cursor_visual.z_index = 100
	_cursor_visual.set_meta("persistent_viewport_cursor", true)
	_cursor_visual.visible = _ui_mode_active
	_cursor_layer.add_child(_cursor_visual)

func _update_cursor_visual() -> void:
	if not _cursor_visual or not is_instance_valid(_cursor_visual):
		return
	# Con cursor por shader el cursor viejo (Sprite dentro de la textura) no se dibuja en el
	# mundo: lo pinta HoloScreen.shader desde cursor_uv, a la tasa del juego. Pero en modo
	# Pantalla del HUD (cursor relativo) la textura se muestra en 2D sin ese shader y
	# HoloTerminalV2 apaga cursor_uv: ahi el cursor tiene que ser este Sprite.
	_cursor_visual.visible = _ui_mode_active and not _use_system_mouse and _surface_hover \
			and (not shader_cursor or _hud_relative_cursor)
	_cursor_visual.position = _cursor_position

func _map_root_to_viewport(pos: Vector2, root_size: Vector2) -> Vector2:
	var size = get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	var x = (pos.x / root_size.x) * size.x
	var y = (pos.y / root_size.y) * size.y
	return Vector2(clamp(x, 0.0, size.x), clamp(y, 0.0, size.y))
