extends HoloTerminalHUDable
class_name CryoPodHUDable

# CryoPodHUDable.gd - La criocapsula como pantalla de OdiseaOS (FD-307).
# Hereda toda la maquinaria de terminal/foco/viewport de HoloTerminalHUDable y agrega
# lo unico propio del pod: la ficha del ocupante y el mando de la escotilla.
#
# La escotilla (RotatingObjectV2) deja de ser un interactuable suelto del mundo: se
# opera desde aca, y por eso se llama set_active() y no interact() (interact() se corta
# solo cuando is_interactable es false, que es justo como queda el nodo en la escena).

const PodWidgetScene = preload("res://core_v2/ui/hud/CryoPodWidget.tscn")
const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")

# Por defecto el padre del terminal: el terminal se monta sobre la escotilla para que la
# pantalla acompañe al vidrio.
export(NodePath) var hatch_path: NodePath = NodePath("..")

# La capsula abierta no necesita su holoterminal: se apaga y deja de ser interactuable
# mientras dure la apertura, y se cierra sola pasado este tiempo (la escotilla abierta no
# tiene otra forma de volver: la terminal que la manda esta apagada).
export(float) var auto_close_delay := 30.0

var _last_hatch_open: bool = false
var _last_hatch_busy: bool = false
var _auto_close_left: float = 0.0

func _ready() -> void:
	._ready()
	# Hidratar la UI del terminal apenas existe: de ahi saca su screen_id, que es por donde
	# despacha el boton ABRIR CÁPSULA. Sin esto el boton quedaba mudo hasta el primer
	# cambio de estado de la escotilla, o sea nunca.
	call_deferred("_push_to_source_ui")

func default_screen_title() -> String:
	return tr("Criocápsula")

# FD-297: abrir la Criocapsula desde el HUD pide la camara de foco del terminal, igual que el
# HangingDisplay. La base delega en terminal.focus(), pero desde afuera _pick_focus_rig()
# devuelve null a proposito (asi la camara del jugador no queda atrapada al operar la escotilla
# en gameplay, FD-307) y entonces no se pide ningun rig: la transicion no ocurre. Aca, si el
# terminal no eligio rig, se pide explicitamente el FocusedRig exterior, el mismo que
# view_transition_origin() devuelve como origen de la transicion. Salir lo libera por el camino
# normal (_exit_focus_mode -> _release_focus_camera_request) con restore_view_on_exit, sin
# duplicar CinematicManager. Solo actua desde el HUD: si el terminal esta enfocado, el rig de
# afuera ya existia y la pantalla se monta como con cualquier HoloTerminal.
func enter_focus_mode() -> void:
	var terminal = _get_terminal()
	if not is_instance_valid(terminal):
		.enter_focus_mode()
		return
	var picked_rig = terminal.call("_pick_focus_rig") if terminal.has_method("_pick_focus_rig") else null
	.enter_focus_mode()
	if is_instance_valid(picked_rig):
		return
	if not (terminal.has_method("is_focused") and terminal.is_focused()):
		return
	var rig = terminal.get_node_or_null("CinematicSetup/FocusedRig")
	if is_instance_valid(rig) and rig.is_inside_tree() and terminal.has_method("_request_focus_camera_rig"):
		terminal.call("_request_focus_camera_rig", rig)

# La capsula se mira desde adentro, contra la pared clara del domo: sin piso de vidrio la
# ficha compite con el mundo que se ve a traves y no se lee.
# HoloScreen: EMISSION = texel * albedo.rgb * emission_energy, o sea la emision es
# proporcional al BRILLO del pixel de la UI, mientras que el ALBEDO sale normalizado por la
# cobertura y da igual para el fondo que para la tinta. Conclusion: lo unico que separa
# tinta de vidrio es la emision. Subirla es el knob de contraste real; el alfa solo pone un
# piso para que no se cuele la pared del domo.
func view_hud_config() -> Dictionary:
	return {
		"background_alpha": 0.95,
		"tint": Color(0.10, 0.16, 0.18),
		"contrast": 8.0,
	}

func widget_scene() -> PackedScene:
	if hud_widget_scene != null:
		return hud_widget_scene
	return PodWidgetScene

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	var hatch := _get_hatch()
	var open_now: bool = is_instance_valid(hatch) and "is_active" in hatch and bool(hatch.is_active)
	var busy_now: bool = _hatch_action_disabled(hatch)
	if open_now != _last_hatch_open:
		_last_hatch_open = open_now
		_last_hatch_busy = busy_now
		# Aca y no en perform_action: la escotilla tambien se abre desde la secuencia de
		# despertar y desde el mundo, y todas esas aperturas deben apagar la terminal.
		_deactivate_terminal_if_open(open_now)
		_auto_close_left = auto_close_delay if open_now else 0.0
		_push_to_source_ui()
		notify_state_changed()
	elif busy_now != _last_hatch_busy:
		_last_hatch_busy = busy_now
		_push_to_source_ui()
		notify_state_changed()
	elif open_now and _auto_close_left > 0.0:
		_auto_close_left -= delta
		if _auto_close_left <= 0.0 and is_instance_valid(hatch) and hatch.has_method("set_active"):
			hatch.set_active(false)


func _deactivate_terminal_if_open(hatch_open: bool) -> void:
	if not hatch_open:
		return
	var terminal = _get_terminal()
	if not is_instance_valid(terminal):
		return
	# La pantalla se apaga con el vidrio abierto, pero la capsula sigue registrada como
	# interactuable/HUDable. Su accion informa indisponibilidad hasta terminar el cierre.
	if terminal.has_method("set_active"):
		terminal.set_active(false)

func _hatch_action_disabled(hatch) -> bool:
	if not is_instance_valid(hatch) or not ("is_active" in hatch):
		return true
	var moving: bool = "anim_progress" in hatch and "target_progress" in hatch \
		and abs(float(hatch.anim_progress) - float(hatch.target_progress)) > 0.001
	return bool(hatch.is_active) or moving

func widget_snapshot() -> Dictionary:
	var snap: Dictionary = .widget_snapshot()
	var hatch := _get_hatch()
	snap["hatch_open"] = is_instance_valid(hatch) and "is_active" in hatch and bool(hatch.is_active)
	snap["hatch_busy"] = _hatch_action_disabled(hatch)
	var ui := _get_pod_ui()
	if is_instance_valid(ui) and ui.has_method("pod_state"):
		for key in ui.pod_state():
			snap[key] = ui.pod_state()[key]
	return snap

func allowed_actions() -> Array:
	var actions: Array = .allowed_actions()
	if not actions.has("toggle_hatch"):
		actions.append("toggle_hatch")
	return actions

# FD-304 §4: la accion primaria de la capsula es abrir/cerrar, no enfocar. "confirm" la
# marca para el acorde hombro + boton, que la ejecuta sin abrir la pantalla.
func hud_gamepad_actions() -> Array:
	var hatch := _get_hatch()
	var open: bool = bool(hatch.is_active) if is_instance_valid(hatch) and "is_active" in hatch else false
	return [{
		"button": "a",
		"op": "toggle_hatch",
		"label": tr("CERRAR") if open else tr("ABRIR"),
		"icon": "hatch",
		"enabled": is_instance_valid(hatch) and not _hatch_action_disabled(hatch),
		"confirm": true,
	}]

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op != "toggle_hatch":
		return .perform_action(op, args)
	var hatch := _get_hatch()
	if not is_instance_valid(hatch) or not hatch.has_method("set_active"):
		return {"ok": false, "error": "Sin escotilla"}
	if _hatch_action_disabled(hatch):
		return {"ok": false, "error": "Escotilla no disponible"}
	hatch.set_active(not bool(hatch.is_active))
	# La pantalla puede estar enfocada mientras el HUD pausa el mundo; apagarla aqui
	# evita dejar camara/input atrapados, sin retirar la capsula de interaccion.
	_deactivate_terminal_if_open(bool(hatch.is_active))
	_push_to_source_ui()
	notify_state_changed()
	# La capsula abierta ya no necesita la holoterminal: se desactiva sola en vez de quedar la
	# pantalla encendida sobre la escotilla abierta. Diferido para no cerrar el HUD en medio del
	# mismo gesto que lo esta usando.
	if bool(hatch.is_active):
		call_deferred("_close_hud_and_capture_mouse")
	return {"ok": true, "hatch_open": bool(hatch.is_active)}

func _close_hud_and_capture_mouse() -> void:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_method("close_hud_mode"):
		suit_os.close_hud_mode()
	# El overlay se libera al final del frame y restaura su modo anterior; capturar en el
	# siguiente evita que esa limpieza vuelva a dejar el puntero oculto pero libre.
	if not get_tree().is_connected("idle_frame", self, "_capture_gameplay_mouse"):
		get_tree().connect("idle_frame", self, "_capture_gameplay_mouse", [], CONNECT_ONESHOT)

func _capture_gameplay_mouse() -> void:
	VirtualMouse.set_pointer_released(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# La UI que vive en el Viewport del terminal es la misma que ve el jugador en el mundo y
# en el modo foco (viewport prestado): hay que avisarle a mano, porque el HudViewMount
# solo hidrata las copias que instancia el (el control remoto).
func _push_to_source_ui() -> void:
	var ui := _get_pod_ui()
	if is_instance_valid(ui) and ui.has_method("update_snapshot"):
		ui.update_snapshot(widget_snapshot())

func _get_pod_ui() -> Node:
	var terminal = _get_terminal()
	var viewport = terminal.get_node_or_null("Viewport") if is_instance_valid(terminal) else null
	if viewport == null:
		return null
	for child in viewport.get_children():
		if child is Control and not child.is_queued_for_deletion() and child.has_method("pod_state"):
			return child
	return null

func _get_hatch() -> Node:
	var terminal = _get_terminal()
	if not is_instance_valid(terminal):
		return null
	return terminal.get_node_or_null(hatch_path)
