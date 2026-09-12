extends CanvasLayer

const MobileUI = preload("res://core_v2/ui/MobileUI.tscn")

export(float) var touch_idle_timeout := 15.0
const TOUCH_POINTER_GRACE_MSEC := 250
# En desktop el jugador tiene el mouse a mano: el modo tactil se suelta enseguida. El timeout
# largo del export sigue siendo el del telefono, donde solo sirve para auto-ocultar la UI.
const DESKTOP_TOUCH_IDLE_TIMEOUT := 2.0
# El puntero fantasma del touch tambien manda motion; el mouse de verdad se mueve de a mas de
# un par de pixeles, el fantasma en modo capturado se movia de a uno.
const MOUSE_WAKE_PIXELS := 2.0

var _mobile_ui: CanvasLayer = null
var _touch_camera: TouchCameraControls = null
var _is_mobile := false
var _is_touch_active := false
var _touch_idle_timer := 0.0
var _touch_pointer_until := 0
var _touch_trackers := [] # controles tactiles que llevan su propio _touch_index
var _mouse_capture_suspended := false
var _is_cinematic_active := false
var _cinematic_manager: Node = null
var _is_zero_g := false
var _tracked_controller_manager: Node = null

func _ready() -> void:
	layer = 100
	
	# En desktop con pantalla tactil (ej. un notebook con touch), has_touchscreen_ui_hint()
	# ya da true al arrancar y la UI movil aparecia sin que el jugador tocara nada. Solo
	# Android/iOS arrancan mobile de una; el resto de plataformas tactiles se activan
	# recien con el primer touch real, via _input() mas abajo.
	_is_mobile = OS.get_name() == "Android" or OS.get_name() == "iOS"
	_is_touch_active = _is_mobile
	_touch_idle_timer = 0.0
	
	if _is_mobile:
		_spawn_mobile_ui()
	
	_connect_cinematic_manager()
	_refresh_mobile_ui_visibility()
	set_process(true)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_idle_timer = 0.0
		_touch_pointer_until = OS.get_ticks_msec() + TOUCH_POINTER_GRACE_MSEC
		if not _is_touch_active:
			# _is_mobile queda intacto: es "la plataforma es Android/iOS", no "hay touch
			# ahora". Un touch en desktop (notebook con pantalla tactil) solo prende
			# _is_touch_active, asi que decae solo con el idle-timeout en _process() sin
			# dejar al jugador pegado en modo movil el resto de la sesion.
			_is_touch_active = true
			if not is_instance_valid(_mobile_ui):
				_spawn_mobile_ui()
			_notify_input_provider_touch_active(true)
			_refresh_mobile_ui_visibility()
		_suspend_mouse_capture()
	elif event is InputEventMouseMotion and _is_touch_active and not _is_mobile:
		# Histeresis: el mouse de verdad recupera el mando en el acto, sin esperar el timeout.
		# El puntero fantasma del touch tambien manda motion, asi que se descarta con la ventana
		# del dedo (y con el umbral, por si llega un motion suelto justo despues).
		if not is_pointer_from_touch() and event.relative.length() > MOUSE_WAKE_PIXELS:
			_deactivate_touch()
			_restore_mouse_capture()

# Solo apaga el MODO tactil (UI y pistas). El grab NO se devuelve aca a proposito: si volviera
# con el timeout, la proxima pulsacion se perderia otra vez -es el bug que arregla
# _suspend_mouse_capture()- porque el grab se roba la secuencia antes de que nadie la vea. El
# puntero se recupera cuando se mueve el mouse de verdad, que es cuando hace falta.
func _deactivate_touch() -> void:
	_is_touch_active = false
	_reset_move_joystick()
	_notify_input_provider_touch_active(false)
	_refresh_mobile_ui_visibility()


# Capturar el mouse (MOUSE_MODE_CAPTURED) hace XGrabPointer, y con un grab de puntero activo X11
# le entrega la secuencia tactil al cliente que tiene el grab: al oyente de touch le llega un
# TouchEnd apenas el dedo se mueve, asi que el joystick se resetea solo -"se pierde el touch al
# arrastrar"- y el resto del gesto aparece como motion de mouse. En modo tactil no hace falta
# capturar: HIDDEN esconde el cursor SIN grab (solo CAPTURED y CONFINED* graban), asi el arrastre
# llega completo. SessionManager._wants_mouse_capture() deja de reafirmar mientras dure.
func _suspend_mouse_capture() -> void:
	if _is_mobile:
		return # Android/iOS nunca captura; ahi no hay grab que soltar
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		_mouse_capture_suspended = true


func is_mouse_capture_suspended() -> bool:
	return _mouse_capture_suspended


func _restore_mouse_capture() -> void:
	if not _mouse_capture_suspended:
		return
	_mouse_capture_suspended = false
	if Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _any_touch_control_held() -> bool:
	for ctrl in _touch_trackers:
		if is_instance_valid(ctrl) and ctrl._touch_index != -1:
			return true
	return false


func _collect_touch_trackers(node: Node) -> void:
	if "_touch_index" in node:
		_touch_trackers.append(node)
	for child in node.get_children():
		_collect_touch_trackers(child)


# El servidor X emula un puntero a partir del touch y NO lo suprime: XI2 solo lo hace si el
# cliente pide los eventos tactiles en el dispositivo master, y Godot los pide en XIAllDevices.
# Asi que cada toque en una pantalla tactil de escritorio llega ADEMAS como click y motion de
# mouse REAL (device 0: ni el device ni el evento lo delatan; el emulado propio de Godot, que si
# trae device -1, ni siquiera dispara acciones porque el InputMap filtra por device). Eso prendia
# tool_fire_primary -la unica accion en el boton izquierdo- con cada arrastre del joystick, y
# movia la camara doble, porque el arrastre ya entra por TouchCameraControls.
# Lo unico que delata al fantasma es que hay un dedo apoyado. Es una ventana de tiempo y no un
# contador de dedos a proposito: con el arbol pausado este _input no corre, y un contador se
# quedaria trabado en "hay un dedo" para siempre. La gracia cubre que el click del X server
# llega un toque despues del TouchEnd.
func is_pointer_from_touch() -> bool:
	return OS.get_ticks_msec() < _touch_pointer_until


func _notify_input_provider_touch_active(active: bool) -> void:
	var provider = _get_active_input_provider()
	if provider and provider.has_method("set_touch_ui_hint"):
		provider.set_touch_ui_hint(active)

func _spawn_mobile_ui() -> void:
	if _mobile_ui:
		return
	
	_mobile_ui = MobileUI.instance()
	add_child(_mobile_ui)
	_touch_trackers.clear()
	_collect_touch_trackers(_mobile_ui)
	
	_touch_camera = _get_touch_camera_control()
	if _touch_camera:
		_touch_camera.connect("camera_drag", self, "_on_camera_drag")
		_touch_camera.connect("camera_zoom", self, "_on_camera_zoom")
	
	_refresh_mobile_ui_visibility()

func _connect_cinematic_manager() -> void:
	_cinematic_manager = get_node_or_null("/root/CinematicManager")
	if not is_instance_valid(_cinematic_manager):
		_is_cinematic_active = false
		return
	if not _cinematic_manager.is_connected("cinematic_started", self, "_on_cinematic_started"):
		_cinematic_manager.connect("cinematic_started", self, "_on_cinematic_started")
	if not _cinematic_manager.is_connected("cinematic_stopped", self, "_on_cinematic_stopped"):
		_cinematic_manager.connect("cinematic_stopped", self, "_on_cinematic_stopped")
	_is_cinematic_active = _is_script_cinematic_active()

func _is_script_cinematic_active() -> bool:
	if not is_instance_valid(_cinematic_manager):
		return false
	var active_requests = _cinematic_manager.get("_active_requests")
	if typeof(active_requests) != TYPE_DICTIONARY:
		return false
	for request_id in active_requests.keys():
		var request = active_requests.get(request_id)
		if request and str(request.source) == "legacy_direct":
			return true
	return false

func _refresh_mobile_ui_visibility() -> void:
	# Also hide while paused: the touch controls (CanvasLayer 10/100) render above
	# the PauseMenu (CanvasLayer 50) and would otherwise intercept the touches meant
	# for the pause buttons, leaving the player unable to operate the menu on Android.
	_is_cinematic_active = _is_script_cinematic_active() or _is_script_input_block_active() or _is_replay_active()
	if not is_instance_valid(_mobile_ui):
		return
	var non_playable := _is_non_playable_scene()
	var paused := get_tree().paused
	var show_skip := _is_touch_active and _is_script_cinematic_active() and not non_playable and not paused
	# During a legacy cinematic (input blocked), show only the skip button so the
	# player can skip. Camera-zone-only cinematics keep the full UI (handled below).
	if show_skip:
		_mobile_ui.visible = true
		_mobile_ui.set_skip_visible(true)
		_mobile_ui.set_zero_g_mode(false)
		_set_gameplay_controls_visible(false)
		_reset_move_joystick()
		return
	var was_visible := _mobile_ui.visible
	_mobile_ui.visible = _is_touch_active and not _is_cinematic_active and not non_playable and not paused
	if _mobile_ui.visible:
		_mobile_ui.set_skip_visible(false)
		_mobile_ui.set_zero_g_mode(_is_zero_g)
		_set_gameplay_controls_visible(true)
	elif was_visible:
		# The tree can pause (or a cinematic can take over) mid-drag: the joystick's
		# _input freezes under PAUSE_MODE_STOP before it ever sees the touch-release,
		# leaving it visually stuck and its move_* actions held down. Reset it directly
		# here — direct calls still run on a paused node, only _input/_process don't.
		_reset_move_joystick()

func _reset_move_joystick() -> void:
	if not is_instance_valid(_mobile_ui):
		return
	var joystick = _mobile_ui.get_node_or_null("Container/MoveJoystick")
	if is_instance_valid(joystick):
		joystick.reset()

func _set_gameplay_controls_visible(enabled: bool) -> void:
	if not is_instance_valid(_mobile_ui):
		return
	var container = _mobile_ui.get_node_or_null("Container")
	if not container:
		return
	for child in container.get_children():
		if child.name != "ZeroGButtons" and child.name != "SkipButton":
			child.visible = enabled

func _is_replay_active() -> bool:
	var session = get_node_or_null("/root/SessionManager")
	return is_instance_valid(session) and bool(session.get("is_replaying"))

func _is_non_playable_scene() -> bool:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return false
	var filename: String = current_scene.filename
	return filename.find("Menu.tscn") != -1 or filename.find("Boot.tscn") != -1

# Force the touch UI hidden right now, independent of _process. The replay
# player pauses the SceneTree, which stops this autoload's _process, so the
# per-frame refresh can't be relied on to hide controls during replay; the
# player calls this directly when it takes over.
func set_replay_mode(active: bool) -> void:
	if active and is_instance_valid(_mobile_ui):
		_mobile_ui.visible = false
	else:
		_refresh_mobile_ui_visibility()

func _process(delta: float) -> void:
	# Los controles tactiles se COMEN el evento: set_input_as_handled() corta el grupo _input
	# (SceneTree::_call_input_pause sale del bucle) y este autoload es el PADRE de todos ellos,
	# o sea el ultimo en la fila. Arrastrando el joystick, _input() de aca no ve un solo touch:
	# ni se abria la ventana del puntero fantasma ni se reseteaba el idle-timeout (a los 15 s de
	# arrastre continuo la UI movil se apagaba sola). Se les pregunta a ellos, que llevan el dedo
	# apoyado en su propio _touch_index.
	if _any_touch_control_held():
		_touch_idle_timer = 0.0
		_touch_pointer_until = OS.get_ticks_msec() + TOUCH_POINTER_GRACE_MSEC
		_suspend_mouse_capture()
	if _is_touch_active:
		_touch_idle_timer += delta
		if _touch_idle_timer >= (touch_idle_timeout if _is_mobile else DESKTOP_TOUCH_IDLE_TIMEOUT):
			_deactivate_touch()

	if not is_instance_valid(_mobile_ui):
		return
	_track_player_controller_manager()
	_refresh_mobile_ui_visibility()

# Called by PauseManager on pause/resume. The autoload inherits PAUSE_MODE_STOP, so
# its _process is frozen while the tree is paused and can't refresh visibility on its
# own; the pause flow drives the hide explicitly here.
func refresh_for_pause() -> void:
	_refresh_mobile_ui_visibility()

func _is_script_input_block_active() -> bool:
	var input_provider = _get_active_input_provider()
	if input_provider == null:
		return false
	return not bool(input_provider.hardware_input_enabled)

func _on_cinematic_started(_rig_id: String = "") -> void:
	_refresh_mobile_ui_visibility()

func _on_cinematic_stopped() -> void:
	_refresh_mobile_ui_visibility()

func _get_touch_camera_control() -> TouchCameraControls:
	if not _mobile_ui:
		return null
	var container = _mobile_ui.get_node_or_null("Container")
	if not container:
		return null
	return container.get_node_or_null("TouchCameraArea")

func _on_camera_drag(delta: Vector2) -> void:
	var input_provider = _get_active_input_provider()
	if input_provider:
		input_provider.add_touch_camera_drag(delta)

func _on_camera_zoom(delta: float) -> void:
	var input_provider = _get_active_input_provider()
	if input_provider:
		input_provider.add_touch_camera_zoom(delta)

func _track_player_controller_manager() -> void:
	var session = get_node_or_null("/root/SessionManager")
	if not session or not session.player:
		return
	var player = session.player
	var cm = player.get_node_or_null("ControllerManager")
	if not is_instance_valid(cm) or cm == _tracked_controller_manager:
		return
	if is_instance_valid(_tracked_controller_manager):
		if _tracked_controller_manager.is_connected("controller_changed", self, "_on_controller_changed"):
			_tracked_controller_manager.disconnect("controller_changed", self, "_on_controller_changed")
	_tracked_controller_manager = cm
	_tracked_controller_manager.connect("controller_changed", self, "_on_controller_changed")
	var cur_mode = cm.get("current_mode")
	_is_zero_g = (cur_mode == 1)

func _on_controller_changed(mode: int) -> void:
	_is_zero_g = (mode == 1)
	_refresh_mobile_ui_visibility()

func _get_active_input_provider():
	var session = get_node_or_null("/root/SessionManager")
	if not session or not session.player:
		return null
	var player = session.player
	if not ("input_provider" in player):
		return null
	return player.input_provider

func is_mobile() -> bool:
	return _is_mobile

func is_touch_active() -> bool:
	return _is_touch_active

# El punto cae sobre un control virtual (joystick, botones de accion, de gravedad cero, saltar
# cinematica). TouchCameraArea no cuenta: cubre la pantalla entera y es el fondo que arrastra
# la camara, no un control. Lo usa quien quiere quedarse con un toque SIN apagar los controles
# (el dial del control remoto), mirando donde empieza.
func is_point_on_touch_controls(point: Vector2) -> bool:
	if not is_instance_valid(_mobile_ui) or not _mobile_ui.visible:
		return false
	var container = _mobile_ui.get_node_or_null("Container")
	if container == null:
		return false
	for ctrl in container.get_children():
		if not (ctrl is Control) or ctrl.name == "TouchCameraArea" or not ctrl.is_visible_in_tree():
			continue
		# Mismo calculo de rect que _expand_overlay_margins (la escala del nodo cuenta).
		var scale: Vector2 = ctrl.rect_scale
		var size := Vector2(ctrl.rect_size.x * abs(scale.x), ctrl.rect_size.y * abs(scale.y))
		if Rect2(ctrl.rect_global_position, size).has_point(point):
			return true
	return false

func get_reserved_overlay_margins(padding: float = 16.0) -> Dictionary:
	var margins = {
		"left": 0.0,
		"top": 0.0,
		"right": 0.0,
		"bottom": 0.0
	}
	if not is_instance_valid(_mobile_ui) or not _mobile_ui.visible:
		return margins

	var viewport_size = get_viewport().get_visible_rect().size
	margins = _expand_overlay_margins(margins, _mobile_ui.get_node_or_null("Container/MoveJoystick"), viewport_size, padding)
	margins = _expand_overlay_margins(margins, _mobile_ui.get_node_or_null("Container/ActionButtons"), viewport_size, padding)
	return margins

func _expand_overlay_margins(margins: Dictionary, ctrl: Control, viewport_size: Vector2, padding: float) -> Dictionary:
	if not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree():
		return margins

	var top_left = ctrl.rect_global_position
	var scale = ctrl.rect_scale
	var size = Vector2(ctrl.rect_size.x * abs(scale.x), ctrl.rect_size.y * abs(scale.y))
	var bottom_right = top_left + size

	margins["bottom"] = max(float(margins.get("bottom", 0.0)), max(0.0, viewport_size.y - top_left.y + padding))
	if bottom_right.x <= viewport_size.x * 0.5:
		margins["left"] = max(float(margins.get("left", 0.0)), bottom_right.x + padding)
	if top_left.x >= viewport_size.x * 0.5:
		margins["right"] = max(float(margins.get("right", 0.0)), viewport_size.x - top_left.x + padding)
	return margins
