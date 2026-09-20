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

# Por defecto el padre del terminal: el terminal se monta sobre la escotilla para que la
# pantalla acompañe al vidrio.
export(NodePath) var hatch_path: NodePath = NodePath("..")

var _last_hatch_open: bool = false

func _ready() -> void:
	._ready()
	# Hidratar la UI del terminal apenas existe: de ahi saca su screen_id, que es por donde
	# despacha el boton ABRIR CÁPSULA. Sin esto el boton quedaba mudo hasta el primer
	# cambio de estado de la escotilla, o sea nunca.
	call_deferred("_push_to_source_ui")

func default_screen_title() -> String:
	return tr("Criocápsula")

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
	var open_now: bool = bool(hatch.is_active) if is_instance_valid(hatch) else false
	if open_now != _last_hatch_open:
		_last_hatch_open = open_now
		_push_to_source_ui()
		notify_state_changed()

func widget_snapshot() -> Dictionary:
	var snap: Dictionary = .widget_snapshot()
	var hatch := _get_hatch()
	snap["hatch_open"] = bool(hatch.is_active) if is_instance_valid(hatch) else false
	snap["hatch_busy"] = false
	if is_instance_valid(hatch) and "anim_progress" in hatch and "target_progress" in hatch:
		snap["hatch_busy"] = abs(float(hatch.anim_progress) - float(hatch.target_progress)) > 0.001
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
	var open: bool = bool(hatch.is_active) if is_instance_valid(hatch) else false
	return [{
		"button": "a",
		"op": "toggle_hatch",
		"label": tr("CERRAR") if open else tr("ABRIR"),
		"icon": "hatch",
		"enabled": is_instance_valid(hatch),
		"confirm": true,
	}]

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op != "toggle_hatch":
		return .perform_action(op, args)
	var hatch := _get_hatch()
	if not is_instance_valid(hatch) or not hatch.has_method("set_active"):
		return {"ok": false, "error": "Sin escotilla"}
	hatch.set_active(not bool(hatch.is_active))
	_push_to_source_ui()
	notify_state_changed()
	# La capsula abierta ya no necesita la holoterminal: se desactiva sola en vez de quedar la
	# pantalla encendida sobre la escotilla abierta. Diferido para no cerrar el HUD en medio del
	# mismo gesto que lo esta usando.
	if bool(hatch.is_active):
		var suit_os = get_node_or_null("/root/SuitOS")
		if suit_os != null and suit_os.has_method("close_hud_mode"):
			suit_os.call_deferred("close_hud_mode")
	return {"ok": true, "hatch_open": bool(hatch.is_active)}

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
