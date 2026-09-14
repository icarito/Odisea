extends Node

# RemoteHudBackend.gd - El HUD del telefono (control remoto) con los mismos nodos que el del juego.
#
# SuitOSWidgetHost (y, en la etapa 2, HudModeOverlay) no hablan con SuitOS sino con un backend que
# cumple su contrato: senales widget_changed/screen_registered/screen_unregistered/screen_opened/
# screen_closed/hud_mode_changed; slots (get_slot_snapshot, get_pinned_slots, slot_screen_id,
# pin_to_slot, move_slot, clear_slot, clear_slots); pantallas (get_registered_screens, has_screen,
# get_screen -> objeto con screen_title/widget_scene/view_scene/view_size/widget_snapshot y la
# senal state_changed); modo HUD (is_hud_mode_active, get_active_screen_id, open_hud_mode,
# close_hud_mode, open_screen) y perform_action. En el juego ese backend es SuitOS; aca, esto.
#
# Las pantallas viven en el host y llegan por el canal (screen_list, screen_data, screen_active).
# Los 4 slots son del telefono: independientes de los del host (decision de FD-296), con la
# linterna en el 1 por defecto y guardados en user://. Mismas reglas que SuitOS (HudSlots): nada
# se autoasigna y una pantalla nunca ocupa dos slots.

signal widget_changed(slot, snapshot)
signal screen_registered(id)
signal screen_unregistered(id)
signal screen_opened(id)
signal screen_closed(id)
signal hud_mode_changed(active)

const HudSlots = preload("res://core_v2/ui/hud/HudSlots.gd")
const HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
const DEFAULT_PINS := ["player:flashlight", "", "", ""]
# Distancia de camara de referencia para la regla del zoom: el telefono no tiene jugador, asi que
# acumula el pellizco que manda al host (mas chico = mas cerca, como la del jugador).
const ZOOM_START := 4.0

# ponytail: fuera del editor nada mas, asi los tests (que instancian el control a cada rato) no
# heredan ni ensucian los slots guardados; en un build exportado (el telefono) siempre guarda.
# Si hace falta probar la persistencia desde el editor, poner persist y pins_path a mano.
var persist: bool = not OS.has_feature("editor")
var pins_path := "user://remote_hud.cfg"

# RemoteControlHome: el canal, el dial y el estado de pausa del host.
var home: Node = null
var screen_list: Array = []
var snapshots: Dictionary = {}
var active_screen: Dictionary = {}
var zoom_level := ZOOM_START

var _pinned: Array = DEFAULT_PINS.duplicate()
var _slot_snapshots: Dictionary = {"slot_1": {}, "slot_2": {}, "slot_3": {}, "slot_4": {}}
var _proxies: Dictionary = {}


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
		return backend.active_view_size() if backend.get_active_screen_id() == id else Vector2.ZERO

	func widget_snapshot() -> Dictionary:
		return backend.snapshot_for(id)


func _ready() -> void:
	if persist:
		_load_pins()
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
	if sid == get_active_screen_id():
		active_screen["snapshot"] = snap.duplicate(true)
	reevaluate_slots()
	_notify_proxy(sid)

func apply_screen_active(payload: Dictionary) -> void:
	var previous: String = get_active_screen_id()
	active_screen = payload.duplicate(true)
	var current: String = get_active_screen_id()
	if previous == current:
		return
	if not previous.empty():
		emit_signal("screen_closed", previous)
	if not current.empty():
		emit_signal("screen_opened", current)

# El dial del telefono se abrio o se cerro (RemoteControlHome): los widgets y contornos se enteran.
func notify_hud_state() -> void:
	emit_signal("hud_mode_changed", is_hud_mode_active())

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
	_slots_changed()

func move_slot(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= HudSlots.COUNT or to >= HudSlots.COUNT:
		return
	var moving: String = String(_pinned[from])
	if moving.empty():
		return
	var displaced: String = String(_pinned[to])
	_pinned[to] = moving
	_pinned[from] = displaced
	_slots_changed()

func clear_slot(index: int) -> void:
	if index < 0 or index >= HudSlots.COUNT:
		return
	_pinned[index] = ""
	_slots_changed()

func clear_slots() -> void:
	_pinned = HudSlots.empty_pins()
	_slots_changed()

func reevaluate_slots() -> void:
	for i in range(HudSlots.COUNT):
		var id: String = String(_pinned[i])
		var new_snap: Dictionary = {} if id.empty() else snapshot_for(id)
		var key: String = HudSlots.slot_key(i)
		if new_snap != _slot_snapshots.get(key, {}):
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
	if get_active_screen_id() == screen_id:
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
	return home != null and is_instance_valid(home) and home.has_method("_hud_mode_active") \
		and home._hud_mode_active()

func get_active_screen_id() -> String:
	return String(active_screen.get("id", ""))

func open_hud_mode(radial: bool = false, screen_id: String = "", slot: int = -1) -> bool:
	if home == null or not is_instance_valid(home):
		return false
	return home.open_hud_from_backend(radial, screen_id, slot)

func close_hud_mode() -> void:
	if home != null and is_instance_valid(home):
		home._exit_hud_mode()

func open_screen(id: String) -> bool:
	if home == null or not is_instance_valid(home) or not has_screen(id):
		return false
	home.select_remote_screen(id)
	return true

func perform_action(screen_id: String, op: String, args: Dictionary = {}) -> Dictionary:
	if home == null or not is_instance_valid(home):
		return {"ok": false, "error": "sin control remoto"}
	home.send_remote_action(screen_id, op, args)
	return {"ok": true}

# --- Persistencia de los slots del telefono ---

func _slots_changed() -> void:
	reevaluate_slots()
	if persist:
		_save_pins()

func _notify_proxy(sid: String) -> void:
	if _proxies.has(sid):
		_proxies[sid].emit_signal("state_changed")

func _load_pins() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(pins_path) != OK:
		return
	var saved = cfg.get_value("slots", "pinned", null)
	if typeof(saved) != TYPE_ARRAY:
		return
	_pinned = HudSlots.empty_pins()
	for i in range(min((saved as Array).size(), HudSlots.COUNT)):
		_pinned[i] = String(saved[i]) if saved[i] != null else ""

func _save_pins() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("slots", "pinned", _pinned)
	cfg.save(pins_path)
