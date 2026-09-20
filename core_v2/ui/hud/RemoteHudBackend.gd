extends Node

# RemoteHudBackend.gd - El HUD del telefono (control remoto) con los mismos nodos que el del juego.
#
# SuitOSWidgetHost y HudModeOverlay no hablan con SuitOS sino con un backend que
# cumple su contrato: senales widget_changed/screen_registered/screen_unregistered/screen_opened/
# screen_closed/hud_mode_changed; slots (get_slot_snapshot, get_pinned_slots, slot_screen_id,
# pin_to_slot, move_slot, clear_slot, clear_slots); pantallas (get_registered_screens, has_screen,
# get_screen -> objeto con screen_title/widget_scene/view_scene/view_size/widget_snapshot/
# hud_gamepad_actions y la senal state_changed); modo HUD (is_hud_mode_active, get_active_screen_id, open_hud_mode,
# close_hud_mode, open_screen) y perform_action. En el juego ese backend es SuitOS; aca, esto.
#
# Las pantallas viven en el host y llegan por el canal (screen_list, screen_data, screen_active).
# Los 4 slots son del telefono: al conectar copian los del host (ui op "slots") y desde ahi son
# independientes (decision de FD-296). Antes de esa copia, la linterna en el 1. Mismas reglas que
# SuitOS (HudSlots): nada se autoasigna y una pantalla nunca ocupa dos slots.

signal widget_changed(slot, snapshot)
signal screen_registered(id)
signal screen_unregistered(id)
signal screen_opened(id)
signal screen_closed(id)
signal hud_mode_changed(active)

const HudSlots = preload("res://core_v2/ui/hud/HudSlots.gd")
const HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
const HudModeOverlayScene = preload("res://core_v2/ui/hud/HudModeOverlay.tscn")
const DEFAULT_PINS := ["player:flashlight", "", "", ""]
# Distancia de camara de referencia para la regla del zoom: el telefono no tiene jugador, asi que
# acumula el pellizco que manda al host (mas chico = mas cerca, como la del jugador).
const ZOOM_START := 4.0

# RemoteControlHome: el canal, el dial y el estado de pausa del host.
var home: Node = null
var screen_list: Array = []
var snapshots: Dictionary = {}
var active_screen: Dictionary = {}
var zoom_level := ZOOM_START
# El control no tiene mundo ni camara: la vista de una pantalla va en un Viewport 2D (HudViewMount).
var presents_views_in_2d := true

var _pinned: Array = DEFAULT_PINS.duplicate()
var _slot_snapshots: Dictionary = {"slot_1": {}, "slot_2": {}, "slot_3": {}, "slot_4": {}}
var _proxies: Dictionary = {}
# El modo HUD del telefono: el mismo HudModeOverlay del juego, sin pausa.
var _overlay: Control = null
# La pantalla elegida aca. La del host (active_screen) llega despues, con su vista y su tamaño.
var _selected_id := ""
# Los slots del host se copian una sola vez: si el canal se corta y retoma, lo que se acomodo en el
# telefono se queda.
var _adopted_host_pins := false


# Lo que el HUD compartido le pide a una pantalla, armado con lo que mando el host.
class RemoteScreenProxy extends Reference:
	signal state_changed()
	var id := ""
	var backend = null

	func screen_id() -> String:
		return id

	func screen_title() -> String:
		var title: String = backend.screen_field(id, "title")
		return title if not title.empty() else id

	func widget_scene() -> PackedScene:
		return backend.resolve_widget_scene(id)

	func view_scene() -> PackedScene:
		return backend.resolve_view_scene(id)

	func view_size() -> Vector2:
		return backend.active_view_size() if String(backend.active_screen.get("id", "")) == id else Vector2.ZERO

	func widget_snapshot() -> Dictionary:
		return backend.snapshot_for(id)

	# FD-304 §4/§5: las acciones de los botones de cara viajan desde el host. Sin esto el control
	# no sabria que hace el tap de un hombro y caeria siempre a abrir la pantalla.
	func hud_gamepad_actions() -> Array:
		return backend.screen_gamepad_actions(id)


func _ready() -> void:
	reevaluate_slots()

# --- Lo que llega del host ---

func apply_screen_list(list: Array) -> void:
	var before: Array = get_registered_screens()
	screen_list = list.duplicate(true)
	# La lista trae el snapshot de cada pantalla: es lo que hace que el widget muestre su nombre y
	# su estado reales y no el id.
	for item in screen_list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var sid: String = String(item.get("id", ""))
		var snap = item.get("snapshot")
		if not sid.empty() and typeof(snap) == TYPE_DICTIONARY:
			snapshots[sid] = (snap as Dictionary).duplicate(true)
	var after: Array = get_registered_screens()
	if is_hud_mode_active() and after != before:
		_overlay._screen_ids = after
		_overlay._placeholder.visible = after.empty()
	reevaluate_slots()
	for sid in after:
		if not before.has(sid):
			emit_signal("screen_registered", sid)
		_notify_proxy(sid)
	for sid in before:
		if not after.has(sid):
			emit_signal("screen_unregistered", sid)

func apply_screen_data(sid: String, snap: Dictionary) -> void:
	if sid.empty():
		return
	snapshots[sid] = snap.duplicate(true)
	if sid == String(active_screen.get("id", "")):
		active_screen["snapshot"] = snap.duplicate(true)
	reevaluate_slots()
	_notify_proxy(sid)

func apply_screen_active(payload: Dictionary) -> void:
	var previous: String = String(active_screen.get("id", ""))
	active_screen = payload.duplicate(true)
	var current: String = String(active_screen.get("id", ""))
	var snapshot = active_screen.get("snapshot")
	if not current.empty() and typeof(snapshot) == TYPE_DICTIONARY:
		snapshots[current] = (snapshot as Dictionary).duplicate(true)
		_notify_proxy(current)
	if previous == current:
		return
	# El host cerro la pantalla que se estaba viendo aca (se fue de la escena): el modo HUD tambien.
	if current.empty() and not _selected_id.empty() and previous == _selected_id:
		close_hud_mode()
		return
	# Elegida aca y confirmada alla: con la vista del host (ruta y tamaño) ya se puede armar su
	# Viewport en lugar del widget ampliado.
	if is_hud_mode_active() and current == _selected_id and not _overlay._selector.is_open() \
			and resolve_view_scene(current) != null:
		_overlay.show_screen_id(current)

func add_zoom(delta: float) -> void:
	zoom_level = clamp(zoom_level + delta, 0.5, 50.0)

func zoom_metric() -> float:
	return zoom_level

# --- Slots ---

func get_slot_snapshot(slot: String) -> Dictionary:
	return _slot_snapshots.get(slot, {}).duplicate(true)

func get_pinned_slots() -> Array:
	return _pinned.duplicate()

func slot_screen_id(index: int) -> String:
	if index < 0 or index >= HudSlots.COUNT:
		return ""
	return String(_pinned[index])

func pin_to_slot(index: int, id: String) -> void:
	_pinned = HudSlots.pin_to(_pinned, index, id)
	reevaluate_slots()

func move_slot(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= HudSlots.COUNT or to >= HudSlots.COUNT:
		return
	var moving: String = String(_pinned[from])
	if moving.empty():
		return
	var displaced: String = String(_pinned[to])
	_pinned[to] = moving
	_pinned[from] = displaced
	reevaluate_slots()

func clear_slot(index: int) -> void:
	if index < 0 or index >= HudSlots.COUNT:
		return
	_pinned[index] = ""
	reevaluate_slots()

func clear_slots() -> void:
	_pinned = HudSlots.empty_pins()
	reevaluate_slots()

func reevaluate_slots() -> void:
	for i in range(HudSlots.COUNT):
		var id: String = String(_pinned[i])
		var new_snap: Dictionary = {} if id.empty() else snapshot_for(id)
		var key: String = HudSlots.slot_key(i)
		# hash(): != entre Dictionaries compara referencias en Godot 3 (ver SuitOS.reevaluate_slots).
		if new_snap.hash() != _slot_snapshots.get(key, {}).hash():
			_slot_snapshots[key] = new_snap.duplicate(true)
			emit_signal("widget_changed", key, _slot_snapshots[key])

# El snapshot de una pantalla: el ultimo que mando el host, con id, titulo y si esta en la partida.
func snapshot_for(id: String) -> Dictionary:
	var snap: Dictionary = snapshots.get(id, {}).duplicate(true)
	if not snap.has("proto"):
		snap["proto"] = 1
	snap["id"] = id
	if not snap.has("title"):
		var title: String = screen_field(id, "title")
		snap["title"] = title if not title.empty() else id
	snap["source"] = "online" if has_screen(id) else "offline"
	return snap

# --- Pantallas ---

func get_registered_screens() -> Array:
	var ids: Array = []
	for item in screen_list:
		if typeof(item) == TYPE_DICTIONARY and not String(item.get("id", "")).empty():
			ids.append(String(item["id"]))
	return ids

func has_screen(id: String) -> bool:
	return not id.empty() and get_registered_screens().has(id)

func get_screen(id: String) -> Object:
	if not has_screen(id):
		return null
	if not _proxies.has(id):
		var proxy := RemoteScreenProxy.new()
		proxy.id = id
		proxy.backend = self
		_proxies[id] = proxy
	return _proxies[id]

func screen_field(screen_id: String, key: String) -> String:
	for item in screen_list:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("id", "")) == screen_id:
			return String(item.get(key, ""))
	return ""

# Las acciones de botones de cara que declara la pantalla en el host (vacio = ninguna).
func screen_gamepad_actions(screen_id: String) -> Array:
	for item in screen_list:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("id", "")) == screen_id:
			var actions = item.get("gamepad_actions")
			if typeof(actions) == TYPE_ARRAY:
				return (actions as Array).duplicate(true)
	return []

# El host de widgets montado en este dispositivo (lo usa HudSlotGamepadV2 para el feedback del hold).
func get_widget_host() -> Node:
	return home.widget_host if home != null and "widget_host" in home else null

# La escena del widget: la del SuitOS local si la pantalla existe aca (no pasa en un telefono), la
# ruta que mando el host, o la de las terminales holograficas.
func resolve_widget_scene(screen_id: String) -> PackedScene:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(screen_id):
		var screen = suit_os.get_screen(screen_id)
		if is_instance_valid(screen) and screen.has_method("widget_scene"):
			var scene = screen.widget_scene()
			if scene != null:
				return scene
	var widget_path: String = screen_field(screen_id, "widget")
	if not widget_path.empty() and ResourceLoader.exists(widget_path):
		var remote_scene = load(widget_path)
		if remote_scene is PackedScene:
			return remote_scene
	if screen_id.begins_with("holoterminal:"):
		return HoloTerminalWidgetScene
	return null

# La vista completa llega como ruta, solo para la pantalla activa. Sin escena (la que presta su
# Viewport en vivo en el host) no se puede replicar aca y queda el widget.
func resolve_view_scene(screen_id: String) -> PackedScene:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(screen_id):
		var screen = suit_os.get_screen(screen_id)
		if is_instance_valid(screen) and screen.has_method("view_scene"):
			var scene = screen.view_scene()
			if scene != null:
				return scene
	if String(active_screen.get("id", "")) == screen_id:
		var view_path: String = String(active_screen.get("view_scene", ""))
		if not view_path.empty() and ResourceLoader.exists(view_path):
			var remote_view = load(view_path)
			if remote_view is PackedScene:
				return remote_view
	return null

func active_view_size() -> Vector2:
	var size = active_screen.get("view_size")
	if typeof(size) == TYPE_ARRAY and (size as Array).size() >= 2:
		return Vector2(float(size[0]), float(size[1]))
	return Vector2.ZERO

# --- Modo HUD (el dial y la vista son del telefono; la eleccion viaja al host) ---

func is_hud_mode_active() -> bool:
	return is_instance_valid(_overlay) and not _overlay.is_queued_for_deletion()

# El dial del modo HUD a la vista (con teclado y mouse se queda con la entrada).
func is_dial_open() -> bool:
	return is_hud_mode_active() and _overlay._selector.is_open()

func get_overlay() -> Control:
	return _overlay if is_hud_mode_active() else null

func get_active_screen_id() -> String:
	return _selected_id

# Como SuitOS.open_hud_mode, pero el overlay va en la pantalla del control y el mundo no se pausa.
func open_hud_mode(radial: bool = false, screen_id: String = "", slot: int = -1) -> bool:
	if is_hud_mode_active():
		if not radial and has_screen(screen_id):
			_overlay.show_screen_id(screen_id)
			return true
		return false
	if home == null or not is_instance_valid(home):
		return false
	_overlay = HudModeOverlayScene.instance()
	_overlay.backend = self
	_overlay.use_virtual_mouse = false
	_overlay.drives_dial_with_gameplay_input = home.get("_raw_passthrough") == true
	home.mount_hud_overlay(_overlay)
	emit_signal("hud_mode_changed", true)
	if radial:
		_overlay.show_radial(slot)
	elif has_screen(screen_id):
		_overlay.show_screen_id(screen_id)
	elif slot >= 0:
		_overlay.show_for_slot(slot)
	return true

func close_hud_mode() -> void:
	if not is_hud_mode_active():
		return
	_overlay.queue_free()
	_overlay = null
	if not _selected_id.empty():
		var closed: String = _selected_id
		_selected_id = ""
		if home != null and is_instance_valid(home):
			home.select_remote_screen("")
		emit_signal("screen_closed", closed)
	emit_signal("hud_mode_changed", false)

func open_screen(id: String) -> bool:
	if home == null or not is_instance_valid(home) or not has_screen(id):
		return false
	if id != _selected_id:
		_selected_id = id
		home.select_remote_screen(id)
		emit_signal("screen_opened", id)
	return true

func perform_action(screen_id: String, op: String, args: Dictionary = {}) -> Dictionary:
	if home == null or not is_instance_valid(home):
		return {"ok": false, "error": "sin control remoto"}
	home.send_remote_action(screen_id, op, args)
	return {"ok": true}

func adopt_host_pins(pins: Array) -> void:
	if _adopted_host_pins:
		return
	_adopted_host_pins = true
	var copied: Array = HudSlots.empty_pins()
	for i in range(min(pins.size(), HudSlots.COUNT)):
		copied[i] = String(pins[i]) if pins[i] != null else ""
	_pinned = copied
	reevaluate_slots()

func _notify_proxy(sid: String) -> void:
	if _proxies.has(sid):
		_proxies[sid].emit_signal("state_changed")
