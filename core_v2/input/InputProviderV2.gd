extends Reference
class_name InputProviderV2

enum Mode {
	LIVE,
	REPLAY
}

var mode = Mode.LIVE
var playback_buffer := []
var playback_index := 0
var mouse_delta_accum := Vector2()
var zoom_delta_accum := 0.0
# Latch del auto-sprint analogico (histeresis 0.85/0.7): evita el flicker de sprint
# cuando la deflexion del stick virtual ronda el umbral.
var _auto_sprint_engaged := false
var move_response_curve: Curve
var camera_response_curve: Curve
var hardware_input_enabled := true
# D-pad como camara (camera_left/right/up/down). El modo HUD lo apaga en su propio proveedor.
var digital_camera_enabled := true

var joy_look_sensitivity := 15.0
var joy_move_sensitivity := 1.0
var hardware_look_sensitivity := 1.0
var touch_camera_sensitivity := 0.003
const JOY_DEADZONE := 0.2
const DIGITAL_ZOOM_SENSITIVITY := 0.1

var _touch_camera_drag := Vector2.ZERO
var _touch_camera_zoom := 0.0
var _axis_profile_resolved := false
var _touch_ui_hint_resolved := false
var _touch_ui_hint := false
# Espejo de la preferencia del jugador (Opciones -> Invertir X / Invertir Y), solo
# para diagnostico remoto. La correccion real la aplica axis_inversion().
var _invert_joy_move_x := false
var _invert_joy_move_y := false
var _invert_joy_look_x := false
var _invert_joy_look_y := false
var handheld_axis_correction_enabled := false
var handheld_axis_profile := "none"

# El engine numera los pads en el orden en que los descubre y ese orden cambia
# entre plataformas: en FRT/SDL un pad virtual (p. ej. el que crea un remapper de
# usuarios) puede quedar despues del dispositivo crudo, y en X11 al reves. En vez
# de hardcodear el device 0, agarramos el primer pad conectado; si no hay ninguno
# devolvemos -1 y los ejes leen 0.
var _primary_joypad := -1

func _primary_joy() -> int:
	var pads := Input.get_connected_joypads()
	if pads.empty():
		_primary_joypad = -1
	elif not pads.has(_primary_joypad):
		_primary_joypad = pads[0]
	return _primary_joypad

func _joy_axis(axis: int) -> float:
	var d := _primary_joy()
	return Input.get_joy_axis(d, axis) if d >= 0 else 0.0

func _init() -> void:
	pass


# En una pantalla tactil de escritorio cada toque llega TAMBIEN como mouse real (ver
# MobileUIManager.is_pointer_from_touch): el click fantasma prendia tool_fire_primary con cada
# arrastre del joystick y el motion movia la camara doble, porque el arrastre ya entra por
# add_touch_camera_drag(). Nada en el evento lo delata; lo unico que lo delata es que hay un dedo
# apoyado, y eso lo sabe MobileUIManager. Aca vive el acceso porque es el unico punto por donde
# el gameplay lee el mouse (polling de acciones y mouse_delta_accum).
static func pointer_is_from_touch() -> bool:
	var loop = Engine.get_main_loop()
	if loop == null or loop.root == null:
		return false
	var mgr = loop.root.get_node_or_null("MobileUIManager")
	return is_instance_valid(mgr) and mgr.has_method("is_pointer_from_touch") \
		and mgr.is_pointer_from_touch()


# Universal input getter
# Ultimo input entregado por get_input() en este frame. Existe para que otros sistemas
# (consolas, menus de prop) puedan LEER el input del frame sin consumirlo: get_input()
# avanza playback_index, asi que llamarlo desde fuera del bucle del jugador se comia
# entradas del buffer y desincronizaba la reproduccion entera.
var last_input: InputDataV2 = null


func peek_input() -> InputDataV2:
	return last_input


func get_input() -> InputDataV2:
	if mode == Mode.REPLAY:
		if playback_index < playback_buffer.size():
			var entry = playback_buffer[playback_index]
			var d = InputDataV2.new()
			if typeof(entry) == TYPE_DICTIONARY and entry.has("input"):
				d.from_dict(entry["input"])
			else:
				d.from_dict(entry)
			playback_index += 1
			last_input = d
			return d
		else:
			# Buffer ended, return null to signal end of replay
			return null
	else:
		last_input = _read_live_input()
		return last_input


func _q(v):
	return round(v * 1000.0) / 1000.0

func _apply_curve(v: Vector2, curve: Curve) -> Vector2:
	if not curve:
		return v
	
	var length = v.length()
	if length < 0.001:
		return Vector2.ZERO
		
	# Normalize input length 0-1 for curve lookup
	# Assuming joystick input is roughly 0-1.
	length = clamp(length, 0.0, 1.0)
	var curved_length = curve.interpolate(length)
	
	return v.normalized() * curved_length


func set_touch_ui_hint(active: bool) -> void:
	_touch_ui_hint_resolved = true
	_touch_ui_hint = active

func invalidate_touch_ui_hint() -> void:
	_touch_ui_hint_resolved = false

func _has_touch_ui() -> bool:
	if not _touch_ui_hint_resolved:
		_touch_ui_hint_resolved = true
		_touch_ui_hint = OS.has_touchscreen_ui_hint() or OS.get_name() == "Android" or OS.get_name() == "iOS"
		if not _touch_ui_hint and Engine.get_main_loop() and Engine.get_main_loop().root:
			var mobile_mgr = Engine.get_main_loop().root.get_node_or_null("MobileUIManager")
			if is_instance_valid(mobile_mgr) and mobile_mgr.has_method("is_touch_active"):
				_touch_ui_hint = mobile_mgr.is_touch_active()
	return _touch_ui_hint


func _is_digital_move_vector(v: Vector2) -> bool:
	# Keyboard-style movement yields exact 0/1 action strengths.
	# We use this to avoid forcing sprint on desktop keyboard movement.
	var x = abs(v.x)
	var y = abs(v.y)
	var x_is_digital = is_equal_approx(x, 0.0) or is_equal_approx(x, 1.0)
	var y_is_digital = is_equal_approx(y, 0.0) or is_equal_approx(y, 1.0)
	return x_is_digital and y_is_digital



# Inversion manual de los ejes analogos (Opciones -> Invertir X / Invertir Y).
# Un firmware que reporta los ejes al reves lo hace en los dos sticks a la vez, asi
# que la MISMA preferencia corrige movimiento y camara. No se detecta por dispositivo:
# la huella no es fiable y el paquete tiene que ser universal. Default: sin invertir.
# Se resuelve sin instancia porque VirtualMouse/RemoteControlHome leen las acciones
# cursor_* del InputMap directo (no pasan por step()) y necesitan el mismo signo.
static func axis_inversion() -> Vector2:
	var sm = _settings_manager()
	var ix := false
	var iy := false
	if sm != null:
		if "invert_x" in sm:
			ix = bool(sm.invert_x)
		if "invert_y" in sm:
			iy = bool(sm.invert_y)
	return Vector2(-1.0 if ix else 1.0, -1.0 if iy else 1.0)

static func wants_axis_inversion() -> bool:
	var inv := axis_inversion()
	return inv.x < 0.0 or inv.y < 0.0

static func _settings_manager():
	var loop = Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root = (loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("SettingsManager")

func _ensure_axis_profile_resolved() -> void:
	var inv := axis_inversion()
	var has_x := inv.x < 0.0
	var has_y := inv.y < 0.0
	_axis_profile_resolved = true
	handheld_axis_correction_enabled = has_x or has_y
	handheld_axis_profile = "manual_invert_xy" if (has_x and has_y) else ("manual_invert_x" if has_x else ("manual_invert_y" if has_y else "none"))
	_invert_joy_move_x = has_x
	_invert_joy_move_y = has_y
	_invert_joy_look_x = has_x
	_invert_joy_look_y = has_y


func _action_strength(action_name: String) -> float:
	if not InputMap.has_action(action_name):
		return 0.0
	return Input.get_action_strength(action_name)


func _action_pressed(action_name: String) -> bool:
	if not InputMap.has_action(action_name):
		return false
	return Input.is_action_pressed(action_name)


func _action_just_pressed(action_name: String) -> bool:
	if not InputMap.has_action(action_name):
		return false
	return Input.is_action_just_pressed(action_name)


func _read_live_input() -> InputDataV2:
	var d = InputDataV2.new()

	if hardware_input_enabled:
		_ensure_axis_profile_resolved()
		var axis_inv := axis_inversion()

		var raw_move_vec = Vector2(
			_action_strength("move_right") - _action_strength("move_left"),
			_action_strength("move_backward") - _action_strength("move_forward")
		)
		# Las acciones move_* tambien leen el stick, y pueden ser el unico camino si el
		# runtime no expone get_joy_axis. Se invierten igual, salvo el vector digital de
		# teclado (0/1 exactos), para que la correccion cubra las dos fuentes.
		if not _is_digital_move_vector(raw_move_vec):
			raw_move_vec = Vector2(raw_move_vec.x * axis_inv.x, raw_move_vec.y * axis_inv.y)

		d.jump = _action_pressed("jump")
		d.sprint = _action_pressed("run")
		d.crouch = _action_pressed("crouch")
		d.interact = _action_just_pressed("interact")
		d.interact_held = _action_pressed("interact")
		d.focus = _action_just_pressed("focus")
		d.rotate_left = _action_pressed("rotate_left")
		d.rotate_right = _action_pressed("rotate_right")
		d.roll_left = _action_pressed("zero_g_roll_left")
		d.roll_right = _action_pressed("zero_g_roll_right")
		# tool_fire_primary es la unica accion en el boton izquierdo, que es el que aprieta el
		# puntero fantasma del touch en cada toque.
		d.tool_fire_primary = _action_pressed("tool_fire_primary") and not pointer_is_from_touch()
		d.tool_fire_secondary = _action_pressed("tool_fire_secondary")
		d.tool_next_mode = _action_just_pressed("tool_next_mode")
		d.tool_prev_mode = _action_just_pressed("tool_prev_mode")
		d.cargol_ability = _action_pressed("cargol_ability")
		d.hud_mode = _action_pressed("hud_mode")
		d.hud_slot = 0
		for n in range(1, 5): # HudSlots.COUNT; la primera sostenida gana
			if _action_pressed("slot_%d" % n):
				d.hud_slot = n
				break
		# La cruceta, que en modo HUD no es camara: pasos por la lista del dial y del drawer.
		# Las flechas (ui_up/ui_down, built-in) son el equivalente de teclado de la cruceta:
		# ya viven en el InputMap y ningun otro sistema de gameplay las lee.
		d.hud_nav = 0
		if _action_pressed("camera_up") or _action_pressed("ui_up"):
			d.hud_nav = -1
		elif _action_pressed("camera_down") or _action_pressed("ui_down"):
			d.hud_nav = 1

		# --- JOYSTICK SPRINT (Physical) ---
		var joy_move_x = _joy_axis(JOY_AXIS_0) * axis_inv.x
		var joy_move_y = _joy_axis(JOY_AXIS_1) * axis_inv.y
		var joy_move = Vector2(
			joy_move_x,
			joy_move_y
		)
		var move_source_vec = raw_move_vec
		if joy_move.length() > JOY_DEADZONE:
			move_source_vec = joy_move
			d.analog_move_active = true
		elif raw_move_vec.length() > 0.001:
			# El joystick virtual empuja las MISMAS acciones que el teclado, solo que con
			# fuerza analogica, asi que un vector no digital delata al stick. A deflexion
			# maxima entrega 1.0 exacto y pasaria por teclado: en un dispositivo tactil no
			# hay teclado con el que confundirlo, todo movimiento es del stick de pantalla.
			d.analog_move_active = _has_touch_ui() or not _is_digital_move_vector(raw_move_vec)
		d.move_vec = _apply_curve(move_source_vec, move_response_curve)
		d.move_vec *= joy_move_sensitivity
		d.move_vec.x = _q(d.move_vec.x)
		d.move_vec.y = _q(d.move_vec.y)
		if joy_move.length() > 0.8:
			d.sprint = true
		
		# --- VIRTUAL/ANALOG AUTO SPRINT ---
		# Keep auto sprint for analog-like input, but do not force sprint for digital keyboard vectors.
		# Con histeresis: en el borde (~0.85) la deflexion del stick oscila y hace titilar
		# sprint frame a frame; el flicker alternaba return_to_neutral del head-look del
		# animador y se veia como wobble de la cabeza en fps bajos.
		if not _is_digital_move_vector(move_source_vec):
			var move_speed: float = d.move_vec.length()
			if move_speed > 0.85:
				_auto_sprint_engaged = true
			elif move_speed < 0.7:
				_auto_sprint_engaged = false
			if _auto_sprint_engaged:
				d.sprint = true

		# Acumula y consume mouse_delta localmente
		var mouse_d = Vector2(_q(mouse_delta_accum.x), _q(-mouse_delta_accum.y))
		mouse_d *= hardware_look_sensitivity
		d.hardware_mouse_active = mouse_d.length() > 0.1

		# --- JOYSTICK CAMERA (Right Stick) ---
		var joy_look_x = _joy_axis(JOY_AXIS_2)
		var joy_look_y = _joy_axis(JOY_AXIS_3)
		var joy_look = Vector2(
			joy_look_x,
			- joy_look_y
		)
		if joy_look.length() > JOY_DEADZONE:
			joy_look = _apply_curve(joy_look, camera_response_curve)
			mouse_d += joy_look * joy_look_sensitivity

		# --- D-PAD CAMERA (Digital) ---
		# En juego el D-pad es camara (izq/der gira, arriba/abajo inclina; +Y es arriba, como el
		# stick). En el modo HUD el overlay la apaga: ahi el D-pad navega la UI (ui_*).
		if digital_camera_enabled:
			var digital_look := Vector2(
				_action_strength("camera_right") - _action_strength("camera_left"),
				_action_strength("camera_up") - _action_strength("camera_down")
			)
			# Mismo resguardo que el zoom digital: hay handhelds que comparten indices entre el
			# click del stick y el D-pad, asi que con el stick de movimiento activo no inclina.
			if joy_move.length() > 0.4:
				digital_look.y = 0.0
			mouse_d += digital_look * joy_look_sensitivity

		# --- TOUCH CAMERA (from TouchCameraControls) ---
		if _touch_camera_drag.length_squared() > 0.001:
			mouse_d += _touch_camera_drag
			_touch_camera_drag = Vector2.ZERO

		# La inversion manual abarca el control completo (mouse, stick, D-pad y arrastre
		# tactil): si el firmware da vuelta un stick, tambien da vuelta la camara.
		d.mouse_delta = Vector2(mouse_d.x * axis_inv.x, mouse_d.y * axis_inv.y)

		# --- ZOOM ---
		var digital_zoom = (_action_strength("zoom_out") - _action_strength("zoom_in")) * DIGITAL_ZOOM_SENSITIVITY
		
		# Robustness: Many handhelds/controllers overlap Stick Click with D-pad indices.
		# If the movement stick is active, we ignore digital (button-based) zoom to avoid accidents.
		if joy_move.length() > 0.4:
			digital_zoom = 0.0
			
		d.zoom_delta = zoom_delta_accum + digital_zoom + _touch_camera_zoom
		_touch_camera_zoom = 0.0

	# Limpiamos los acumuladores real aquí SIEMPRE para evitar fugas si se re-activa
	mouse_delta_accum = Vector2()
	zoom_delta_accum = 0.0

	return d


func set_replay_data(data: Array):
	playback_buffer = data
	playback_index = 0
	mode = Mode.REPLAY

func set_live_mode():
	playback_buffer.clear()
	playback_index = 0
	mode = Mode.LIVE

func add_touch_camera_drag(delta: Vector2) -> void:
	_touch_camera_drag += delta

func add_touch_camera_zoom(delta: float) -> void:
	_touch_camera_zoom += delta
