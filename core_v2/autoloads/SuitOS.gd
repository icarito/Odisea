extends Node

# SuitOS.gd - Core suit operating system autoload for OdiseaOS (FD-296)
# Manages screen module registration, slot scoring (Slot A = auto), pinned screen selection (Slot B),
# F1 data contract actions, haptic bus, and persistence state.
#
# Ownership & Architecture Notes:
# - Pause & Android Back: Owned strictly by PauseManager. SuitOS NEVER sets get_tree().paused directly.
# - Presentation: Widget layout/presentation is delegated to OverlayUIManager (slot 'HUD').
# - Scene Cut: Listens to SceneManager 'pre_scene_swap' signal to close active screens and clear
#   relevance context on scene transitions. Registered screens auto-unregister via _exit_tree().
#
# Slot A never duplicates Slot B: the pinned screen is excluded from Slot A scoring.
#
# Slot A relevance threshold:
# min_relevance_a (default 0.0, const MIN_RELEVANCE_A = 0.0) defines the minimum relevance score required
# for a screen to occupy Slot A. If all registered screens have relevance <= min_relevance_a,
# Slot A remains empty ({}) and widget_changed("slot_a", {}) is emitted.

signal screen_registered(id)
signal screen_unregistered(id)
signal screen_opened(id)
signal screen_closed(id)
signal widget_changed(slot, snapshot)
signal hud_mode_changed(active)
signal haptic(kind, intensity)

const MIN_RELEVANCE_A: float = 0.0

const ContextDriverScript = preload("res://core_v2/autoloads/SuitOSContextDriver.gd")
const WidgetHostScene = preload("res://core_v2/ui/hud/SuitOSWidgetHost.tscn")
const HudModeOverlayScene = preload("res://core_v2/ui/hud/HudModeOverlay.tscn")
const HUD_MODE_OVERLAY := "HudModeOverlay"

export(float) var min_relevance_a: float = MIN_RELEVANCE_A

var _screens: Dictionary = {} # Maps String (screen_id) -> Object
var _context: Dictionary = {}
var _hud_mode_active: bool = false
var _active_screen_id: String = ""
var _pinned_screen_id: String = ""
var _slot_snapshots: Dictionary = {"slot_a": {}, "slot_b": {}}
var _last_snapshots_cache: Dictionary = {}

var _context_driver: Node = null
var _widget_host: Node = null

func _ready() -> void:
	add_to_group("replay_sync")
	_ensure_runtime_subsystems()

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and not scene_manager.is_connected("pre_scene_swap", self, "_on_pre_scene_swap"):
		scene_manager.connect("pre_scene_swap", self, "_on_pre_scene_swap")

	# Persistence: SuitOS participates in the 'replay_sync' contract (add_to_group("replay_sync") above).
	# CheckpointManager.capture_replay_sync_state() collects get_snapshot() from every node in that group and
	# restore_replay_sync_state() calls restore_snapshot() back; TeleportSystem stores that snapshot inside
	# CheckpointResource.slots["last"]. No PersistenceManager registration API is required: the pinned screen
	# and widget snapshots travel with the existing save/replay checkpoint, so CONTINUE and replay stay in sync.

func _ensure_runtime_subsystems() -> void:
	if not is_instance_valid(_context_driver):
		_context_driver = get_node_or_null("SuitOSContextDriver")
		if _context_driver == null:
			_context_driver = ContextDriverScript.new()
			_context_driver.name = "SuitOSContextDriver"
			add_child(_context_driver)

	if not is_instance_valid(_widget_host):
		_widget_host = get_node_or_null("SuitOSWidgetHost")
		if _widget_host == null and WidgetHostScene != null:
			_widget_host = WidgetHostScene.instance()
			_widget_host.name = "SuitOSWidgetHost"
			add_child(_widget_host)

func register_screen(screen: Object) -> void:
	if screen == null:
		return
	var id: String = _extract_screen_id(screen)
	if id.empty():
		return

	if _screens.has(id):
		var old_screen = _screens[id]
		if is_instance_valid(old_screen) and old_screen.has_signal("state_changed"):
			if old_screen.is_connected("state_changed", self, "_on_screen_state_changed"):
				old_screen.disconnect("state_changed", self, "_on_screen_state_changed")

	_screens[id] = screen

	if screen.has_signal("state_changed"):
		if not screen.is_connected("state_changed", self, "_on_screen_state_changed"):
			screen.connect("state_changed", self, "_on_screen_state_changed", [id])

	emit_signal("screen_registered", id)

	_update_screen_snapshot_cache(id)
	reevaluate_slots()

func unregister_screen(screen_or_id) -> void:
	var id: String = ""
	if typeof(screen_or_id) == TYPE_STRING:
		id = screen_or_id
	elif typeof(screen_or_id) == TYPE_OBJECT and is_instance_valid(screen_or_id):
		id = _extract_screen_id(screen_or_id)

	if id.empty() or not _screens.has(id):
		return

	var screen = _screens[id]
	if is_instance_valid(screen) and screen.has_signal("state_changed"):
		if screen.is_connected("state_changed", self, "_on_screen_state_changed"):
			screen.disconnect("state_changed", self, "_on_screen_state_changed")

	_screens.erase(id)
	emit_signal("screen_unregistered", id)

	reevaluate_slots()

func has_screen(id: String) -> bool:
	return _screens.has(id) and is_instance_valid(_screens[id])

func get_screen(id: String) -> Object:
	if has_screen(id):
		return _screens[id]
	return null

func get_registered_screens() -> Array:
	var result: Array = []
	for id in _screens.keys():
		if is_instance_valid(_screens[id]):
			result.append(id)
	return result

func set_hud_mode_active(active: bool) -> void:
	if _hud_mode_active != active:
		_hud_mode_active = active
		emit_signal("hud_mode_changed", _hud_mode_active)

func is_hud_mode_active() -> bool:
	return _hud_mode_active

# FD-296 F3 — modo HUD local. Vive aca porque SuitOS ya es el dueño de hud_mode_changed y
# del estado del modo; la pausa se le pide a PauseManager y la presentacion a
# OverlayUIManager (SLOT_MODAL), asi que no nace un segundo sistema de ninguna de las dos.
# SuitOS hereda la pausa: este _input solo corre con el mundo andando (con el menu de
# pausa abierto TAB no hace nada). El cierre lo dispara el overlay, que procesa en pausa.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("hud_mode") and open_hud_mode():
		get_tree().set_input_as_handled()

# radial / screen_id: abrir directo en el selector o en una pantalla (hold y tap sobre el
# widget del slot, que no pasan por el stream). Con TAB el overlay decide tap/hold solo,
# contando muestras del stream.
func open_hud_mode(radial: bool = false, screen_id: String = "") -> bool:
	var pause_mgr = get_node_or_null("/root/PauseManager")
	var overlay_mgr = get_node_or_null("/root/OverlayUIManager")
	if _hud_mode_active or pause_mgr == null or overlay_mgr == null:
		return false
	if not pause_mgr.pause_hud_mode():
		return false
	# null = el overlay anterior sigue en queue_free (TAB repetido en un mismo frame).
	# Nunca dejar el mundo pausado sin UI que lo despause.
	var overlay: Node = overlay_mgr.ensure_overlay(HUD_MODE_OVERLAY, HudModeOverlayScene, overlay_mgr.SLOT_MODAL)
	if overlay == null:
		pause_mgr.resume_hud_mode()
		return false
	set_hud_mode_active(true)
	if radial:
		overlay.show_radial()
	elif has_screen(screen_id):
		overlay.show_screen_id(screen_id)
	return true

func close_hud_mode() -> void:
	if not _hud_mode_active:
		return
	var overlay_mgr = get_node_or_null("/root/OverlayUIManager")
	if overlay_mgr != null:
		overlay_mgr.remove_overlay(HUD_MODE_OVERLAY, overlay_mgr.SLOT_MODAL)
	close_screen()
	var pause_mgr = get_node_or_null("/root/PauseManager")
	if pause_mgr != null:
		pause_mgr.resume_hud_mode()
	set_hud_mode_active(false)

func open_screen(id: String) -> bool:
	if not has_screen(id):
		return false
	_active_screen_id = id
	emit_signal("screen_opened", id)
	return true

func close_screen() -> void:
	if not _active_screen_id.empty():
		var closed_id: String = _active_screen_id
		_active_screen_id = ""
		emit_signal("screen_closed", closed_id)

func get_active_screen_id() -> String:
	return _active_screen_id

# Fijar o soltar tambien reevalua Slot A: la pantalla fijada sale de la competencia de A (o
# vuelve a ella), porque una misma pantalla nunca ocupa los dos slots.
func pin_screen(id: String) -> void:
	_pinned_screen_id = id
	reevaluate_slots()

func unpin_screen() -> void:
	_pinned_screen_id = ""
	reevaluate_slots()

func get_pinned_screen_id() -> String:
	return _pinned_screen_id

func get_slot_snapshot(slot: String) -> Dictionary:
	return _slot_snapshots.get(slot, {}).duplicate(true)

func update_context_key(key: String, value) -> void:
	_context[key] = value
	reevaluate_slots()

func set_context(context_dict: Dictionary) -> void:
	_context = context_dict.duplicate(true)
	reevaluate_slots()

func get_context() -> Dictionary:
	return _context.duplicate(true)

func reevaluate_slots() -> void:
	_reevaluate_slot_a()
	_reevaluate_slot_b()

func perform_action(screen_id: String, op: String, args: Dictionary = {}) -> Dictionary:
	if not has_screen(screen_id):
		return {"ok": false, "error": "Screen '%s' not registered" % screen_id}

	var screen = _screens[screen_id]
	var allowed: Array = []
	if screen.has_method("allowed_actions"):
		allowed = screen.allowed_actions()
	elif screen.get("allowed_actions") != null:
		allowed = screen.get("allowed_actions")

	if not (op in allowed):
		return {"ok": false, "error": "Action '%s' not allowed on screen '%s'" % [op, screen_id]}

	if screen.has_method("perform_action"):
		return screen.perform_action(op, args)
	else:
		return {"ok": false, "error": "Screen '%s' does not implement perform_action" % screen_id}

func trigger_haptic(kind: String, intensity: float = 1.0) -> void:
	emit_signal("haptic", kind, intensity)

func save_state() -> Dictionary:
	return {
		"pinned_screen_id": _pinned_screen_id,
		"last_snapshots": _last_snapshots_cache.duplicate(true)
	}

func restore_state(data: Dictionary) -> void:
	if data.has("pinned_screen_id"):
		_pinned_screen_id = String(data["pinned_screen_id"])
	if data.has("last_snapshots") and typeof(data["last_snapshots"]) == TYPE_DICTIONARY:
		for k in data["last_snapshots"].keys():
			var snap = data["last_snapshots"][k]
			if typeof(snap) == TYPE_DICTIONARY:
				_last_snapshots_cache[k] = snap.duplicate(true)

	reevaluate_slots()

func get_snapshot() -> Dictionary:
	return save_state()

func restore_snapshot(data: Dictionary) -> void:
	restore_state(data)

func _on_pre_scene_swap(_old_scene: Node = null, _new_scene: Node = null, _params: Dictionary = {}) -> void:
	close_hud_mode()
	close_screen()
	set_context({})

func _on_screen_state_changed(id: String) -> void:
	_update_screen_snapshot_cache(id)
	reevaluate_slots()

func _extract_screen_id(screen: Object) -> String:
	if screen.has_method("screen_id"):
		return screen.screen_id()
	elif screen.get("hud_screen_id") != null:
		return String(screen.get("hud_screen_id"))
	elif screen.has_method("get_name"):
		return screen.get_name()
	return ""

func _update_screen_snapshot_cache(id: String) -> Dictionary:
	if not _screens.has(id):
		return {}
	var screen = _screens[id]
	if not is_instance_valid(screen):
		return {}

	var source_snap: Dictionary = {}
	if screen.has_method("widget_snapshot"):
		source_snap = screen.widget_snapshot()
	elif screen.has_method("get_widget_snapshot"):
		source_snap = screen.get_widget_snapshot()
	else:
		source_snap = {"proto": 1, "id": id, "source": "online"}

	var snap: Dictionary = source_snap.duplicate(true)

	if not snap.has("proto"):
		snap["proto"] = 1
	if not snap.has("id"):
		snap["id"] = id
	snap["source"] = "online"

	_last_snapshots_cache[id] = snap.duplicate(true)
	return snap

func _reevaluate_slot_a() -> void:
	var best_id: String = ""
	var max_rel: float = min_relevance_a

	for id in _screens.keys():
		var screen = _screens[id]
		# La fijada ya esta en Slot B: A muestra la mas relevante de las demas, nunca un duplicado.
		if not is_instance_valid(screen) or id == _pinned_screen_id:
			continue
		var rel: float = 0.0
		if screen.has_method("relevance"):
			rel = float(screen.relevance(_context))
		elif screen.has_method("get_relevance"):
			rel = float(screen.get_relevance(_context))

		if rel > max_rel:
			max_rel = rel
			best_id = id

	var new_snap: Dictionary = {}
	if not best_id.empty() and max_rel > min_relevance_a:
		new_snap = _update_screen_snapshot_cache(best_id)

	var current_snap = _slot_snapshots.get("slot_a", {})
	if new_snap != current_snap:
		_slot_snapshots["slot_a"] = new_snap.duplicate(true)
		emit_signal("widget_changed", "slot_a", _slot_snapshots["slot_a"])

func _reevaluate_slot_b() -> void:
	var new_snap: Dictionary = {}
	if not _pinned_screen_id.empty():
		if _screens.has(_pinned_screen_id) and is_instance_valid(_screens[_pinned_screen_id]):
			new_snap = _update_screen_snapshot_cache(_pinned_screen_id)
		elif _last_snapshots_cache.has(_pinned_screen_id):
			new_snap = _last_snapshots_cache[_pinned_screen_id].duplicate(true)
			new_snap["source"] = "offline"
		else:
			new_snap = {"proto": 1, "id": _pinned_screen_id, "source": "offline"}

	var current_snap = _slot_snapshots.get("slot_b", {})
	if new_snap != current_snap:
		_slot_snapshots["slot_b"] = new_snap.duplicate(true)
		emit_signal("widget_changed", "slot_b", _slot_snapshots["slot_b"])
