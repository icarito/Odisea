extends Node

# Toda la comunicacion con el jugador sale por el widget de contexto del HUD (SuitOSWidgetHost),
# abajo-centro. El subtitulo propio (PlayerHintOverlay) se retiro: no hay carteles aparte.
const MAX_HINT_DURATION := 30.0

var _interaction_text := ""
# FD-310: el nodo del interactuable en rango. Con el, el hint de interaccion se muestra como widget
# de contexto en el HUD (SuitOSWidgetHost) en vez del subtitulo; el texto queda de fallback y para
# el control remoto.
var _interaction_source: Node = null
var _context_showing := false
var _context_last_text := ""
var _context_last_title := ""
var _context_last_description := ""
var _manual_text := ""
var _status_text := ""
var _manual_expires_at := 0.0
var _status_expires_at := 0.0
var _explicit_interactive := true
var _refresh_timer: Timer = null
# Hint que ya resolvio otro dispositivo (el host, visto desde el control remoto): se muestra tal
# cual, sin volver a aplicar prioridades ni vencimientos (esos corren alla).
var _remote_text := ""
var _remote_mode := "hint"
var _last_emitted := ["", ""]

# Lo que se ve cambio (texto o modo). El control remoto lo replica (SuitOSRemoteBridge).
signal visible_hint_changed(text, mode)

func _ready() -> void:
	_ensure_refresh_timer()
	_refresh_visible_hint()

func show_interaction_hint(text: String, source: Node = null) -> void:
	_interaction_text = text.strip_edges()
	_interaction_source = source if is_instance_valid(source) else null
	_refresh_visible_hint()

func clear_interaction_hint() -> void:
	if _interaction_text == "" and not _context_showing:
		return
	_interaction_text = ""
	_interaction_source = null
	_refresh_visible_hint()

func show_manual_hint(text: String, duration: float = MAX_HINT_DURATION) -> void:
	var clean_text := text.strip_edges()
	if clean_text == "":
		clear_manual_hint()
		return
	if not _is_runtime_interactive():
		return
	_manual_text = clean_text
	var clamped_duration := clamp(duration, 0.05, MAX_HINT_DURATION)
	_manual_expires_at = _now_sec() + clamped_duration
	_refresh_visible_hint()

func clear_manual_hint() -> void:
	if _manual_text == "":
		return
	_manual_text = ""
	_manual_expires_at = 0.0
	_refresh_visible_hint()

func show_status_hint(text: String, duration: float = 2.0) -> void:
	var clean_text := text.strip_edges()
	if clean_text == "":
		clear_status_hint()
		return
	if not _is_runtime_interactive():
		return
	_status_text = clean_text
	_status_expires_at = _now_sec() + clamp(duration, 0.05, MAX_HINT_DURATION)
	_refresh_visible_hint()

func clear_status_hint() -> void:
	if _status_text == "":
		return
	_status_text = ""
	_status_expires_at = 0.0
	_refresh_visible_hint()

func show_remote_hint(text: String, mode: String = "hint") -> void:
	_remote_text = text.strip_edges()
	_remote_mode = mode if mode in ["hint", "status"] else "hint"
	_refresh_visible_hint()

func get_visible_mode() -> String:
	if _remote_text != "":
		return _remote_mode
	return "status" if _status_text != "" else "hint"

func set_interactive(enabled: bool) -> void:
	_explicit_interactive = enabled
	_refresh_visible_hint()

func is_enabled() -> bool:
	var env = OS.get_environment("ODISEA_PLAYER_HINTS").strip_edges().to_lower()
	if env != "":
		if env in ["1", "true", "yes", "on"]:
			return true
		if env in ["0", "false", "no", "off"]:
			return false
	if OS.has_feature("Server"):
		return false
	return true

func get_visible_text() -> String:
	if not _is_runtime_interactive():
		return ""
	_prune_expired_manual()
	_prune_expired_status()
	if _remote_text != "":
		return _remote_text
	if _status_text != "":
		return _status_text
	if _manual_text != "":
		return _manual_text
	return _interaction_text

func _refresh_visible_hint() -> void:
	_prune_expired_manual()
	_prune_expired_status()
	var text := get_visible_text()
	var visible_mode := get_visible_mode() if text != "" else ""
	if [text, visible_mode] != _last_emitted:
		_last_emitted = [text, visible_mode]
		emit_signal("visible_hint_changed", text, visible_mode)
	# Toda la comunicacion sale por el widget de contexto del HUD (abajo-centro): ya no hay
	# subtitulo propio ni carteles sueltos. El control remoto recibe el texto por la senal.
	_update_context_widget(text, visible_mode)

func _update_context_widget(text: String, _visible_mode: String) -> void:
	var host = _context_host()
	if host == null:
		_context_showing = false
		return
	if text == "":
		if _context_showing and host.has_method("clear_context"):
			host.clear_context()
		_context_showing = false
		return
	var title := _context_title(_interaction_source)
	var description := ""
	var icon: Texture = null
	if is_instance_valid(_interaction_source):
		if "interaction_description" in _interaction_source:
			description = String(_interaction_source.interaction_description)
		if "interaction_icon" in _interaction_source and _interaction_source.interaction_icon is Texture:
			icon = _interaction_source.interaction_icon
	if _context_showing and text == _context_last_text and title == _context_last_title \
			and description == _context_last_description:
		return
	var snapshot := {"title": title, "action": text, "description": description}
	if icon != null:
		snapshot["icon"] = icon
	if host.show_context(snapshot):
		_context_showing = true
		_context_last_text = text
		_context_last_title = title
		_context_last_description = description
	else:
		_context_showing = false

func _context_host() -> Node:
	if not get_tree():
		return null
	for host in get_tree().get_nodes_in_group("hud_widget_host"):
		if is_instance_valid(host) and host.has_method("show_context"):
			return host
	return null

func _context_title(source: Node) -> String:
	if not is_instance_valid(source):
		return ""
	if source.has_method("screen_title"):
		var screen_title := String(source.screen_title())
		if screen_title != "":
			return screen_title
	if "interaction_title" in source:
		var custom := String(source.interaction_title)
		if custom != "":
			return custom
	return String(source.name).replace("_", " ")

func _prune_expired_manual() -> void:
	if _manual_text == "":
		return
	if _now_sec() >= _manual_expires_at:
		_manual_text = ""
		_manual_expires_at = 0.0

func _prune_expired_status() -> void:
	if _status_text == "":
		return
	if _now_sec() >= _status_expires_at:
		_status_text = ""
		_status_expires_at = 0.0

func _is_runtime_interactive() -> bool:
	if not _explicit_interactive:
		return false
	var screen_fx = get_node_or_null("/root/ScreenEffectsManager")
	if screen_fx:
		var depth = screen_fx.get("_script_cinematic_depth")
		if typeof(depth) == TYPE_INT and int(depth) > 0:
			return false
	var player = _find_player()
	if player and "input_provider" in player and is_instance_valid(player.input_provider):
		if not bool(player.input_provider.hardware_input_enabled):
			return false
	return true

func _find_player() -> Node:
	var session = get_node_or_null("/root/SessionManager")
	if session and "player" in session and is_instance_valid(session.player):
		return session.player
	if get_tree():
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			return players[0]
	return null

func _ensure_refresh_timer() -> void:
	if _refresh_timer:
		return
	_refresh_timer = Timer.new()
	_refresh_timer.name = "HintRefreshTimer"
	_refresh_timer.wait_time = 0.2
	_refresh_timer.one_shot = false
	_refresh_timer.autostart = true
	add_child(_refresh_timer)
	_refresh_timer.connect("timeout", self, "_on_refresh_timer_timeout")

func _on_refresh_timer_timeout() -> void:
	_refresh_visible_hint()

func _now_sec() -> float:
	return OS.get_ticks_msec() / 1000.0
