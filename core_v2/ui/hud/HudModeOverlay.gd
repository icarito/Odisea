extends Control

# HudModeOverlay.gd - Modo HUD local de OdiseaOS (FD-296 F3, spec 4).
# Lo monta SuitOS.open_hud_mode() en OverlayUIManager (SLOT_MODAL) con el mundo pausado por
# PauseManager.pause_hud_mode(), asi que corre en PAUSE_MODE_PROCESS.
#
# TAB (o el boton tactil del HUD): desde el juego, tap abre el radial; con una pantalla abierta, tap
# vuelve al jugador; con el radial ya abierto, un tap confirma lo marcado o lo cierra si no hay nada.
# Hold abre el radial tambien sobre una pantalla (para cambiarla), como cuasimodo: soltar elige lo
# marcado. Elegir abre la pantalla sin fijarla: nada se autoasigna a un slot.
# Teclas 1-4 / slot_1..4: tap abre la pantalla de ese slot (o la cierra si ya es la activa) y hold
# abre el radial que fija lo elegido EN ese slot. Con una sola pantalla no hay radial.
# El radial se apunta con un vector acumulado con zona muerta: soltar en el centro no elige nada. Tap/hold, gesto y click salen de InputDataV2
# (patron ElevatorFloorSelector): con el mundo pausado el proveedor del jugador no avanza, asi
# que el overlay avanza uno propio, una muestra por tick y con la normalizacion del replay.

const Gesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const ViewMount = preload("res://core_v2/ui/hud/HudViewMount.gd")
const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
const HudSlots = preload("res://core_v2/ui/hud/HudSlots.gd")
const UIScaleCompensator = preload("res://core_v2/ui/UIScaleCompensator.gd")
const Haptics = preload("res://core_v2/ui/Haptics.gd")
const EyeOpen = preload("res://core_v2/ui/remote_control/eye_open.svg")
const EyeClosed = preload("res://core_v2/ui/remote_control/eye_closed.svg")
# Mismos umbrales que ElevatorFloorSelector: se filtra ruido de angulo, no movimiento.
const MOVE_GESTURE_DEADZONE_SQ := 0.02
const MOUSE_GESTURE_DEADZONE := 3.0
const TOUCH_MIN_DRAG := 12.0
# Punteria del dial, en pixeles del dial: el mouse suma hasta este radio, el stick lo recorre en
# vivo y el dedo lo arrastra. Dentro de AIM_DEAD_ZONE no se marca nada.
const AIM_RADIUS := 120.0
const AIM_DEAD_ZONE := 40.0
# Mantener un item del radial y mover el dedo lo levanta para soltarlo sobre un slot (lo fija ahi).
# Mismo umbral que el hold de TAB y del widget.
const DRAG_HOLD_MSEC := 400
# Godot marca asi el mouse que emula a partir del touch (InputEvent.DEVICE_ID_TOUCH_MOUSE).
const TOUCH_MOUSE_DEVICE := -1
# Asa de la pantalla abierta: arrastrarla hasta un slot la ancla ahi. Pixeles nominales.
const HANDLE_SIZE := Vector2(64, 22)
const HANDLE_GAP := 8.0
const CAMERA_FOCUS_SIZE := Vector2(56, 38)
const DrawerScript = preload("res://core_v2/ui/hud/SuitOSDrawer.gd")
# Botones de cara, tal como ya viajan en el stream (FD-304 §4): A = crouch, B = jump, X = interact,
# Y = hud_mode. No se agrega ninguna accion nueva al mapa de entrada: la pantalla declara sus
# operaciones con hud_gamepad_actions() y el overlay las despacha por HudWidgetAction.
const FACE_FIELDS := {"a": "crouch", "b": "jump", "x": "interact"}
# Paso de la cruceta por el arco: mismo umbral que el hold, para no inventar un tercer tempo.
const NAV_REPEAT_MSEC := 400
const NAV_RATE_MSEC := 110
# Cuanto recorre el cursor del arrastre por tick con el stick a fondo, en pixeles del viewport.
const STICK_DRAG_SPEED := 14.0
# Cuanto aporta el stick por tick al arrastre del widget del interactuable (acorde de Interactuar).
const CONTEXT_GRAB_SPEED := 10.0

var input_provider = null # InputProviderV2; LIVE salvo que un test inyecte uno en REPLAY
# De donde salen las pantallas y los slots: SuitOS en el juego; RemoteHudBackend en el control
# remoto, que lo monta sin pausa (el mundo sigue en el host). Se asigna antes de add_child.
var backend: Node = null
# En el juego el mouse virtual usa la pantalla abierta. En el control remoto no: en un handheld se
# activaba con el stick y convertia A/B en clics locales que nunca llegaban al host.
var use_virtual_mouse: bool = true
# Con el mundo pausado el stick, el mouse y el gatillo quedan libres para el dial y el widget
# ampliado. En un telefono no: el joystick y los botones virtuales siguen manejando al host.
var drives_dial_with_gameplay_input: bool = true

var _selector: Control = null
var _view_host: Control = null
var _placeholder: Label = null
var _virtual_mouse: Control = null
var _screen_ids: Array = []
var _gesture = Gesture.new()
var _mount = ViewMount.new()
# Ya se decidio la pulsacion que abrio el modo HUD: desde ahi, un tap cierra.
var _opened: bool = false
var _mouse_aim_active: bool = false
var _confirm_was_down: bool = true # sostenido al abrir: ese boton no confirma
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO
var _touch_press_msec: int = 0
var _drag_option: int = -1 # el item del radial bajo el dedo al apoyarlo
var _drag_ghost: Label = null # el item levantado, siguiendo al dedo
var _mouse_drag_pending: bool = false
var _mouse_drag_position: Vector2 = Vector2.ZERO
var _mouse_drag_moved: bool = false
var _restore_mouse_capture_after_drag: bool = false
# Arrastre del widget ampliado (pantalla que es solo widget) hasta un slot.
var _view_drag_candidate: bool = false
var _view_handle: Control = null
var _camera_focus_button: Button = null
var _drag_from_handle: bool = false
# El toque cayo sobre un widget de slot con el dial a la vista: es del widget (tocarlo o arrastrarlo,
# SuitOSWidgetHost), no del dial.
var _touch_on_widget: bool = false
var _dragging_view: bool = false
# Pantalla con vista propia (presentador 3D): para que el asa "arrastre" hay que seguir el mesh del
# presentador con el cursor. Se guarda su pose original para restaurarla al soltar.
var _drag_mesh: Node = null
# Widget fantasma que se arrastra (en vez de mover la ventana 3D) al llevar una Pantalla a un slot.
var _drag_widget: Control = null
var _drag_mesh_xf: Transform = Transform()
var _drag_mesh_scale: Vector3 = Vector3.ONE
# El arrastre de la vista abierta que empezo con hombro+stick (gamepad), para saber cuando soltar.
var _view_drag_from_gamepad: bool = false
var _active_focused_screen: Object = null
# El dial abierto por mantener TAB: mientras siga apretado es un cuasimodo (ver _release_tab_hold).
var _tab_hold_active: bool = false
# Clic del widget en modo pantalla: ya estaba apretado al mostrarse (el confirm del dial o el
# tap que lo abrio no lo oprime).
var _widget_click_was_down: bool = true
var _picked_during_hold: bool = false
var _pending_focus_screen: Object = null
var _pending_focus_camera: Camera = null
var _pending_swap_screen: Object = null
# Slot que abrio el radial (tecla o widget): lo elegido se fija ahi. -1 = lo abrio TAB.
var _target_slot: int = -1
var _aim: Vector2 = Vector2.ZERO
var _stick_aiming: bool = false
# Tap/hold de las teclas de slot, del stream igual que TAB. Una sola pulsacion a la vez.
var _slot_gesture = Gesture.new()
var _key_slot: int = -1
var _key_slot_down: bool = false
# La pulsacion de tecla en curso ya abrio su pantalla al oprimir (solo widget, sin vista diegetica):
# su tap no la cierra, y un hold soltado sin elegir sale en vez de volver a ella.
var _opened_on_press: bool = false
# Lo que muestra el arco: los favoritos ordenados por relevancia (FD-305 §2, FD-306 §2). El
# registry completo (_screen_ids) es lo que muestra el drawer.
var _dial_ids: Array = []
# Lo que se esta arrastrando, por id y no por indice: el asa de una pantalla abierta puede
# arrastrar algo que no esta en el arco.
var _drag_id: String = ""
var _drawer: Control = null
# Flancos de los botones de cara. Arrancan en true: el boton que abrio el modo HUD no acciona.
var _face_was_down := {"a": true, "b": true, "x": true}
var _nav_dir: int = 0
var _nav_msec: int = 0
# Relleno del marco del slot mientras se mantiene su hombro (FD-304 §3.1): el hold no puede ser
# invisible. Es solo dibujo, no lee input, y por eso no entra al replay.
var _hold_gauge: Control = null
var _hold_slot: int = -1
var _hold_progress: float = 0.0
# Cursor unico del modo HUD: un solo estado relativo, en pixeles de SU espacio activo. Radial,
# drawer y arrastres lo miden en el viewport del overlay; la pantalla enfocada, en pixeles de su
# propio Viewport. Lo mueven por delta el stick, el dedo y el mouse capturado; el mouse absoluto lo
# fija proyectando. Un unico tope por contexto, siempre por _move_cursor().
var _cursor: Vector2 = Vector2.ZERO
var _cursor_moved: bool = false
# Acorde de Interactuar sobre el widget del interactuable activo. Sale del stream (interact_held +
# mouse_delta/move_vec), asi que el replay lo reproduce igual.
var _context_grabbing: bool = false
# Clic/arrastre del dial con CROUCH (revision 2026-09-19): sostenido levanta el item marcado y el
# stick lo lleva a un slot; un tap corto confirma.
var _crouch_drag_active: bool = false
var _crouch_drag_moved: bool = false
# Arrastre de una fila del drawer hacia un slot (FD-305 §3.5). Con mouse/dedo la fila se levanta
# al superar el umbral; con un hombro sostenido se levanta la fila enfocada y la lleva el stick.
# El cajon se abrio directo (sostener el boton del HUD), sin pasar por el dial. Decide a
# donde vuelve el retroceso: al juego, no a un dial que el jugador nunca abrio.
var _drawer_entered_direct: bool = false
var _drawer_press_row: int = -1
# El drawer usa el mouse CAPTURADO: su puntero es el mismo cursor unico, movido por deltas.
var _drawer_press_star: bool = false
var _drawer_drag_row: int = -1
var _drawer_drag_active: bool = false

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	if use_virtual_mouse:
		# El overlay se crea en runtime (OverlayUIManager): si el cursor se pide en _ready, el
		# padre todavia esta armando hijos ("Parent node is busy setting up children"). Diferido,
		# entra en el mismo frame y evita el add_child denegado.
		call_deferred("_attach_virtual_mouse")
	_selector = get_node("RadialSelector")
	# FD-306 §1: el centro ya no es un agujero sino el hub ("..." -> el drawer), con su propio radio.
	# Por eso no se le pone dead_zone: apuntar al medio marca el hub, y SOLTAR ahi cierra sin elegir,
	# que es la misma red de seguridad que daba la zona muerta.
	_selector.hub_enabled = true
	_selector.animate_transitions = true
	# Sin su sector del anillo el texto de cada opcion flota sobre la escena y no se lee como opcion.
	_selector.draw_option_slices = true
	_view_host = get_node("ViewHost")
	_placeholder = get_node("Placeholder")
	_view_handle = Control.new()
	_view_handle.name = "ViewHandle"
	_view_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE # el toque se resuelve en _input
	_view_handle.visible = false
	add_child(_view_handle)
	_view_handle.connect("draw", self, "_draw_view_handle")
	_camera_focus_button = Button.new()
	_camera_focus_button.name = "CameraFocus"
	_camera_focus_button.hint_tooltip = "Enfocar cámara del piloto"
	_camera_focus_button.toggle_mode = true
	_camera_focus_button.expand_icon = true
	_camera_focus_button.icon = EyeOpen
	_camera_focus_button.rect_min_size = CAMERA_FOCUS_SIZE
	_camera_focus_button.visible = false
	_camera_focus_button.connect("pressed", self, "_on_camera_focus_pressed")
	add_child(_camera_focus_button)
	add_to_group("touch_camera_blocker")
	if input_provider == null:
		input_provider = InputProviderV2.new()
	# En el modo HUD el D-pad es de la UI (ui_*): que no apunte el dial como si fuera la camara.
	input_provider.digital_camera_enabled = false
	_selector.connect("option_selected", self, "_select")
	_selector.connect("cancelled", self, "_exit")
	_hold_gauge = Control.new()
	_hold_gauge.name = "HoldGauge"
	_hold_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_gauge.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(_hold_gauge)
	_hold_gauge.connect("draw", self, "_draw_hold_gauge")
	var suit_os: Node = _suit_os()
	_mount.view_2d = suit_os.get("presents_views_in_2d") == true
	# FD-306 §5: el overlay leia el registry una sola vez. Con el drawer eso pasa a ser un bug real,
	# asi que se escucha el alta y la baja de pantallas y la lista se rehace conservando el foco.
	for sig in ["screen_registered", "screen_unregistered"]:
		if suit_os.has_signal(sig) and not suit_os.is_connected(sig, self, "_refresh_screens"):
			suit_os.connect(sig, self, "_refresh_screens")
	_refresh_screens()
	# El TAB que abrio el modo HUD sigue apretado: tap o hold se decide con las muestras.
	_gesture.begin_held()
	# Con el mundo pausado detras, el widget en modo pantalla se dibuja a resolucion completa
	# (a render_scale < 1 su texto salia pixelado). Ver SettingsManager.hold_full_resolution_ui.
	var settings = get_node_or_null("/root/SettingsManager")
	if settings and settings.has_method("hold_full_resolution_ui"):
		settings.hold_full_resolution_ui(self, true)

func _attach_virtual_mouse() -> void:
	if not use_virtual_mouse or is_instance_valid(_virtual_mouse) or is_queued_for_deletion() \
			or not is_inside_tree():
		return
	_virtual_mouse = VirtualMouse.attach_to(self)
	# Si en el mismo frame ya se abrio una pantalla, el estado quedo pendiente (no habia cursor):
	# se aplica ahora para que el puntero quede liberado y clickeable.
	if is_instance_valid(_active_focused_screen) or _mount.is_showing():
		_set_virtual_mouse_enabled(true)
		_release_mouse_for_screen()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_focus()

func _exit_tree() -> void:
	_end_option_drag()
	_cleanup_focus()
	_mount.close()
	# Salir del modo HUD apaga el cursor virtual aunque el overlay se libere sin pasar por _exit()
	# (cambio de escena, pausa). Si otra UI tambien lo pedia, sigue vivo por ese otro requester.
	if is_instance_valid(_virtual_mouse):
		_set_virtual_mouse_enabled(false)
		if _virtual_mouse.has_method("remove_requester"):
			_virtual_mouse.remove_requester(self)
	var suit_os: Node = _suit_os()
	if is_instance_valid(suit_os):
		for sig in ["screen_registered", "screen_unregistered"]:
			if suit_os.has_signal(sig) and suit_os.is_connected(sig, self, "_refresh_screens"):
				suit_os.disconnect(sig, self, "_refresh_screens")
	var settings = get_node_or_null("/root/SettingsManager")
	if settings and settings.has_method("hold_full_resolution_ui"):
		settings.hold_full_resolution_ui(self, false)

# Entrada directa al radial (hold sobre el widget del slot, que no pasa por el stream).
func show_radial(slot: int = -1) -> void:
	_gesture.consume()
	_opened = true
	_open_radial(slot)

# Lo abrio la tecla de un slot: esa tecla sigue apretada y tap/hold se decide con sus muestras.
func show_for_slot(slot: int) -> void:
	_gesture.consume()
	_key_slot = slot
	_key_slot_down = true
	_slot_gesture.begin_held()
	_open_on_press(slot)

# Entrada directa a una pantalla (tap sobre el widget de su slot).
func show_screen_id(id: String) -> void:
	_gesture.consume()
	_opened = true
	_show_screen(id)

func _physics_process(_delta: float) -> void:
	_mount_focused_screen_if_ready()
	_update_view_handle()
	_update_camera_focus_button()
	var input = _frame_input()
	if input == null:
		return
	if not _selector.is_open() and not _drawer_open():
		_drive_context_grab(input)
	_ensure_widget_host_signals()
	if int(input.hud_widget_activate_slot) >= 0:
		_activate_pinned_interactable(int(input.hud_widget_activate_slot))
	var gesture: int = _gesture.feed(bool(input.hud_mode))
	if _drawer_open():
		# El drawer es una vista: Y sale del modo HUD (no vuelve al dial), como dice FD-305 §3.5.
		if gesture == Gesture.TAP:
			_exit()
			return
		_drive_drawer(input, _delta)
		_update_hold_feedback()
		return
	if gesture == Gesture.TAP:
		if _screen_ids.empty():
			# Sin pantallas no hay dial: el tap que abrio muestra "SIN PANTALLAS", el siguiente sale.
			if _opened:
				_exit()
				return
			_opened = true
		elif _selector.is_open():
			_opened = true
			_dismiss_radial()
			if not is_inside_tree() or is_queued_for_deletion():
				return
		elif _mount.is_showing() or is_instance_valid(_active_focused_screen):
			# Desde una pantalla, el boton del HUD vuelve al jugador. Para cambiar de pantalla, hold.
			_exit()
			return
		else:
			_opened = true
			_open_radial()
	elif gesture == Gesture.HOLD and not _selector.is_open():
		# Decision de Sebastian, 2026-09-20 (Manual, Apendice A punto 1): sostener abre el
		# CAJON. Antes tap y hold abrian los dos el dial: el hold no tenia significado
		# propio, y el "hint de descubrimiento" que pide FD-296:89-92 habria ensenado una
		# diferencia que no existia. Ahora hay dos verbos distintos y enseniables:
		# tap = tus favoritos (el dial), hold = todo (el cajon).
		_opened = true
		_target_slot = -1
		_open_drawer_direct()
	var slot_gesture: int = _feed_slot_gesture(int(input.hud_slot) - 1)
	# FD-304 §6: con una pantalla abierta, el hombro + stick arrastra esa pantalla a otro slot en
	# vez de abrir el radial de ese hombro. Mientras dura el arrastre, el resto del modo HUD no
	# corre: A/X/B no son de la pantalla y el dial no se apunta.
	if drives_dial_with_gameplay_input and _drive_screen_view_drag(input, slot_gesture):
		if not is_inside_tree() or is_queued_for_deletion():
			return
		_update_hold_feedback()
		return
	# Revision 2026-09-19 (Sebastian): el TAP de un hombro ejecuta la accion por default de su
	# pantalla y solo el HOLD lleva a la pantalla (slot vacio: radial para asignarle una). La
	# pulsacion ya no abre nada al oprimir; `_open_on_press` queda solo para el atajo de teclado.
	if slot_gesture == Gesture.TAP:
		if _opened_on_press:
			_opened_on_press = false # el release de la pulsacion que la abrio
		elif _tap_slot(_key_slot):
			return
	elif slot_gesture == Gesture.HOLD and not _selector.is_open():
		_begin_hold_radial(_key_slot)
	_aim_with_hud_button(bool(input.hud_mode))
	# Apuntar antes de resolver el release: la ultima muestra con TAB suelto todavia cuenta.
	if drives_dial_with_gameplay_input:
		_drive_from_stream(input)
		_drive_nav(input)
	if (gesture == Gesture.HOLD_RELEASE or slot_gesture == Gesture.HOLD_RELEASE) and _tab_hold_active:
		_release_tab_hold()
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if drives_dial_with_gameplay_input:
		# Si la pantalla abierta declara sus botones de cara, son suyos: la navegacion por foco de
		# la GUI no puede oprimir el mismo boton otra vez en el mismo toque.
		if not _drive_hud_buttons(input):
			_drive_widget_screen(input)
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_update_hold_feedback()

# Una tecla de slot nueva toma el gesto solo si no hay otra sostenida.
func _feed_slot_gesture(pressed_slot: int) -> int:
	if pressed_slot >= 0 and not _key_slot_down:
		_key_slot = pressed_slot
	var down: bool = pressed_slot >= 0 and pressed_slot == _key_slot
	_key_slot_down = down
	return _slot_gesture.feed(down)

# Tap de la tecla/hombro de un slot, ya dentro del modo HUD. Devuelve true si consumio el
# frame (abrio, cerro o salio).
#
# Decision de Sebastian, 2026-09-20 (Manual, Apendice A punto 2): el boton de un slot
# ABRE la pantalla de ese slot, y si ya estamos en ella, la cierra. Un boton, un destino.
#
# Antes esta funcion descartaba su argumento y llamaba _exit() y nada mas: dentro del modo
# HUD, cualquier tecla de slot u hombro cerraba el HUD sin importar cual se hubiera
# apretado. Los cuatro botones hacian lo mismo, y no era lo que decia ningun documento.
func _tap_slot(slot: int) -> bool:
	if slot < 0:
		_exit()
		return true
	var suit_os: Node = _suit_os()
	var id: String = String(suit_os.slot_screen_id(slot))
	if id.empty() or not suit_os.has_screen(id):
		# Slot vacio: el dial fijado a ese slot, que es como se llena. Ofrecer el dial es mas
		# util que no hacer nada, y es lo mismo que ya hacia el hold.
		_open_radial(slot)
		_opened = true
		return true
	if id == String(suit_os.get_active_screen_id()):
		# Ya estamos en ella: el mismo boton la cierra (Manual §5, verbo 2).
		_exit()
		return true
	_opened = true
	_show_screen(id)
	return true


# Una pantalla que es solo widget se abre al oprimir la tecla, sin esperar a saber si es tap o
# hold: no hay transicion de camara que disimule esa espera. Solo el atajo de teclado 1-4 fuera del
# modo HUD; dentro del modo HUD el tap ejecuta la accion y es el hold el que abre el radial.
func _open_on_press(slot: int) -> void:
	var suit_os: Node = _suit_os()
	var id: String = suit_os.slot_screen_id(slot)
	var screen: Object = suit_os.get_screen(id)
	if screen == null or _selector.is_open() or id == suit_os.get_active_screen_id():
		return
	if screen.has_method("view_scene") and screen.view_scene() != null:
		return
	_opened = true
	_opened_on_press = true
	_show_screen(id)

# Hold de la tecla/hombro de un slot: abre el radial fijado a ese slot y, si el slot tiene pantalla,
# queda marcado su widget en el arco (revision 2026-09-19).
func _begin_hold_radial(slot: int) -> void:
	_opened = true
	if _opened_on_press:
		# La pulsacion ya habia abierto la pantalla del slot por adelantado (es widget puro y no
		# hay transicion de camara que disimule la espera). Que la pulsacion termine siendo un
		# hold dice que no era eso lo que se queria: se deshace antes de abrir el dial.
		_opened_on_press = false
		_cleanup_focus()
		_mount.close()
		_suit_os().close_screen()
	_tab_hold_active = true
	_picked_during_hold = false
	_open_radial(slot)

# La muestra del tick: get_input() una vez por tick (el proveedor del jugador esta pausado).
func _frame_input():
	return input_provider.get_input()

# El boton tactil del HUD es un joystick: arrastrar el dedo desde donde se apoyo apunta el dial,
# y soltarlo suelta TAB (elige lo marcado, _release_tab_hold). Si arrastra antes del umbral del
# hold el dial se abre ya: un arrastre nunca es un tap. Sin boton o sin dedo, drag es cero.
func _aim_with_hud_button(tab_down: bool) -> void:
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	var drag: Vector2 = mobile.hud_button_drag() if mobile != null and mobile.has_method("hud_button_drag") \
		else Vector2.ZERO
	if drag.length() < TOUCH_MIN_DRAG:
		return
	if tab_down and not _selector.is_open() and not _tab_hold_active:
		_gesture.promote_to_hold()
		_begin_hold_radial(-1)
	if _selector.is_open():
		_point_at(drag)

# Acorde de Interactuar (stream): sostener Interactuar agarra el widget del interactuable activo y
# el movimiento (mouse/stick) lo lleva a un slot; al soltar se fija. Todo sale de campos ya
# grabados (interact_held, mouse_delta, move_vec/analog), asi que el replay lo reproduce igual.
func _drive_context_grab(input) -> void:
	var host = _widget_host()
	if host == null or not host.has_method("context_widget_active"):
		return
	if bool(input.interact_held) and host.context_widget_active():
		if not _context_grabbing:
			_context_grabbing = true
			if not host.begin_context_grab():
				_context_grabbing = false
				return
		var delta := Vector2(input.mouse_delta.x, -input.mouse_delta.y)
		delta += Vector2(input.move_vec.x, input.move_vec.y) * CONTEXT_GRAB_SPEED
		host.drive_context_grab(delta)
	elif _context_grabbing:
		_context_grabbing = false
		host.end_context_grab()


# El host avisa que se toco un widget de interactuable fijado; se latea al stream para que la
# accion quede grabada y el replay la reproduzca.
func _ensure_widget_host_signals() -> void:
	var host = _widget_host()
	if host == null or not host.has_signal("interactable_activate_requested"):
		return
	if not host.is_connected("interactable_activate_requested", self, "_on_interactable_activate_requested"):
		host.connect("interactable_activate_requested", self, "_on_interactable_activate_requested")

func _on_interactable_activate_requested(slot_index: int) -> void:
	if input_provider != null and "hud_widget_activate_slot" in input_provider:
		input_provider.hud_widget_activate_slot = slot_index

func _activate_pinned_interactable(slot_index: int) -> void:
	var suit_os: Node = _suit_os()
	if suit_os == null:
		return
	var id: String = suit_os.slot_screen_id(slot_index)
	if id.begins_with("interactable:") and bool(suit_os.perform_action(id, "interact").get("ok", false)):
		Haptics.confirm()


func _drive_from_stream(input) -> void:
	if not _selector.is_open():
		return
	# mouse_delta viene con Y invertida (arriba es +Y); en pantalla arriba es -Y.
	var gesture: Vector2 = Vector2(input.mouse_delta.x, -input.mouse_delta.y)
	var move: Vector2 = Vector2(input.move_vec.x, input.move_vec.y)
	if _touch_index < 0 and gesture != Vector2.ZERO:
		# El mouse suma: volver hacia el centro es volver a la zona muerta.
		_point_at(_aim + gesture)
		if gesture.length() >= MOUSE_GESTURE_DEADZONE:
			_mouse_aim_active = true
	# CROUCH sostenido (clic del dial, revision 2026-09-19): el stick mueve el item levantado, no
	# apunta el arco. El release lo suelta o, si no se movio, confirma lo marcado.
	if _crouch_drag_active:
		_drive_crouch_drag(move, input)
		_confirm_was_down = bool(input.tool_fire_primary)
		return
	# Hold de un hombro sobre un slot QUE YA TIENE pantalla: el stick levanta su widget y lo
	# arrastra (FD-304 §6). Con la revision 2026-09-19 ese arrastre vive en la capa Pantalla
	# (_drive_screen_view_drag); dentro del radial solo queda para slots vacios.
	if _stick_drag_armed():
		_drive_stick_drag(move, input)
		_confirm_was_down = bool(input.tool_fire_primary)
		return
	if move.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
			and (input.analog_move_active or not _mouse_aim_active):
		# WASD solo mientras no se movio el mouse (ElevatorFloorSelector). El stick es en vivo.
		_stick_aiming = bool(input.analog_move_active)
		_point_at(move.limit_length(1.0) * AIM_RADIUS)
	elif _stick_aiming:
		_stick_aiming = false
		_point_at(Vector2.ZERO) # stick soltado: al centro, nada marcado
	var down: bool = bool(input.tool_fire_primary)
	# El clic del mouse tambien aparece en el stream como tool_fire_primary. Mientras su release
	# decide click corto o drag, no puede confirmar el dial por adelantado.
	if not _mouse_drag_pending and down and not _confirm_was_down:
		_confirm_or_dismiss()
	_confirm_was_down = down

func _input(event: InputEvent) -> void:
	if _drawer_open() and (event is InputEventMouseMotion or event is InputEventMouseButton \
			or event is InputEventScreenTouch or event is InputEventScreenDrag):
		# El drawer se usa con el dedo, el mouse y el mando. No marca el evento como atendido: el
		# cursor virtual compartido necesita ver el mismo mouse para seguir al puntero.
		_drawer_pointer_input(event)
		return
	if use_virtual_mouse and event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
		if event.pressed:
			# Liberar de verdad: set_pointer_released marca el estado global (no solo el cursor
			# local), asi al salir del HUD el mouse NO se vuelve a capturar.
			VirtualMouse.set_pointer_released(true)
			_set_virtual_mouse_enabled(true)
			_virtual_mouse.set_desktop_mouse_mode(true, event.position)
			_set_focus_cursor_over_surface(_screen_surface_uv(event.position).x >= 0.0)
		get_tree().set_input_as_handled()
		return
	# Revision 2026-09-19: el panel del widget ampliado se arrastra desde su cuerpo con el mouse
	# (o el dedo emulado), como los items del radial. Sin hold: el mouse levanta al instante. Un
	# clic sobre un boton del panel no arranca drag: va a la GUI.
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT \
			and not _selector.is_open() and not _drawer_open():
		if event.pressed:
			# Asa: arrastra la pantalla (tenga panel o no) hacia un slot. Un widget ampliado tambien
			# se arrastra desde su cuerpo.
			if _view_handle.visible and is_on_view_handle(event.position):
				_begin_mouse_view_drag(event.position)
				get_tree().set_input_as_handled()
				return
			if _showing_widget_only() and _on_view_body(event.position):
				_begin_mouse_view_drag(event.position)
				get_tree().set_input_as_handled()
				return
		elif _dragging_view:
			_drop_view(event.position)
			get_tree().set_input_as_handled()
			return
	if is_instance_valid(_active_focused_screen) and _active_focused_screen.has_method("forward_view_input"):
		if event is InputEventKey and not event.is_action_pressed("ui_cancel"):
			_active_focused_screen.forward_view_input(event)
			get_tree().set_input_as_handled()
			return
		if (event is InputEventMouseMotion or event is InputEventMouseButton) and not _dragging_view:
			# Un cursor a la vez: sobre la superficie dibuja el del Viewport, fuera el
			# mouse virtual 2D. Fuera NO se consume el evento, asi el mouse virtual sigue
			# su curso normal (antes se consumia siempre y quedaba clavado).
			# Con un arrastre de asa en curso el motion NO se manda a la pantalla: si no, el
			# panel levantado se queda clavado y la pantalla se mueve su cursor interno.
			var uv: Vector2
			var gamepad_cursor: bool = is_instance_valid(_virtual_mouse) \
				and _virtual_mouse.relative_target_scale != Vector2.ZERO
			var design: Vector2 = _surface_design_size()
			if event is InputEventMouseMotion and gamepad_cursor:
				# El cursor del stick llega como motion relativo ya escalado a pixeles de la
				# pantalla: mueve el MISMO cursor unico, con el signo del basis real del mesh
				# (misma autoridad que usa la proyeccion del mouse, _surface_u_flip).
				var step: Vector2 = Vector2(event.relative.x, event.relative.y)
				if _surface_u_flip():
					step.x = -step.x
				_move_cursor(step, design)
				uv = _surface_cursor_uv()
			else:
				uv = _screen_surface_uv(event.position)
				if uv.x >= 0.0:
					_set_surface_cursor_uv(uv)
			var over: bool = uv.x >= 0.0
			_set_focus_cursor_over_surface(over)
			if over:
				_active_focused_screen.forward_view_input(event, uv)
				get_tree().set_input_as_handled()
				return
	if event is InputEventMouseMotion:
		if _dragging_view:
			_drive_view_drag(event.position, true)
			get_tree().set_input_as_handled()
			return
		if _mouse_drag_pending and _drag_option >= 0:
			var drag_position: Vector2 = _update_mouse_drag_position(event)
			if _drive_option_drag(drag_position, false):
				_mouse_drag_moved = _mouse_drag_moved \
					or (drag_position - _touch_start).length() >= TOUCH_MIN_DRAG
			get_tree().set_input_as_handled()
			return
		# Lo que hace PlayerControllerV2._input, que ahora esta pausado.
		if _touch_index >= 0 or not drives_dial_with_gameplay_input:
			return # es un dedo: ya apunta el radial por InputEventScreenDrag, mas abajo
		if input_provider != null and "mouse_delta_accum" in input_provider:
			input_provider.mouse_delta_accum += event.relative
		return
	if event is InputEventScreenTouch:
		# Un dedo sobre el joystick o un boton virtual es de ellos: se sigue caminando con el dial
		# abierto (en el control remoto; en el juego estan ocultos o no sirven en pausa).
		if event.pressed and _touch_index < 0 and not _on_touch_controls(event.position):
			_touch_index = event.index
			_touch_start = event.position
			_touch_press_msec = OS.get_ticks_msec()
			var host = _widget_host()
			_touch_on_widget = _selector.is_open() and host != null and host.forward_touch(event)
			if _touch_on_widget:
				get_tree().set_input_as_handled()
				return
			_drag_option = _selector.slice_at(event.position)
			_drag_id = _dial_id_at(_drag_option)
			_drag_from_handle = is_on_view_handle(event.position)
			if _drag_from_handle:
				_drag_id = _suit_os().get_active_screen_id()
				_drag_option = _dial_ids.find(_drag_id)
			_view_drag_candidate = _widget_screen_showing() and not _drag_from_handle \
				and _view_screen_rect().has_point(event.position) \
				and not HudWidgetActionScript.pointer_on_button(_mount.get_widget(), event.position)
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			var tapped: bool = (event.position - _touch_start).length() < TOUCH_MIN_DRAG
			if _touch_on_widget:
				_touch_on_widget = false # lo resuelve el widget (su pantalla, su boton, o el arrastre)
				var host = _widget_host()
				if host != null:
					host.forward_touch(event)
				get_tree().set_input_as_handled()
			elif is_instance_valid(_drag_ghost):
				_drop_option(event.position)
				get_tree().set_input_as_handled()
			elif _dragging_view:
				_drop_view(event.position)
				get_tree().set_input_as_handled()
			elif _drag_from_handle:
				_drag_from_handle = false # un toque al asa sin arrastrar no hace nada (ni cierra)
				get_tree().set_input_as_handled()
			elif _selector.is_open() \
					and _selector.slice_at(_touch_start) == RadialSelectorV2.HUB_INDEX \
					and _selector.slice_at(event.position) == RadialSelectorV2.HUB_INDEX:
				# Dedo que empezo y solto en el "..." pero se corrio mas que el umbral del tap:
				# sigue siendo el hub, que no es una opcion. Sin esto el drift lo dejaba en nada.
				Haptics.confirm()
				_select(RadialSelectorV2.HUB_INDEX)
				get_tree().set_input_as_handled()
			elif tapped and _selector.is_open():
				# Como en el ascensor: tocar un sector elige ese sector; tocar en cualquier otro lado
				# con una opcion marcada (apuntada con el boton del HUD o arrastrando) la oprime, y
				# sin nada marcado cierra el dial.
				var picked: int = _selector.slice_at(event.position)
				if picked != RadialSelectorV2.NONE:
					Haptics.confirm() # el toque directo no pasa por confirm(), que es el que vibra
					_select(picked)
				elif _selector.has_selection():
					_selector.confirm()
				else:
					_dismiss_radial()
				get_tree().set_input_as_handled()
			elif tapped and _is_outside_view(event.position):
				_exit()
				get_tree().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		# Todo el arrastre, no el ultimo delta (criterio de ElevatorFloorSelector).
		if event.index == _touch_index:
			if _touch_on_widget or _drive_option_drag(event.position) or _drive_view_drag(event.position):
				return
			_point_at(event.position - _touch_start)
		return
	# TAB NO se lee aca: tap/hold sale del stream (_physics_process).
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and _selector.is_open():
		# El clic emulado de un toque no decide: el toque se resuelve al soltar (sector o fuera).
		# Por el device y no solo por InputProviderV2.pointer_is_from_touch(): con el arbol pausado
		# MobileUIManager no renueva esa ventana, y el clic del dedo cerraba el dial al apoyarlo.
		if event.device == TOUCH_MOUSE_DEVICE \
				or (Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and InputProviderV2.pointer_is_from_touch()):
			# Y sigue de largo a la GUI: si el dedo cayo sobre un widget de slot, ese clic es el
			# que lo oprime. Marcarlo como atendido dejaba al widget sin su toque.
			return
		if event.pressed:
			# Igual que touch: el click corto confirma; si se mueve antes de soltar, lleva el
			# item del dial hasta un slot.
			_mouse_drag_pending = true
			# Con el mouse capturado el click llega warpeado al centro (el hub) y el puntero miente:
			# manda el aim. Con el mouse liberado (HIDDEN, como en modo HUD) el puntero es real y
			# manda la posicion; el aim solo decide si el click cae fuera del anillo.
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				_drag_option = _selector.get_hovered_index()
				if _drag_option == RadialSelectorV2.NONE:
					_drag_option = _selector.slice_at(event.position)
			elif _mouse_aim_active or _target_slot < 0:
				# El mouse ya apunto (o el radial no vino de un slot): manda la posicion.
				_drag_option = _selector.slice_at(event.position)
				if _drag_option == RadialSelectorV2.NONE:
					_drag_option = _selector.get_hovered_index()
			else:
				# Radial abierto por el hold de un slot y sin movimiento del mouse: vale lo marcado
				# (el widget de ese slot), no la posicion del puntero.
				_drag_option = _selector.get_hovered_index()
				if _drag_option == RadialSelectorV2.NONE:
					_drag_option = _selector.slice_at(event.position)
			_drag_id = _dial_id_at(_drag_option)
			_mouse_drag_moved = false
			_mouse_drag_position = _selector.option_center(_drag_option)
			_touch_start = _mouse_drag_position
			_touch_press_msec = OS.get_ticks_msec()
			if _drag_option != RadialSelectorV2.NONE:
				_selector.point_at(_mouse_drag_position)
				_start_mouse_option_drag(_mouse_drag_position)
		elif is_instance_valid(_drag_ghost):
			var dragged: bool = _mouse_drag_moved
			_drop_option(event.position)
			if not dragged:
				_confirm_or_dismiss()
		elif _mouse_drag_pending:
			_mouse_drag_pending = false
			# El hub se confirma con un click explicito (FD-306 §1.1): _confirm_or_dismiss lo
			# descartaria, porque soltar con el centro marcado no elige. Solo si el click cayo
			# sobre el hub; un click en cualquier otro lado conserva la ruta de siempre.
			var pressed_hub: bool = _drag_option == RadialSelectorV2.HUB_INDEX
			_drag_option = -1
			if pressed_hub:
				_selector.confirm()
			else:
				_confirm_or_dismiss()
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed \
			and _is_outside_view(event.position):
		_exit()
	elif event.is_action_pressed("ui_cancel"):
		_exit()
	elif event.is_action_pressed("ui_accept") and _selector.is_open() \
			and not event is InputEventJoypadButton:
		# Solo teclado/accion: el mando (A = joy0 = crouch y ui_accept a la vez) lo resuelve el
		# stream en _physics_process. Sin este filtro A confirmaba por evento Y arrancaba el
		# click/arrastre, y podia abrir un item que no era el apuntado (p. ej. la Consola).
		_selector.confirm()
	elif event.is_action("ui_accept") and _widget_screen_showing():
		pass # el boton lo oprime _drive_widget_screen: la GUI lo oprimiria otra vez
	else:
		return
	get_tree().set_input_as_handled()

# Levanta el item apretado cuando, pasado el hold, el dedo se mueve; desde ahi lo sigue y resalta el
# slot de abajo. El mouse lo levanta al oprimir para que se lea como un drag desde su propia opcion.
func _drive_option_drag(position: Vector2, require_hold: bool = true, allow_stationary: bool = false) -> bool:
	if not is_instance_valid(_drag_ghost):
		if _drag_id.empty() \
				or (not allow_stationary and (position - _touch_start).length() < TOUCH_MIN_DRAG):
			return false
		# Del dial hace falta el hold; el asa ya es para arrastrar; el drawer levanta la fila con
		# el gesto que ya paso su propio umbral (mouse/dedo) o con el hombro sostenido (stick).
		if not _drag_from_handle and not _drawer_open() and (not _selector.is_open() \
				or (require_hold and OS.get_ticks_msec() - _touch_press_msec < DRAG_HOLD_MSEC)):
			return false
		Haptics.pulse(Haptics.LIFT_MSEC)
		_drag_ghost = Label.new()
		_drag_ghost.name = "DragGhost"
		_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_ghost.text = _screen_title(_drag_id)
		if _selector.option_font is Font:
			_drag_ghost.add_font_override("font", _selector.option_font)
		_drag_ghost.add_color_override("font_color", _selector.color_fg)
		add_child(_drag_ghost)
	_drag_ghost.rect_position = position - _drag_ghost.get_combined_minimum_size() * 0.5
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(true, host.slot_at(position))
	return true

func _start_mouse_option_drag(position: Vector2) -> void:
	if not _drive_option_drag(position, false, true):
		return
	VirtualMouse.set_dragging(true)
	_restore_mouse_capture_after_drag = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _restore_mouse_capture_after_drag:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		get_viewport().warp_mouse(position)

func _update_mouse_drag_position(event: InputEventMouseMotion) -> Vector2:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		_mouse_drag_position = event.position
		return _mouse_drag_position
	_mouse_drag_position += event.relative
	var size: Vector2 = get_viewport_rect().size
	_mouse_drag_position.x = clamp(_mouse_drag_position.x, 0.0, size.x)
	_mouse_drag_position.y = clamp(_mouse_drag_position.y, 0.0, size.y)
	return _mouse_drag_position

# Soltar el item levantado: sobre un slot lo fija ahi; en cualquier otro lado no pasa nada. Desde el
# dial, el dial queda abierto para seguir asignando; desde el asa de una pantalla, anclarla cierra
# el modo HUD para que se vea el widget en su slot.
func _drop_option(position: Vector2) -> void:
	var host = _widget_host()
	var slot: int = host.slot_at(position) if host != null else -1
	var from_handle: bool = _drag_from_handle
	var recycled: bool = host != null and host.recycle_rect().has_point(position)
	if slot >= 0:
		Haptics.pulse(Haptics.DROP_MSEC)
		_suit_os().pin_to_slot(slot, _drag_id)
	elif recycled:
		# Soltar sobre la zona de reciclaje vacia el slot, igual que con el mouse (FD-304 §6).
		Haptics.pulse(Haptics.DROP_MSEC)
		_suit_os().clear_slot(_suit_os().get_pinned_slots().find(_drag_id))
	# Soltar el item CONSUME el gesto del hold, igual que elegirlo (_select). Sin esto, tras
	# arrastrar con A y soltar, el release del hombro caia en _confirm_or_dismiss() y ACTIVABA
	# el item que seguia marcado: el arrastre funcionaba y ademas se abria la pantalla.
	if _tab_hold_active:
		_picked_during_hold = true
	_end_option_drag()
	if slot >= 0 and from_handle:
		_exit()

func _end_option_drag() -> void:
	VirtualMouse.set_dragging(false)
	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null
	_drag_option = -1
	_drag_id = ""
	_mouse_drag_pending = false
	_mouse_drag_position = Vector2.ZERO
	_mouse_drag_moved = false
	_drag_from_handle = false
	if _restore_mouse_capture_after_drag:
		# Si el cursor virtual sigue en modo desktop (una pantalla abierta lo pide), no se puede
		# recapturar: se queda HIDDEN.
		if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("is_desktop_mouse_mode") \
				and _virtual_mouse.is_desktop_mouse_mode():
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_restore_mouse_capture_after_drag = false
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(false)

# El widget ampliado de una pantalla que es solo widget: pasado el hold y con el dedo en movimiento
# se levanta, vuelve al tamaño de slot y sigue al dedo.
func _drive_view_drag(position: Vector2, allow_stationary: bool = false) -> bool:
	var widget: Control = _mount.get_widget()
	if not is_instance_valid(widget):
		# Pantalla con vista propia (presentador 3D): el asa sigue el mesh con el cursor y muestra
		# los destinos; al soltar ancla la pantalla al slot.
		if not _dragging_view:
			if not _view_drag_candidate or OS.get_ticks_msec() - _touch_press_msec < DRAG_HOLD_MSEC \
					or (not allow_stationary and (position - _touch_start).length() < TOUCH_MIN_DRAG):
				return false
			_dragging_view = true
			Haptics.pulse(Haptics.LIFT_MSEC)
			_capture_drag_mesh()
		_follow_drag_mesh(position)
		var host_full = _widget_host()
		if host_full != null:
			host_full.show_drop_targets(true, host_full.slot_at(position))
		return true
	if not _dragging_view:
		if not _view_drag_candidate or OS.get_ticks_msec() - _touch_press_msec < DRAG_HOLD_MSEC \
				or (not allow_stationary and (position - _touch_start).length() < TOUCH_MIN_DRAG):
			return false
		_dragging_view = true
		Haptics.pulse(Haptics.LIFT_MSEC)
		widget.rect_pivot_offset = Vector2.ZERO
		widget.rect_scale = Vector2.ONE * UIScaleCompensator.scale_for(self)
	widget.rect_global_position = position - widget.rect_size * widget.rect_scale * 0.5
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(true, host.slot_at(position))
	return true


# El cuerpo del panel (fuera de sus botones): zona de arrastre del widget ampliado.
func _on_view_body(position: Vector2) -> bool:
	if not _view_screen_rect().has_point(position):
		return false
	return not HudWidgetActionScript.pointer_on_button(_mount.get_widget(), position)


# Mouse: levanta el panel al instante (como el radial), sin esperar el hold. Se apoya en el mismo
# _drive_view_drag de touch/gamepad, que hace el resto.
func _begin_mouse_view_drag(position: Vector2) -> void:
	_view_drag_candidate = true
	_drag_from_handle = false
	_touch_start = position
	_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC
	if _drive_view_drag(position, true):
		VirtualMouse.set_dragging(true)

# FD-304 §6 (modo pantalla, gamepad): el hombro sostenido levanta la pantalla abierta y el stick
# la lleva a otro slot; soltar el hombro la suelta. Reusa _drive_view_drag()/_drop_view().
# Un simple tap del hombro no arrastra: el gesto es hold (o stick) + soltar.
func _drive_screen_view_drag(input, slot_gesture: int) -> bool:
	var slot: int = int(input.hud_slot) - 1
	if _view_drag_from_gamepad:
		if slot < 0 or not _widget_screen_showing():
			_drop_view(_cursor)
		else:
			_move_gamepad_view_cursor(input)
		return true
	if slot < 0 or not _widget_screen_showing() or _opened_on_press:
		# `_opened_on_press` = la pantalla la abrio este mismo hombro por adelantado: el hold es
		# para el radial de ese slot (FD-304 §3), no para arrastrar la pantalla.
		return false
	var move := Vector2(input.move_vec.x, input.move_vec.y)
	var stick_moved: bool = bool(input.analog_move_active) and move.length_squared() > MOVE_GESTURE_DEADZONE_SQ
	if slot_gesture != Gesture.HOLD and not stick_moved:
		return false
	_view_drag_from_gamepad = true
	_dragging_view = true
	_view_drag_candidate = true
	_set_cursor(_view_screen_rect().get_center(), get_viewport_rect().size)
	_touch_start = _cursor
	_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC # el hold ya se cumplio al abrir
	Haptics.pulse(Haptics.LIFT_MSEC)
	_move_gamepad_view_cursor(input)
	return true


func _move_gamepad_view_cursor(input) -> void:
	var move := Vector2(input.move_vec.x, input.move_vec.y)
	if bool(input.analog_move_active) or move.length_squared() > MOVE_GESTURE_DEADZONE_SQ:
		_move_cursor(move.limit_length(1.0) * STICK_DRAG_SPEED, get_viewport_rect().size)
	_drive_view_drag(_cursor)

# Mesh de la pantalla del presentador (si la hay): es lo que el asa arrastra en pantallas con vista.
func _presenter_screen_mesh() -> Node:
	var presenter = _mount.get_presenter()
	if not is_instance_valid(presenter):
		return null
	if presenter.has_method("_get_hud_attach_target"):
		return presenter._get_hud_attach_target()
	return presenter.get_node_or_null("ScreenContainer/ScreenMesh")

# Al arrastrar una Pantalla se levanta un WIDGET (no la ventana 3D, que se ve lenta y rara). El
# widget sigue al cursor y hace snap/atraccion al slot bajo el cursor.
func _capture_drag_mesh() -> void:
	_restore_drag_mesh()
	var panel := Panel.new()
	panel.name = "ScreenDragWidget"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.rect_size = Vector2(220.0, 130.0)
	panel.rect_pivot_offset = panel.rect_size * 0.5
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = _screen_title(_suit_os().get_active_screen_id())
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	panel.add_child(label)
	add_child(panel)
	_drag_widget = panel

func _follow_drag_mesh(position: Vector2) -> void:
	if not is_instance_valid(_drag_widget):
		return
	var host = _widget_host()
	var slot: int = host.slot_at(position) if host != null else -1
	var target: Vector2 = position
	if slot >= 0 and host != null:
		target = host.slot_rect(slot).get_center() # atraccion/snap al slot
	_drag_widget.rect_position = target - _drag_widget.rect_size * 0.5
	_drag_widget.modulate = Color(0.6, 0.9, 1.0, 0.95) if slot >= 0 else Color(1, 1, 1, 0.85)

func _restore_drag_mesh() -> void:
	if is_instance_valid(_drag_widget):
		_drag_widget.queue_free()
	_drag_widget = null
	_drag_mesh = null
	_drag_mesh_xf = Transform()
	_drag_mesh_scale = Vector3.ONE

# Soltarlo sobre un slot lo fija ahi y cierra el modo HUD: el widget queda en su slot. En cualquier
# otro lado vuelve a la vista ampliada.
func _drop_view(position: Vector2) -> void:
	VirtualMouse.set_dragging(false)
	_restore_drag_mesh()
	_dragging_view = false
	_view_drag_candidate = false
	_view_drag_from_gamepad = false
	var host = _widget_host()
	var slot: int = host.slot_at(position) if host != null else -1
	if host != null:
		host.show_drop_targets(false)
	var suit_os: Node = _suit_os()
	var id: String = suit_os.get_active_screen_id()
	if slot >= 0 and suit_os.has_screen(id):
		Haptics.pulse(Haptics.DROP_MSEC)
		suit_os.pin_to_slot(slot, id)
		_exit()
	elif suit_os.has_screen(id):
		_show_screen(id)

# --- Ghost de transicion del widget (slot <-> ampliado) ---
# Visual y descartable: un panel que viaja entre dos rects y se desvanece. No toca el layout real
# del widget ni el estado de gameplay, asi que no afecta determinismo ni tests.

func _spawn_screen_transition_in(id: String) -> void:
	if not is_inside_tree():
		return
	var widget: Control = _mount.get_widget()
	if not is_instance_valid(widget) or widget.rect_size.x <= 0.0:
		return
	var target := Rect2(widget.rect_global_position, widget.rect_size * widget.rect_scale)
	var from := target.grow(-min(target.size.x, target.size.y) * 0.14)
	_spawn_transition_ghost(from, target, _screen_title(id))

func _spawn_screen_transition_out() -> void:
	if not is_inside_tree():
		return
	var widget: Control = _mount.get_widget()
	if not is_instance_valid(widget) or widget.rect_size.x <= 0.0:
		return
	var from := Rect2(widget.rect_global_position, widget.rect_size * widget.rect_scale)
	var to := from.grow(-min(from.size.x, from.size.y) * 0.16)
	_spawn_transition_ghost(from, to, "")

func _spawn_transition_ghost(from_rect: Rect2, to_rect: Rect2, _title: String = "") -> void:
	if from_rect.size.x <= 0.0 or to_rect.size.x <= 0.0 or not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.name = "ScreenTransitionGhost"
	layer.layer = 128
	get_tree().root.add_child(layer)
	# Solo un tinte muy suave que viaja y se desvanece: nada que tape el widget ni que parezca un
	# panel.
	var ghost := ColorRect.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.color = Color(0.6, 0.9, 1.0, 0.14)
	ghost.rect_position = from_rect.position
	ghost.rect_size = from_rect.size
	layer.add_child(ghost)
	var tween := Tween.new()
	layer.add_child(tween)
	tween.interpolate_property(ghost, "rect_position", from_rect.position, to_rect.position, 0.18, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tween.interpolate_property(ghost, "rect_size", from_rect.size, to_rect.size, 0.18, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tween.interpolate_property(ghost, "color:a", 0.14, 0.0, 0.22, Tween.TRANS_SINE, Tween.EASE_OUT, 0.05)
	# La capa entera se va cuando termina (el ghost es su unico hijo ademas del Tween).
	tween.interpolate_callback(layer, 0.30, "queue_free")
	tween.start()

func _screen_title(id: String) -> String:
	var suit_os: Node = _suit_os()
	var screen: Object = suit_os.get_screen(id)
	if screen != null and screen.has_method("screen_title"):
		return screen.screen_title()
	# Un favorito de otro nivel sigue teniendo nombre: sale del ultimo snapshot conocido.
	if suit_os.has_method("screen_title_of"):
		return String(suit_os.screen_title_of(id))
	return id


func _dial_id_at(index: int) -> String:
	return String(_dial_ids[index]) if index >= 0 and index < _dial_ids.size() else ""


# --- Frescura del registry (FD-306 §5) ---

func _refresh_screens(_id: String = "") -> void:
	var suit_os: Node = _suit_os()
	if not is_instance_valid(suit_os):
		return
	_screen_ids = suit_os.get_registered_screens()
	_placeholder.visible = _screen_ids.empty() and not _selector.is_open() and not _drawer_open()
	if is_instance_valid(_drawer):
		_drawer.set_rows(_drawer_rows())


# --- Drawer (FD-305 §3) ---

func _drawer_open() -> bool:
	return is_instance_valid(_drawer) and _drawer.visible


func _drawer_rows() -> Array:
	var suit_os: Node = _suit_os()
	var rows: Array = []
	var seen := {}
	# Todo el registry, mas los favoritos de otros niveles: un favorito offline se sigue viendo
	# (marcado) para poder quitarlo, en vez de desaparecer al cambiar de escena.
	var ids: Array = _screen_ids.duplicate()
	if suit_os.has_method("get_favorites"):
		for id in suit_os.get_favorites():
			if not ids.has(id):
				ids.append(id)
	for id in ids:
		if seen.has(id):
			continue
		seen[id] = true
		var screen: Object = suit_os.get_screen(id)
		var snapshot: Dictionary = {}
		if screen != null and screen.has_method("widget_snapshot"):
			snapshot = screen.widget_snapshot()
		rows.append({
			"id": id,
			"title": _screen_title(id),
			"source": "online" if screen != null else "offline",
			"favorite": suit_os.has_method("is_favorite") and suit_os.is_favorite(id),
			"alarm": bool(snapshot.get("alarm", false))
		})
	return rows


func _open_drawer() -> void:
	# El unico cierre del dial que no tiene nada que lo tape en el mismo frame: el drawer entra
	# encima mientras el anillo se retrae hacia el centro (FD-304 §8). Cerrar hacia una pantalla
	# tiene que ser sincronico, y salir del modo HUD se lleva el overlay entero.
	_selector.close_animated()
	_placeholder.visible = false
	_view_host.visible = false
	if not is_instance_valid(_drawer):
		_drawer = DrawerScript.new()
		_drawer.name = "SuitOSDrawer"
		add_child(_drawer)
		_drawer.connect("screen_chosen", self, "_on_drawer_chose")
		_drawer.connect("favorite_toggled", self, "_on_drawer_favorited")
	_drawer.visible = true
	_drawer.set_rows(_drawer_rows())
	# El drawer va con el mouse CAPTURADO y el cursor unico movido por deltas: con HIDDEN se
	# movia mal.
	_set_cursor(get_viewport_rect().size * 0.5, get_viewport_rect().size)
	_cursor_moved = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_end_drawer_row_drag()
	_set_virtual_mouse_enabled(false)
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_gamepad_cursor_enabled"):
		_virtual_mouse.set_gamepad_cursor_enabled(false)


# Sostener el boton del HUD desde el juego o desde una pantalla: el cajon entra sin dial
# detras. Cierra lo que estuviera mostrandose para que no quede una vista abajo.
func _open_drawer_direct() -> void:
	_drawer_entered_direct = true
	if _mount.is_showing() or is_instance_valid(_active_focused_screen):
		_cleanup_focus()
		_mount.close()
		_suit_os().close_screen()
	_open_drawer()


func _close_drawer() -> void:
	if is_instance_valid(_drawer):
		_drawer.visible = false
	_placeholder.visible = _screen_ids.empty()
	_end_drawer_row_drag()
	if is_instance_valid(_drag_ghost):
		_end_option_drag()
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_gamepad_cursor_enabled"):
		_virtual_mouse.set_gamepad_cursor_enabled(true)


# Salida del drawer: vuelve al dial si el drawer se abrio desde el, o sale del modo HUD si se
# entro directo. Misma ruta para B (mando) y para el clic fuera de toda fila (mouse/dedo).
func _dismiss_drawer() -> void:
	_close_drawer()
	# Se entro directo (hold): el retroceso vuelve al juego. Abrir un dial que el jugador
	# nunca abrio seria aparecerle una pantalla que no pidio.
	if _drawer_entered_direct or _dial_ids.empty():
		_drawer_entered_direct = false
		_exit()
	else:
		_open_radial(_target_slot)


func _on_drawer_chose(id: String) -> void:
	_close_drawer()
	_drawer_entered_direct = false
	if _target_slot >= 0:
		_suit_os().pin_to_slot(_target_slot, id)
	_show_screen(id)


func _on_drawer_favorited(_id: String, _is_favorite: bool) -> void:
	# El arco se rehace la proxima vez que se abra: reordenarlo mientras el drawer esta encima
	# solo serviria para que cambie a espaldas del jugador.
	pass

# --- Asa de la pantalla abierta ---

# Arriba al centro de la vista (dentro si la vista toca el borde de arriba). Solo con una pantalla a
# la vista y sin dial ni arrastre en curso. Los widgets ampliados no llevan asa (revision
# 2026-09-19): su propio panel es la zona de arrastre, como en los slots.
func _update_view_handle() -> void:
	if not is_instance_valid(_view_handle):
		return
	var rect: Rect2 = _view_screen_rect() if _mount.is_showing() else Rect2()
	# El asa es solo para las Pantallas con vista propia (sin panel arrastrable). Un widget
	# ampliado se arrastra desde su cuerpo, asi que no la lleva.
	var show: bool = rect.size.x > 0.0 and rect.size.y > 0.0 and not _selector.is_open() \
		and not _dragging_view and not is_instance_valid(_drag_ghost) and not _showing_widget_only()
	_view_handle.visible = show
	if not show:
		return
	var k: float = UIScaleCompensator.scale_for(self)
	var size: Vector2 = HANDLE_SIZE * k
	var y: float = rect.position.y - size.y - HANDLE_GAP * k
	if y < HANDLE_GAP * k:
		y = rect.position.y + HANDLE_GAP * k
	var x: float = clamp(rect.position.x + (rect.size.x - size.x) * 0.5, 0.0, get_viewport_rect().size.x - size.x)
	_view_handle.rect_position = Vector2(x, y)
	if _view_handle.rect_size != size:
		_view_handle.rect_size = size
		_view_handle.update()

func _update_camera_focus_button() -> void:
	if not is_instance_valid(_camera_focus_button):
		return
	var screen: Object = _suit_os().get_screen(_suit_os().get_active_screen_id())
	var snapshot: Dictionary = screen.widget_snapshot() if screen != null and screen.has_method("widget_snapshot") else {}
	var remote_view: bool = _suit_os().get("presents_views_in_2d") == true
	var show: bool = remote_view and not _selector.is_open() and _mount.is_showing() \
		and String(snapshot.get("id", "")).begins_with("holoterminal:") and bool(snapshot.get("can_focus", false))
	_camera_focus_button.visible = show
	if not show:
		return
	var focused: bool = bool(snapshot.get("focused", false))
	_camera_focus_button.set_pressed_no_signal(focused)
	_camera_focus_button.icon = EyeClosed if focused else EyeOpen
	_camera_focus_button.hint_tooltip = "Dejar de enfocar cámara del piloto" if focused else "Enfocar cámara del piloto"
	var rect: Rect2 = _view_screen_rect()
	var size: Vector2 = CAMERA_FOCUS_SIZE * UIScaleCompensator.scale_for(self)
	_camera_focus_button.rect_size = size
	_camera_focus_button.rect_position = Vector2(
		clamp(rect.position.x + (rect.size.x - size.x) * 0.5, 0.0, get_viewport_rect().size.x - size.x),
		rect.end.y + HANDLE_GAP * UIScaleCompensator.scale_for(self))

func _on_camera_focus_pressed() -> void:
	var id: String = _suit_os().get_active_screen_id()
	if not id.empty():
		_suit_os().perform_action(id, "toggle_focus")

func is_on_view_handle(point: Vector2) -> bool:
	return is_instance_valid(_view_handle) and _view_handle.visible \
		and _view_handle.get_global_rect().grow(HANDLE_GAP * UIScaleCompensator.scale_for(self)).has_point(point)

func _is_on_camera_focus_button(point: Vector2) -> bool:
	return is_instance_valid(_camera_focus_button) and _camera_focus_button.visible \
		and _camera_focus_button.get_global_rect().has_point(point)

# Una pastilla con tres rayas de agarre.
func _draw_view_handle() -> void:
	var size: Vector2 = _view_handle.rect_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.1, 0.13, 0.85)
	style.border_color = Color(0.0, 0.83, 1.0, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(size.y * 0.5))
	_view_handle.draw_style_box(style, Rect2(Vector2.ZERO, size))
	var line := Color(0.0, 0.83, 1.0, 0.9)
	for i in range(3):
		var y: float = size.y * (0.3 + 0.2 * i)
		_view_handle.draw_line(Vector2(size.x * 0.3, y), Vector2(size.x * 0.7, y), line, 1.5, true)

# El host de widgets de este mismo backend (el del juego cuelga de SuitOS; el del control, del home).
func _widget_host() -> Node:
	var suit_os: Node = _suit_os()
	for host in get_tree().get_nodes_in_group("hud_widget_host"):
		if host._backend() == suit_os:
			return host
	return null

# TouchCameraControls: un dedo del modo HUD no gira la camara. Con el dial a la vista es del dial (o
# de un widget); con una pantalla abierta, lo que cae en ella o en su asa (usarla, arrastrar su
# widget). Fuera de la pantalla si es camara, y el joystick y los botones siguen siendo suyos.
func blocks_touch_camera(point: Vector2) -> bool:
	if is_queued_for_deletion() or _on_touch_controls(point):
		return false
	if _selector.is_open():
		return true
	if not _mount.is_showing():
		return false
	return is_on_view_handle(point) or _is_on_camera_focus_button(point) or _view_screen_rect().has_point(point)

func _on_touch_controls(point: Vector2) -> bool:
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	return mobile != null and mobile.has_method("is_point_on_touch_controls") \
		and mobile.is_point_on_touch_controls(point)

# Tocar fuera de la pantalla la cierra, simetrico con tocar el widget del slot para abrirla.
func _is_outside_view(pos: Vector2) -> bool:
	if not _opened or _selector.is_open() or not _mount.is_showing() or is_on_view_handle(pos) \
			or _is_on_camera_focus_button(pos):
		return false
	var rect: Rect2 = _view_screen_rect()
	return rect.size.x > 0.0 and rect.size.y > 0.0 and not rect.has_point(pos)


# El area que ocupa la vista en pantalla: el widget ampliado (2D) o, lo habitual, el cuadro del
# presentador 3D proyectado con la camara.
func _view_screen_rect() -> Rect2:
	if _mount.get_view_rect().size != Vector2.ZERO:
		return _mount.get_view_rect()
	var widget: Control = _mount.get_widget()
	if is_instance_valid(widget):
		# La transformacion dibujada: rect_global_position ya trae el corrimiento del pivote y la
		# escala, y sumarselos otra vez corria el rect media pantalla. Tocar el boton del widget
		# ampliado caia "fuera de la pantalla" y cerraba el modo HUD en vez de oprimirlo.
		var xf: Transform2D = widget.get_global_transform_with_canvas()
		return Rect2(xf.origin, widget.rect_size * xf.get_scale())
	var presenter: Spatial = _mount.get_presenter()
	var camera: Camera = get_viewport().get_camera()
	if presenter == null or camera == null:
		return Rect2()
	# El mesh puede estar reparentado a la camara (hud_attach_as_child), como en reveal_presenter.
	var mesh = presenter._get_hud_attach_target() if presenter.has_method("_get_hud_attach_target") \
		else presenter.get_node_or_null("ScreenContainer/ScreenMesh")
	if not is_instance_valid(mesh) or not ("width" in mesh) or not ("height" in mesh):
		return Rect2()
	var half_w: float = float(mesh.width) * 0.5
	var half_h: float = float(mesh.height) * 0.5
	var xf: Transform = mesh.global_transform
	var rect := Rect2(camera.unproject_position(xf.xform(Vector3(-half_w, -half_h, 0.0))), Vector2.ZERO)
	for corner in [Vector3(half_w, -half_h, 0.0), Vector3(-half_w, half_h, 0.0), Vector3(half_w, half_h, 0.0)]:
		rect = rect.expand(camera.unproject_position(xf.xform(corner)))
	return rect


# Pantalla que es solo widget (sin vista propia): se dibuja el panel ampliado, no un presentador.
# Su panel entero es la zona de arrastre, asi que no necesita asa (revision 2026-09-19).
func _showing_widget_only() -> bool:
	return _mount.is_showing() and is_instance_valid(_mount.get_widget())


# Cuentan angulo y magnitud: dentro de AIM_DEAD_ZONE del centro el dial no marca nada.
func _point_at(aim: Vector2) -> void:
	_aim = aim.limit_length(AIM_RADIUS)
	_selector.point_at(_selector.rect_size * 0.5 + _aim)

# El arco lo llenan los FAVORITOS, no el registry (FD-305 §2): el jugador decide que esta a mano.
# Su orden es la relevancia del momento, resuelta UNA vez al abrir y no por frame, o las opciones
# se reordenarian bajo el dedo (FD-306 §2). Lo demas vive en el drawer, detras del hub.
func _open_radial(slot: int = -1) -> void:
	_target_slot = slot
	_aim = Vector2.ZERO
	_stick_aiming = false
	_mouse_aim_active = false
	_dial_ids = _dial_screen_ids()
	if _dial_ids.size() == 1 and _screen_ids.size() <= 1:
		# Una sola pantalla y nada mas que elegir: se abre directo, como siempre.
		_select(0)
		return
	var suit_os: Node = _suit_os()
	var items: Array = []
	for id in _dial_ids:
		var screen: Object = suit_os.get_screen(id)
		var title: String = String(screen.screen_title()) if screen != null and screen.has_method("screen_title") \
			else _screen_title(id)
		items.append({
			"id": id, "label": title,
			"icon": screen.screen_icon() if screen != null and screen.has_method("screen_icon") else null,
			"enabled": true
		})
	_selector.set_options(items)
	_selector.open()
	# Al entrar al radial el item del centro (hub) queda seleccionado; si el radial viene fijado a un
	# slot (hold de hombro), se marca el widget de ese slot. Si el slot NO es un favorito, se abre
	# el drawer con su opcion marcada.
	if slot >= 0:
		var id: String = _suit_os().slot_screen_id(slot)
		var index: int = _dial_ids.find(id)
		if index >= 0:
			_point_at(_selector.option_center(index) - _selector.rect_size * 0.5)
		elif not id.empty() and _suit_os().has_screen(id):
			_open_drawer()
			var row: int = _drawer.index_of(id)
			if row >= 0:
				_drawer.focus_row(row)
			return
	else:
		_point_at(Vector2.ZERO) # centro = hub
	_placeholder.visible = _dial_ids.empty() and _screen_ids.empty()
	_set_virtual_mouse_enabled(false)
	_view_host.visible = false


# Favoritos ordenados, filtrados por el backend. El control remoto no tiene favoritos propios:
# ahi el arco sigue siendo el registry, como hasta ahora.
func _dial_screen_ids() -> Array:
	var suit_os: Node = _suit_os()
	if suit_os != null and suit_os.has_method("get_favorites_ordered"):
		return suit_os.get_favorites_ordered()
	return _screen_ids.duplicate()

# Soltar TAB tras el hold conserva una pantalla ya elegida. Si el dial sigue abierto, lo marcado
# queda elegido (el dial no se queda abierto); sin nada marcado se vuelve a la pantalla que habia,
# o se sale si no habia ninguna.
func _release_tab_hold() -> void:
	_tab_hold_active = false
	# El hold del boton tactil no tiene stick que volver al centro: si solto sobre el hub, lo
	# confirma. Solo ese origen: el reflejo del stick y el mouse que vuelve al medio descartan
	# (FD-306 §1.1, test_letting_go_on_the_hub... / test_release_in_the_dead_zone...).
	var touch_hold: bool = _consume_touch_hud_hold()
	if is_instance_valid(_drag_ghost):
		# Se estaba arrastrando un widget con el stick: soltar el hombro lo suelta donde este.
		_drop_option(_cursor)
		_picked_during_hold = false
		return
	if _picked_during_hold:
		_picked_during_hold = false
		return
	if not _selector.is_open():
		return
	if _selector.hub_hovered():
		if touch_hold:
			_selector.confirm()
		else:
			_dismiss_radial()
		return
	_confirm_or_dismiss() # con algo marcado -> _select, ya sin hold activo: la pantalla se queda

# El boton tactil del HUD avisa cuando lo apretaron (MobileUIManager.note_hud_touch). Se consume
# aca una sola vez, en el release del hold.
func _consume_touch_hud_hold() -> bool:
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	return mobile != null and mobile.has_method("consume_hud_touch") and bool(mobile.consume_hud_touch())

# Oprimir con algo marcado lo elige; sin nada marcado (zona muerta, o fuera del dial) lo cierra.
func _confirm_or_dismiss() -> void:
	if _selector.has_selection():
		_selector.confirm()
	else:
		_dismiss_radial()

# Cerrar el dial sin elegir siempre sale del modo HUD.
func _dismiss_radial() -> void:
	_opened_on_press = false
	_exit()

func _select(index: int) -> void:
	var suit_os: Node = _suit_os()
	if index == RadialSelectorV2.HUB_INDEX:
		# El hub no es una app: es la puerta al resto. Elegirlo abre el drawer y deja el dial
		# cerrado (el drawer es una vista, no un submenu del dial).
		_picked_during_hold = _tab_hold_active
		_open_drawer()
		return
	if index < 0 or index >= _dial_ids.size():
		return
	if _tab_hold_active:
		_picked_during_hold = true
	_opened_on_press = false
	var id: String = _dial_ids[index]
	if _target_slot >= 0:
		suit_os.pin_to_slot(_target_slot, id)
	_show_screen(id)

# El mouse virtual es para usar una pantalla (clic en su UI), no para el dial, que se apunta con
# el stick o el mouse. Se activa solo con cualquier boton o eje de gamepad: apretar el boton del
# HUD o mover el stick para apuntar lo prendia encima del dial, y con TAB (teclado) no. Apagado
# mientras el dial esta abierto, los dos entran igual.
func _set_virtual_mouse_enabled(enabled: bool) -> void:
	if not is_instance_valid(_virtual_mouse):
		return
	_virtual_mouse.set_process(enabled)
	_virtual_mouse.set_process_input(enabled)
	if enabled:
		_virtual_mouse.visible = true
		if _virtual_mouse.has_method("set_gamepad_cursor_enabled"):
			# Con el drawer abierto el mando navega la lista directo: su cursor inyectaria clicks.
			_virtual_mouse.set_gamepad_cursor_enabled(not _drawer_open())
	if not enabled:
		if _virtual_mouse.has_method("set_desktop_mouse_mode"):
			_virtual_mouse.set_desktop_mouse_mode(false)
		_virtual_mouse.visible = false

func _show_screen(id: String) -> void:
	_set_virtual_mouse_enabled(true)
	_release_mouse_for_screen()
	var suit_os: Node = _suit_os()
	var screen: Object = suit_os.get_screen(id)
	# Los favoritos pueden conservar el ultimo snapshot de una pantalla que ya salio de
	# escena. No hay nodo ni Viewport que montar hasta que vuelva a registrarse.
	if not is_instance_valid(screen):
		_refresh_screens()
		return
	suit_os.open_screen(id)
	_selector.close()
	_view_host.visible = true

	var origin: Dictionary = {}
	if screen != null and screen.has_method("view_transition_origin"):
		origin = screen.view_transition_origin()

	if origin.get("kind", "") == "focus_rig":
		_cleanup_focus()
		_active_focused_screen = screen
		_set_surface_cursor_uv(Vector2(0.5, 0.5))
		_pending_focus_screen = screen
		var rig = get_node_or_null(origin.get("path", NodePath("")))
		_pending_focus_camera = rig.get_node_or_null("Camera") as Camera if is_instance_valid(rig) else null
		_view_host.visible = false
		if screen.has_method("enter_focus_mode"):
			screen.enter_focus_mode()
		_mount_focused_screen_if_ready()
	else:
		_cleanup_focus()
		if screen.has_method("view_requires_input") and screen.view_requires_input():
			_active_focused_screen = screen
			_set_surface_cursor_uv(Vector2(0.5, 0.5))
			# Cursor ABSOLUTO sobre la superficie, igual que las pantallas con foco: el
			# overlay proyecta el puntero real (o el del mando) con _screen_surface_uv.
			# El camino relativo (_focus_cursor_scale + delta) hacia que el cursor de la
			# Consola derivara y no cayera bajo el puntero.
			if is_instance_valid(_virtual_mouse):
				_virtual_mouse.relative_target_scale = Vector2.ZERO
			_set_focus_cursor_over_surface(false)
			if screen.has_method("enter_focus_mode"):
				screen.enter_focus_mode()
		var snapshot: Dictionary = screen.widget_snapshot() if screen.has_method("widget_snapshot") else {"id": id}
		_mount.show(screen, snapshot, _view_host)
	_sync_widget_focus()
	if _showing_widget_only():
		# Ghost de transicion slot <-> widget ampliado (visual, no toca layout ni estado).
		call_deferred("_spawn_screen_transition_in", id)

# Un hudable sin Pantalla muestra su widget ampliado. No usa mouse: se navega entre sus botones
# (cruceta o flechas, la navegacion de foco de la GUI) y se oprime el enfocado con el gatillo
# derecho, jump, crouch o ui_accept. En el host el modo HUD pausa el mundo, asi que esas acciones
# no hacen nada mas y quedan libres para eso.
func _sync_widget_focus() -> void:
	var widget = _mount.get_widget()
	if not is_instance_valid(widget) or _selector.is_open():
		return
	# Revision 2026-09-19: el panel ampliado acepta mouse (liberado) ademas del foco por mando.
	# Sin mouse, la cruceta/flechas siguen navegando los botones y el gatillo/A los oprime.
	_set_virtual_mouse_enabled(true)
	_widget_click_was_down = true
	HudWidgetActionScript.focus_first_button(widget)


# El modo pantalla libera el puntero: HIDDEN (nunca capturado) para poder clickear y arrastrar
# con el mouse virtual. Lo mismo que hace el clic derecho en gameplay.
func _release_mouse_for_screen() -> void:
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_desktop_mouse_mode"):
		_virtual_mouse.set_desktop_mouse_mode(true, get_viewport().get_mouse_position())

func _widget_screen_showing() -> bool:
	return is_instance_valid(_mount.get_widget()) and not _selector.is_open()

func _drive_widget_screen(input) -> void:
	if not _widget_screen_showing():
		return
	# Un solo flanco para todo: A es crouch y ui_accept a la vez, y oprimir dos veces el toggle de
	# la linterna en el mismo toque la dejaba como estaba.
	var down: bool = bool(input.tool_fire_primary) or bool(input.jump) or bool(input.crouch) \
		or Input.is_action_pressed("ui_accept")
	if down and not _widget_click_was_down:
		HudWidgetActionScript.press_focused_button(_mount.get_widget())
	_widget_click_was_down = down

func _cleanup_focus() -> void:
	_pending_focus_screen = null
	_pending_focus_camera = null
	_pending_swap_screen = null
	if is_instance_valid(_virtual_mouse):
		# Se apago al montar una pantalla con cursor propio (_complete_focus_swap): volver
		# a prenderlo, no solo a mostrarlo. _exit() lo apaga otra vez enseguida.
		_set_virtual_mouse_enabled(true)
		_virtual_mouse.relative_target_scale = Vector2.ZERO
	if VisualServer.is_connected("frame_post_draw", self, "_complete_focus_swap"):
		VisualServer.disconnect("frame_post_draw", self, "_complete_focus_swap")
	if is_instance_valid(_active_focused_screen):
		if _active_focused_screen.has_method("set_source_view_visible"):
			_active_focused_screen.set_source_view_visible(true)
		if _active_focused_screen.has_method("exit_focus_mode"):
			_active_focused_screen.exit_focus_mode()
	_active_focused_screen = null

# Quien dibuja el cursor: adentro de la superficie el del Viewport de la pantalla, afuera el
# mouse virtual 2D. Nunca los dos.
func _set_focus_cursor_over_surface(over: bool) -> void:
	if is_instance_valid(_virtual_mouse):
		_virtual_mouse.visible = not over
	if is_instance_valid(_active_focused_screen) \
			and _active_focused_screen.has_method("set_view_cursor_visible"):
		_active_focused_screen.set_view_cursor_visible(over)

# --- Cursor unico: movimiento, tope y proyeccion a la superficie ---

# Mueve el cursor por delta y lo topa contra el espacio activo (viewport del overlay o Viewport
# de la pantalla enfocada). Un solo camino para stick, dedo y mouse capturado; el signo ya viene
# resuelto por quien llama (_surface_u_flip en la superficie).
func _move_cursor(delta: Vector2, bounds: Vector2) -> void:
	if delta != Vector2.ZERO:
		_cursor_moved = true
	_cursor += delta
	_cursor.x = clamp(_cursor.x, 0.0, bounds.x)
	_cursor.y = clamp(_cursor.y, 0.0, bounds.y)

func _set_cursor(position: Vector2, bounds: Vector2) -> void:
	_cursor = Vector2(clamp(position.x, 0.0, bounds.x), clamp(position.y, 0.0, bounds.y))

# Espacio del cursor de la pantalla enfocada: su resolucion de diseno, no la del overlay.
func _surface_design_size() -> Vector2:
	if is_instance_valid(_active_focused_screen) and _active_focused_screen.has_method("view_size"):
		var design: Vector2 = _active_focused_screen.view_size()
		if design.x > 0.0 and design.y > 0.0:
			return design
	return get_viewport_rect().size

func _surface_cursor_uv() -> Vector2:
	var design: Vector2 = _surface_design_size()
	if design.x <= 0.0 or design.y <= 0.0:
		return Vector2(0.5, 0.5)
	return Vector2(_cursor.x / design.x, _cursor.y / design.y)

func _set_surface_cursor_uv(uv: Vector2) -> void:
	_cursor = uv * _surface_design_size()
	_cursor_moved = false

# El signo de U del mesh no es fijo: sale del basis REAL del presentador. Se proyectan los dos
# extremos de su eje local X y se ve para que lado cae el +X en pantalla. Un mesh que mira a la
# camara lo tiene invertido; uno que mira al frente, no. Unica autoridad de signo: la usan tanto
# la proyeccion del mouse (_screen_surface_uv) como el delta del stick sobre la superficie.
func _surface_u_flip(mesh = null, cam: Camera = null) -> bool:
	var m = mesh if is_instance_valid(mesh) else _presenter_screen_mesh()
	var c: Camera = cam if cam != null else get_viewport().get_camera()
	if not is_instance_valid(m) or c == null or not ("width" in m):
		return true # sin mesh 3D (vista 2D del control remoto): se conserva el signo historico
	var half_w: float = float(m.width) * 0.5
	var xf: Transform = m.global_transform
	var minus_x: float = c.unproject_position(xf.xform(Vector3(-half_w, 0.0, 0.0))).x
	var plus_x: float = c.unproject_position(xf.xform(Vector3(half_w, 0.0, 0.0))).x
	return plus_x < minus_x

# Donde cae un punto de pantalla sobre la superficie de la pantalla enfocada, en uv [0,1].
# (-1,-1) = fuera. Se proyectan las esquinas del mesh del presentador con la camara activa,
# que es lo unico que sabe donde quedo dibujado. Todo se normaliza porque unproject_position
# devuelve pixeles del viewport de RENDER y el evento viene en el espacio de GUI estirado.
func _screen_surface_uv(point: Vector2) -> Vector2:
	var presenter = _mount.get_presenter()
	if not is_instance_valid(presenter):
		return Vector2(-1.0, -1.0)
	# OJO: en modo pegado a camara el presentador REPARENTA su ScreenMesh bajo la camara,
	# asi que "ScreenContainer/ScreenMesh" ya no existe bajo el presentador. Se pregunta por
	# el destino de enganche, que es como lo resuelve HudViewMount.reveal_presenter().
	var mesh = presenter._get_hud_attach_target() if presenter.has_method("_get_hud_attach_target") else null
	if not is_instance_valid(mesh):
		mesh = presenter.get_node_or_null("ScreenContainer/ScreenMesh")
	var cam: Camera = get_viewport().get_camera()
	if not is_instance_valid(mesh) or cam == null:
		return Vector2(-1.0, -1.0)
	var half_w: float = float(mesh.width) * 0.5
	var half_h: float = float(mesh.height) * 0.5
	var xf: Transform = mesh.global_transform
	var top_left: Vector2 = cam.unproject_position(xf.xform(Vector3(-half_w, half_h, 0.0)))
	var bottom_right: Vector2 = cam.unproject_position(xf.xform(Vector3(half_w, -half_h, 0.0)))
	var render_size: Vector2 = get_viewport().size
	var gui_size: Vector2 = get_viewport_rect().size
	if render_size.x <= 0.0 or render_size.y <= 0.0 or gui_size.x <= 0.0 or gui_size.y <= 0.0:
		return Vector2(-1.0, -1.0)
	var a := Vector2(top_left.x / render_size.x, top_left.y / render_size.y)
	var b := Vector2(bottom_right.x / render_size.x, bottom_right.y / render_size.y)
	var span := b - a
	if abs(span.x) < 0.0001 or abs(span.y) < 0.0001:
		return Vector2(-1.0, -1.0)
	var p := Vector2(point.x / gui_size.x, point.y / gui_size.y)
	var uv := Vector2((p.x - a.x) / span.x, (p.y - a.y) / span.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1.0, -1.0)
	# El signo de U sale del basis real del mesh, no de un flip fijo: asi el puntero real cae
	# donde se ve aunque el presentador cambie de orientacion.
	if _surface_u_flip(mesh, cam):
		uv.x = 1.0 - uv.x
	return uv

# El cursor virtual cruza el terminal en el mismo tiempo que cruza la pantalla: la resolucion
# del Viewport del terminal sobre la del viewport de render.
func _focus_cursor_scale(screen: Object) -> Vector2:
	var design: Vector2 = screen.view_size() if screen != null and screen.has_method("view_size") else Vector2.ZERO
	var root: Vector2 = get_viewport_rect().size
	if design.x <= 0.0 or design.y <= 0.0 or root.x <= 0.0 or root.y <= 0.0:
		return Vector2.ONE
	return design / root

func _mount_focused_screen_if_ready() -> void:
	if not is_instance_valid(_pending_focus_screen):
		return
	if is_instance_valid(_pending_focus_camera) and not _pending_focus_camera.current:
		return
	var screen: Object = _pending_focus_screen
	_pending_focus_screen = null
	_pending_focus_camera = null
	var snapshot: Dictionary = screen.widget_snapshot() if screen.has_method("widget_snapshot") else {}
	_mount.show(screen, snapshot, _view_host, true)
	if is_instance_valid(_mount.get_presenter()):
		_pending_swap_screen = screen
		VisualServer.connect("frame_post_draw", self, "_complete_focus_swap", [], CONNECT_ONESHOT)
		return
	_complete_focus_swap(screen)

func _complete_focus_swap(screen: Object = null) -> void:
	if screen == null:
		screen = _pending_swap_screen
	_pending_swap_screen = null
	if not is_instance_valid(screen):
		return
	_mount.reveal_presenter()
	if screen.has_method("forward_view_input") and is_instance_valid(_virtual_mouse):
		# Doble puntero: la pantalla dibuja SU cursor dentro del Viewport prestado, y el
		# mouse virtual seguia dibujando el suyo. Peor: mas arriba, _input le entrega el
		# InputEventMouseMotion a la pantalla y marca el evento como manejado, asi que el
		# mouse virtual nunca actualizaba su posicion y se quedaba clavado donde lo dejo
		# _release_mouse_for_screen (el centro). Ponerlo invisible no alcanzaba: hay que
		# apagarlo, porque set_desktop_mouse_mode() lo vuelve a mostrar.
		# El mouse virtual sigue VIVO: es el que unifica puntero real y joypad, y su
		# posicion es la que se proyecta sobre la superficie. Lo unico que se decide es
		# cual de los dos cursores se dibuja.
		_virtual_mouse.relative_target_scale = Vector2.ZERO
		_set_focus_cursor_over_surface(_screen_surface_uv(get_viewport().get_mouse_position()).x >= 0.0)
	if screen.has_method("set_source_view_visible"):
		screen.set_source_view_visible(false)
	_view_host.visible = true

func _exit() -> void: # SuitOS saca el overlay y le devuelve la pausa a PauseManager
	if _showing_widget_only():
		_spawn_screen_transition_out() # ghost visual: sobrevive al free del overlay (cuelga de root)
	_end_option_drag()
	_end_drawer_row_drag()
	_cleanup_focus()
	_set_virtual_mouse_enabled(false)
	_suit_os().close_hud_mode()

# --- Gamepad: botones de cara, cruceta y acordes (FD-304 §4/§5/§7) ---

# Los tres flancos de una vez: leerlos por separado en distintas ramas dejaba alguno sin consumir
# y el siguiente tick lo veia como pulsacion nueva.
func _face_edges(input) -> Dictionary:
	var edges := {}
	for button in FACE_FIELDS:
		var down: bool = bool(input.get(FACE_FIELDS[button]))
		edges[button] = down and not _face_was_down[button]
		_face_was_down[button] = down
	return edges


func _drive_hud_buttons(input) -> bool:
	"""Devuelve true si los botones de cara son de la pantalla abierta: en ese caso la ruta GUI
	por foco (_drive_widget_screen) no debe volver a oprimir nada."""
	var edges: Dictionary = _face_edges(input)
	if _selector.is_open():
		# JUMP (b) e INTERACT (x) cierran el dial sin saltar ni interactuar: consume el flanco aca
		# y no se reenvia a gameplay (en el control remoto tampoco llega al host).
		if edges["x"] or edges["b"]:
			_end_crouch_drag()
			_dismiss_radial()
			return false
		# CROUCH (a) es el clic del dial: un tap confirma lo marcado; sostenido y con el stick
		# levanta el item y lo arrastra a un slot (drag/drop con mando, FD-304 §6).
		if edges["a"]:
			_begin_crouch_drag()
		elif _crouch_drag_active and not bool(input.crouch):
			_finish_crouch_drag()
		return false
	_end_crouch_drag()
	return _dispatch_screen_action(edges)


# --- Drag/drop del dial con CROUCH + stick (revision 2026-09-19) ---

func _begin_crouch_drag() -> void:
	var index: int = _selector.get_hovered_index()
	if index == RadialSelectorV2.NONE:
		_selector.confirm() # sin nada marcado el clic no tiene presa: confirma el hub/nada
		return
	_drag_option = index
	_drag_id = _dial_id_at(index)
	if _drag_id.empty():
		_selector.confirm()
		return
	_crouch_drag_active = true
	_crouch_drag_moved = false
	_set_cursor(_selector.option_center(index), get_viewport_rect().size)
	_touch_start = _cursor
	_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC # el click ya es una presa
	_drive_option_drag(_cursor, false, true)


func _finish_crouch_drag() -> void:
	var moved: bool = _crouch_drag_moved
	_crouch_drag_active = false
	_crouch_drag_moved = false
	if moved and is_instance_valid(_drag_ghost):
		_drop_option(_cursor)
	else:
		# Click corto: sin arrastre, confirma lo marcado como siempre.
		_end_option_drag()
		_selector.confirm()


func _end_crouch_drag() -> void:
	if not _crouch_drag_active:
		return
	_crouch_drag_active = false
	_crouch_drag_moved = false
	_end_option_drag()


func _drive_crouch_drag(move: Vector2, input) -> void:
	if bool(input.analog_move_active) or move.length_squared() > MOVE_GESTURE_DEADZONE_SQ:
		_crouch_drag_moved = true
		_move_cursor(move.limit_length(1.0) * STICK_DRAG_SPEED, get_viewport_rect().size)
	_drive_option_drag(_cursor, false)


# FD-304 §4: la pantalla declara que hace cada boton de cara y el overlay lo despacha por la misma
# ruta que su boton tactil, asi que funciona igual en local y en el control remoto. Si no declara
# nada, se cae a la navegacion por foco de la GUI que ya existia.
func _dispatch_screen_action(edges: Dictionary) -> bool:
	if not (_mount.is_showing() or is_instance_valid(_active_focused_screen)):
		return false
	var suit_os: Node = _suit_os()
	var id: String = suit_os.get_active_screen_id()
	var screen: Object = suit_os.get_screen(id)
	if screen == null or not screen.has_method("hud_gamepad_actions"):
		return false
	var actions: Array = screen.hud_gamepad_actions()
	if actions.empty():
		return false
	for action in actions:
		if not bool(edges.get(String(action.get("button", "")).to_lower(), false)):
			continue
		if not bool(action.get("enabled", true)):
			continue
		HudWidgetActionScript.perform(self, id, String(action.get("op", "")), {})
		break
	# Los botones de cara son de esta pantalla aunque este tick no haya coincidido ninguno: si la
	# GUI tambien los oprimiera, el toggle de la linterna se accionaria dos veces en un toque.
	return true


# La cruceta recorre el arco en pasos, con auto-repeat al mismo umbral que el hold.
func _drive_nav(input) -> void:
	var dir: int = int(input.hud_nav)
	var now: int = OS.get_ticks_msec()
	var step: int = 0
	if dir == 0:
		_nav_dir = 0
	elif dir != _nav_dir:
		_nav_dir = dir
		_nav_msec = now
		step = dir
	elif now - _nav_msec >= NAV_REPEAT_MSEC and (now - _nav_msec - NAV_REPEAT_MSEC) % NAV_RATE_MSEC < 20:
		step = dir
	if step == 0:
		return
	if not _selector.is_open():
		# Con una pantalla abierta la cruceta recorre SU lista, si es que tiene una (el roster de
		# las criocapsulas). Sin contrato nuevo: se le pide "select" y las que no lo permiten ni
		# se enteran.
		_step_screen_selection(step)
		return
	if _dial_ids.empty():
		return
	# Arriba en pantalla es avanzar por el arco (el primer sector esta a las 6, el ultimo a las 12).
	# Sin nada marcado, el primer paso entra SIEMPRE por el primer sector, vaya para donde vaya:
	# entrar por el otro extremo segun la direccion se siente como un salto, no como un paso.
	var current: int = _selector.get_hovered_index()
	var next: int = 0
	if current >= 0:
		next = int(clamp(current - step, 0, _dial_ids.size() - 1))
	var angle: float = _selector.option_angle(next)
	_point_at(Vector2(cos(angle), sin(angle)) * AIM_RADIUS)


# --- Arrastre de un widget con el stick (FD-304 §6) ---

func _step_screen_selection(step: int) -> void:
	if not (_mount.is_showing() or is_instance_valid(_active_focused_screen)):
		return
	var suit_os: Node = _suit_os()
	var id: String = suit_os.get_active_screen_id()
	var screen: Object = suit_os.get_screen(id)
	if screen == null or not screen.has_method("allowed_actions") or not ("select" in screen.allowed_actions()):
		return
	HudWidgetActionScript.perform(self, id, "select", {"delta": step})


func _stick_drag_armed() -> bool:
	if not _tab_hold_active or _target_slot < 0 or not _selector.is_open():
		return false
	return _suit_os().has_screen(_suit_os().slot_screen_id(_target_slot))


func _drive_stick_drag(move: Vector2, input) -> void:
	var host = _widget_host()
	if host == null:
		return
	if _drag_id.empty():
		_drag_id = _suit_os().slot_screen_id(_target_slot)
		_drag_option = _dial_ids.find(_drag_id)
		_set_cursor(host.slot_rect(_target_slot).get_center(), get_viewport_rect().size)
		_touch_start = _cursor
		_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC # el hold ya se cumplio al abrir
	if bool(input.analog_move_active) or move.length_squared() > MOVE_GESTURE_DEADZONE_SQ:
		_move_cursor(move.limit_length(1.0) * STICK_DRAG_SPEED, get_viewport_rect().size)
	_drive_option_drag(_cursor, false)


# --- Deny del tap sobre un slot vacio (FD-304 §3) ---

func _deny_slot(slot: int) -> void:
	Haptics.pulse(Haptics.LIFT_MSEC)
	var host = _widget_host()
	if host != null and host.has_method("deny_slot"):
		host.deny_slot(slot)


# --- Relleno del hold y leyenda (FD-304 §3.1 / §9) ---

func _update_hold_feedback() -> void:
	var slot: int = _key_slot if _key_slot_down and not _selector.is_open() else -1
	var progress: float = _slot_gesture.progress() if slot >= 0 else 0.0
	if slot != _hold_slot or abs(progress - _hold_progress) > 0.001:
		_hold_slot = slot
		_hold_progress = progress
		if is_instance_valid(_hold_gauge):
			_hold_gauge.update()


func _draw_hold_gauge() -> void:
	if _hold_slot < 0 or _hold_progress <= 0.0:
		return
	var host = _widget_host()
	if host == null:
		return
	var rect: Rect2 = host.slot_rect(_hold_slot)
	var color := Color(0.0, 0.835, 1.0, 0.9)
	_hold_gauge.draw_rect(rect, Color(color.r, color.g, color.b, 0.15))
	# El marco se llena como una barra proporcional al tiempo; soltar antes lo vacia solo.
	_hold_gauge.draw_rect(Rect2(rect.position, Vector2(rect.size.x * _hold_progress, 3.0)), color)
	_hold_gauge.draw_rect(rect, color, false, 2.0)


# --- Drawer (FD-305 §3.5) ---

# Drawer SIN puntero: el mouse mueve la lista en relativo, como el arma del radial. La fila
# CENTRADA es la elegida y el snap la asienta con easing; el clic acciona esa fila y el derecho
# sale. El dedo si es puntero (arrastra filas a slots y toca la estrella).
func _drawer_pointer_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.device == TOUCH_MOUSE_DEVICE:
			return
		var k: float = UIScaleCompensator.scale_for(_drawer)
		_drawer.scroll_by(event.relative.y / max(k, 0.001))
		return
	if event is InputEventScreenDrag:
		if is_instance_valid(_drag_ghost):
			_drive_option_drag(event.position, false, true)
		elif _drawer_drag_row >= 0 and (event.position - _touch_start).length() >= TOUCH_MIN_DRAG:
			_start_drawer_row_drag(event.position)
		return
	if event is InputEventMouseButton and event.device != TOUCH_MOUSE_DEVICE \
			and (event.button_index == BUTTON_WHEEL_UP or event.button_index == BUTTON_WHEEL_DOWN):
		# La rueda da pasos discretos por la lista, igual que la cruceta. Sin esto no hacia nada.
		if event.pressed:
			_drawer.step_focus(-1 if event.button_index == BUTTON_WHEEL_UP else 1)
		return
	if event is InputEventMouseButton:
		if event.device == TOUCH_MOUSE_DEVICE or not event.pressed:
			return
		if event.button_index == BUTTON_RIGHT:
			_dismiss_drawer()
		elif event.button_index == BUTTON_LEFT:
			var point: Vector2 = event.position
			var star_row: int = _drawer.star_at(point)
			if star_row >= 0:
				_drawer.toggle_favorite_row(star_row, _suit_os())
			else:
				var clicked_row: int = _drawer.row_at(point)
				if clicked_row >= 0:
					_drawer.activate_row(clicked_row)
				else:
					var focused: int = _drawer.focused_index()
					if focused >= 0:
						_drawer.activate_row(focused)
		return
	if event is InputEventScreenTouch:
		var point: Vector2 = event.position
		if event.pressed:
			_drawer_press_row = _drawer.row_at(point)
			_drawer_press_star = _drawer_press_row >= 0 and _drawer.star_at(point) == _drawer_press_row
			_drawer_drag_row = -1 if _drawer_press_star else _drawer_press_row
			_touch_start = point
			return
		if is_instance_valid(_drag_ghost):
			_drop_option(point)
			_end_drawer_row_drag()
			return
		var row: int = _drawer_press_row
		var star: bool = _drawer_press_star
		_end_drawer_row_drag()
		if row < 0:
			# Toque fuera de toda fila: misma salida que B: vuelve al dial o sale del HUD.
			_dismiss_drawer()
			return
		if star:
			_drawer.toggle_favorite_row(row, _suit_os())
		else:
			_drawer.activate_row(row)
		return


func _start_drawer_row_drag(position: Vector2) -> void:
	_drag_id = _drawer.row_id(_drawer_drag_row)
	if _drag_id.empty():
		return
	_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC # el gesto ya empezo en el press
	if _drive_option_drag(position, false, true):
		VirtualMouse.set_dragging(true)


func _end_drawer_row_drag() -> void:
	VirtualMouse.set_dragging(false)
	_drawer_press_row = -1
	_drawer_press_star = false
	_drawer_drag_row = -1
	_drawer_drag_active = false


func _enable_drawer_cursor(position: Vector2) -> void:
	_set_virtual_mouse_enabled(true)
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_desktop_mouse_mode"):
		_virtual_mouse.set_desktop_mouse_mode(true, position)


# El mando no usa el cursor: navega la lista directo (A/X/B + stick) y su hombro arrastra la fila
# enfocada. Cualquier actividad de mando apaga el cursor que el mouse hubiera prendido.
func _drawer_gamepad_active(input) -> bool:
	return bool(input.analog_move_active) or input.move_vec.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
		or int(input.hud_nav) != 0 or int(input.hud_slot) > 0 \
		or bool(input.crouch) or bool(input.jump) or bool(input.interact)


func _drive_drawer_shoulder_drag(input) -> void:
	if not _drawer_drag_active:
		_drag_id = _drawer.focused_screen_id()
		if _drag_id.empty():
			return
		_drawer_drag_active = true
		_set_cursor(_drawer.focused_row_center(), get_viewport_rect().size)
		_touch_start = _cursor
		_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC
	var move := Vector2(input.move_vec.x, input.move_vec.y)
	if move.length_squared() > 0.0:
		_move_cursor(move.limit_length(1.0) * STICK_DRAG_SPEED, get_viewport_rect().size)
	_drive_option_drag(_cursor, false, true)


func _drive_drawer(input, delta: float) -> void:
	var edges: Dictionary = _face_edges(input)
	if not is_instance_valid(_drawer):
		return
	if _drawer_gamepad_active(input):
		_set_virtual_mouse_enabled(false)
	var shoulder: int = int(input.hud_slot) - 1
	if shoulder >= 0:
		_drive_drawer_shoulder_drag(input)
	elif _drawer_drag_active:
		_drop_option(_cursor)
		_drawer_drag_active = false
	else:
		_drawer.drive(-float(input.move_vec.y), int(input.hud_nav), delta)
	if _drawer_drag_active:
		return # arrastrando: A/X/B no accionan la fila
	if edges["a"]:
		_drawer.activate()
	elif edges["x"]:
		_drawer.toggle_favorite(_suit_os())
	elif edges["b"]:
		# B vuelve: al dial si habia uno, o al juego si se entro directo.
		_dismiss_drawer()


func _suit_os() -> Node:
	return backend if is_instance_valid(backend) else get_node_or_null("/root/SuitOS")
