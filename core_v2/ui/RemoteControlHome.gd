extends Control

var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
var RemoteProtocol = preload("res://core_v2/net/RemoteProtocol.gd")
var RadialSelectorScene = preload("res://core_v2/ui/radial/RadialSelectorV2.tscn")
var HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")

const SESSION_ENDED_NOTICE_SEC := 2.5

onready var exit_confirm: ConfirmationDialog = $ExitConfirm
onready var widget_host: Container = $WidgetHost
onready var hud_button: Button = $HUDButton
onready var fullscreen_overlay: Control = $FullScreenOverlay
onready var view_host: Container = $FullScreenOverlay/ViewHost
onready var close_view_button: Button = $FullScreenOverlay/CloseViewButton
onready var radial_overlay: Control = $RadialOverlay

var _input_provider: InputProviderV2 = null
var _remote_control_manager: Node = null
var _raw_passthrough: bool = not OS.get_name() in ["Android", "iOS"]
var _mouse_delta: Vector2 = Vector2.ZERO
var _was_captured: bool = false
var _title_text: String = ""
var _hint_text: String = ""
var _host_paused: bool = false

# F4 HUD Client State
var _screen_list: Array = []
var _snapshots_cache: Dictionary = {}
var _active_remote_screen: Dictionary = {}
var _local_pinned_screen_id: String = ""
var _mounted_widgets: Dictionary = {} # slot -> Node
var _radial_selector: Control = null
var _fullscreen_view_node: Node = null

func _ready() -> void:
	var virtual_cursor_layer := CanvasLayer.new()
	virtual_cursor_layer.layer = 100
	add_child(virtual_cursor_layer)
	virtual_cursor_layer.add_child(VirtualMouse.new())
	_remote_control_manager = get_node_or_null("/root/RemoteControlManager")
	_input_provider = InputProviderV2.new()

	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.fade_out_current_bgm(1.0)

	if _remote_control_manager and _remote_control_manager.client:
		var client = _remote_control_manager.client
		client.connect("session_ended", self, "_on_session_ended")
		client.connect("connection_lost", self, "_on_connection_lost")
		client.connect("connection_restored", self, "_on_connection_restored")
		client.connect("ui_directive_received", self, "_on_ui_directive")

	exit_confirm.connect("confirmed", self, "_on_exit_confirmed")
	exit_confirm.get_ok().text = "Salir"
	exit_confirm.get_cancel().text = "Cancelar"
	preload("res://core_v2/ui/DialogButtons.gd").fit_for_touch(exit_confirm)
	$ExitLayer/ExitButton.connect("pressed", self, "_on_exit_pressed")

	if hud_button:
		hud_button.connect("pressed", self, "_on_hud_button_pressed")
	if close_view_button:
		close_view_button.connect("pressed", self, "_on_close_view_pressed")

	_setup_radial_selector()

	if _raw_passthrough:
		$Hint.text = "Controlando con teclado y mouse. Esc libera el mouse; un clic lo vuelve a capturar."
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr and session_mgr.has_method("_start_mouse_capture_retry"):
			session_mgr._start_mouse_capture_retry()

	_title_text = $Title.text
	_hint_text = $Hint.text
	var client = _client()
	if client:
		_host_paused = client.host_paused
		_refresh_status()

	set_process(false)
	call_deferred("_connect_touch_camera")

func _setup_radial_selector() -> void:
	if RadialSelectorScene != null and radial_overlay != null:
		_radial_selector = RadialSelectorScene.instance()
		radial_overlay.add_child(_radial_selector)
		_radial_selector.set_title("Pantallas HUD")
		_radial_selector.connect("option_selected", self, "_on_radial_option_selected")
		_radial_selector.connect("cancelled", self, "_on_radial_cancelled")

func _connect_touch_camera() -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui and mobile_ui._touch_camera:
		mobile_ui._touch_camera.connect("camera_drag", self, "_on_camera_drag")
		mobile_ui._touch_camera.connect("camera_zoom", self, "_on_camera_zoom")

func _client() -> Node:
	return _remote_control_manager.client if _remote_control_manager else null

func _physics_process(_delta: float) -> void:
	var client = _client()
	if client == null:
		return
	if not _raw_passthrough:
		client.send_input_data(_input_provider.get_input().to_dict())
	elif _mouse_delta != Vector2.ZERO:
		client.send_input("mouse_delta", {"x": _mouse_delta.x, "y": _mouse_delta.y})
		_mouse_delta = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not _raw_passthrough or not event is InputEventMouseMotion:
		return
	var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if captured and _was_captured:
		_mouse_delta += (event as InputEventMouseMotion).relative
	_was_captured = captured

func _unhandled_input(event: InputEvent) -> void:
	if not _raw_passthrough:
		if event.is_action_pressed("ui_cancel"):
			_on_exit_pressed()
			get_tree().set_input_as_handled()
		return
	var client = _client()
	if client == null:
		return
	var payload: Dictionary = RemoteProtocol.encode_event(_event_for_host(event), get_viewport().get_visible_rect().size)
	if not payload.empty():
		client.send_input("event", payload)

func _event_for_host(event: InputEvent) -> InputEvent:
	if event is InputEventJoypadMotion and InputProviderV2.wants_handheld_axis_inversion() \
			and (event as InputEventJoypadMotion).axis in [JOY_AXIS_0, JOY_AXIS_1, JOY_AXIS_2, JOY_AXIS_3]:
		var corrected := event.duplicate() as InputEventJoypadMotion
		corrected.axis_value = -corrected.axis_value
		return corrected
	return event

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT and _raw_passthrough and _client():
		_client().send_input("release_all", {})

func _on_camera_drag(delta: Vector2) -> void:
	_input_provider.add_touch_camera_drag(delta)

func _on_camera_zoom(delta: float) -> void:
	_input_provider.add_touch_camera_zoom(delta)

func _on_exit_pressed() -> void:
	if exit_confirm.visible:
		exit_confirm.hide()
	else:
		exit_confirm.popup_centered()

func _on_exit_confirmed() -> void:
	if _remote_control_manager and _remote_control_manager.client:
		_remote_control_manager.client.disconnect_from_host()
	_go_to_menu()

func _on_connection_lost() -> void:
	$Title.text = "SIN CONEXIÓN"
	set_process(true)

func _process(_delta: float) -> void:
	var client = _client()
	var left: int = int(ceil(client.get_resume_time_left())) if client else 0
	$Hint.text = "Se perdió la conexión con el otro dispositivo. Reintentando... (%d s)" % left

func _on_connection_restored() -> void:
	set_process(false)
	_refresh_status()

# --- F4 HUD Directives ---

func _on_ui_directive(op: String, payload) -> void:
	match op:
		"host_paused":
			if typeof(payload) == TYPE_DICTIONARY:
				_host_paused = bool((payload as Dictionary).get("paused", false))
				if not is_processing():
					_refresh_status()

		"screen_list":
			if typeof(payload) == TYPE_ARRAY:
				_screen_list = (payload as Array).duplicate(true)
				_reevaluate_slots()
				_update_radial_options()

		"screen_active":
			if typeof(payload) == TYPE_DICTIONARY:
				_active_remote_screen = (payload as Dictionary).duplicate(true)
				_update_fullscreen_view()

		"screen_data":
			if typeof(payload) == TYPE_DICTIONARY:
				var dict: Dictionary = payload as Dictionary
				var sid: String = String(dict.get("id", ""))
				var snap: Dictionary = dict.get("snapshot", {}) if typeof(dict.get("snapshot")) == TYPE_DICTIONARY else {}
				if not sid.empty():
					_snapshots_cache[sid] = snap.duplicate(true)
					_reevaluate_slots()
					if sid == String(_active_remote_screen.get("id", "")):
						_active_remote_screen["snapshot"] = snap.duplicate(true)
						_update_fullscreen_view()

		"haptic":
			if typeof(payload) == TYPE_DICTIONARY:
				var intensity: float = float((payload as Dictionary).get("intensity", 1.0))
				if OS.get_name() in ["Android", "iOS"]:
					Input.vibrate_handheld(int(intensity * 100.0))

func _refresh_status() -> void:
	if _host_paused:
		$Title.text = "PARTIDA EN PAUSA"
		$Hint.text = "La partida está en pausa en el otro dispositivo." + (" Esc la reanuda." if _raw_passthrough else "")
	else:
		$Title.text = _title_text
		$Hint.text = _hint_text

func _on_hud_button_pressed() -> void:
	if is_instance_valid(_radial_selector):
		_update_radial_options()
		_radial_selector.open()

func _update_radial_options() -> void:
	if not is_instance_valid(_radial_selector):
		return
	var labels: Array = ["[Cerrar Vista]"]
	for item in _screen_list:
		if typeof(item) == TYPE_DICTIONARY:
			var sid: String = String(item.get("id", ""))
			var title: String = String(item.get("title", sid))
			if sid == _local_pinned_screen_id:
				title += " [PIN]"
			labels.append(title)
	_radial_selector.set_options(labels)

func _on_radial_option_selected(index: int) -> void:
	var client = _client()
	if client == null:
		return

	if index == 0:
		client.send_ui_directive("screen_select", {"id": ""})
	elif index - 1 < _screen_list.size():
		var item = _screen_list[index - 1]
		if typeof(item) == TYPE_DICTIONARY:
			var sid: String = String(item.get("id", ""))
			client.send_ui_directive("screen_select", {"id": sid})

func _on_radial_cancelled() -> void:
	pass

func _on_close_view_pressed() -> void:
	var client = _client()
	if client != null:
		client.send_ui_directive("screen_select", {"id": ""})

# --- Slot Evaluation & Widget Host ---

func pin_local_screen(id: String) -> void:
	_local_pinned_screen_id = id
	_reevaluate_slots()
	_update_radial_options()

func _reevaluate_slots() -> void:
	if widget_host == null:
		return

	var best_a_id: String = ""
	var max_rel: float = 0.0

	for item in _screen_list:
		if typeof(item) == TYPE_DICTIONARY:
			var sid: String = String(item.get("id", ""))
			var rel: float = float(item.get("relevance", 0.0))
			if rel > max_rel:
				max_rel = rel
				best_a_id = sid

	_mount_slot_widget("slot_a", best_a_id)
	_mount_slot_widget("slot_b", _local_pinned_screen_id)

func _mount_slot_widget(slot: String, screen_id: String) -> void:
	if screen_id.empty():
		_remove_slot_widget(slot)
		return

	var snap: Dictionary = _snapshots_cache.get(screen_id, {})
	if snap.empty():
		snap = {"proto": 1, "id": screen_id, "title": screen_id, "source": "online"}

	var existing = _mounted_widgets.get(slot, null)
	if is_instance_valid(existing) and _get_node_screen_id(existing) == screen_id:
		_hydrate_node(existing, snap)
		return

	_remove_slot_widget(slot)

	var widget_scene: PackedScene = _resolve_widget_scene(screen_id)
	var node: Control = null

	if widget_scene != null:
		node = widget_scene.instance() as Control
	else:
		node = PanelContainer.new()
		var label = Label.new()
		label.name = "TitleLabel"
		node.add_child(label)

	if node != null:
		_set_node_screen_id(node, screen_id)
		node.name = "Widget_" + slot
		widget_host.add_child(node)
		_mounted_widgets[slot] = node
		_hydrate_node(node, snap)

func _remove_slot_widget(slot: String) -> void:
	if _mounted_widgets.has(slot):
		var old = _mounted_widgets[slot]
		if is_instance_valid(old):
			old.queue_free()
		_mounted_widgets.erase(slot)

func _resolve_widget_scene(screen_id: String) -> PackedScene:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(screen_id):
		var screen = suit_os.get_screen(screen_id)
		if is_instance_valid(screen) and screen.has_method("widget_scene"):
			var scene = screen.widget_scene()
			if scene != null:
				return scene

	if screen_id.begins_with("holoterminal:"):
		return HoloTerminalWidgetScene

	return null

func _resolve_view_scene(screen_id: String) -> PackedScene:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(screen_id):
		var screen = suit_os.get_screen(screen_id)
		if is_instance_valid(screen) and screen.has_method("view_scene"):
			var scene = screen.view_scene()
			if scene != null:
				return scene

	return null

func _update_fullscreen_view() -> void:
	if fullscreen_overlay == null or view_host == null:
		return

	var sid: String = String(_active_remote_screen.get("id", ""))
	if sid.empty():
		fullscreen_overlay.visible = false
		if is_instance_valid(_fullscreen_view_node):
			_fullscreen_view_node.queue_free()
			_fullscreen_view_node = null
		return

	fullscreen_overlay.visible = true
	var snap: Dictionary = _active_remote_screen.get("snapshot", {})
	if snap.empty():
		snap = _snapshots_cache.get(sid, {})

	if is_instance_valid(_fullscreen_view_node) and _get_node_screen_id(_fullscreen_view_node) == sid:
		_hydrate_node(_fullscreen_view_node, snap)
		return

	if is_instance_valid(_fullscreen_view_node):
		_fullscreen_view_node.queue_free()
		_fullscreen_view_node = null

	var view_scene: PackedScene = _resolve_view_scene(sid)
	if view_scene == null:
		view_scene = _resolve_widget_scene(sid)

	var node: Control = null
	if view_scene != null:
		node = view_scene.instance() as Control
	else:
		node = PanelContainer.new()
		var label = Label.new()
		label.name = "TitleLabel"
		node.add_child(label)

	if node != null:
		_set_node_screen_id(node, sid)
		node.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		view_host.add_child(node)
		_fullscreen_view_node = node
		_hydrate_node(node, snap)

func _set_node_screen_id(node: Node, sid: String) -> void:
	if "screen_id" in node:
		node.set("screen_id", sid)
	node.set_meta("screen_id", sid)

func _get_node_screen_id(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_meta("screen_id"):
		return String(node.get_meta("screen_id"))
	if "screen_id" in node:
		return String(node.get("screen_id"))
	return ""

func _hydrate_node(node: Node, snap: Dictionary) -> void:
	if node.has_method("update_snapshot"):
		node.update_snapshot(snap)
	elif node.has_method("set_snapshot"):
		node.set_snapshot(snap)
	else:
		var label = node.get_node_or_null("TitleLabel")
		if label is Label:
			var title: String = String(snap.get("title", snap.get("id", "Screen")))
			label.text = "[REMOTE] " + title

func send_remote_action(screen_id: String, op: String, args: Dictionary = {}) -> void:
	var client = _client()
	if client != null:
		client.send_ui_directive("remote_action", {
			"screen_id": screen_id,
			"op": op,
			"args": args
		})

func _on_session_ended(reason: String) -> void:
	set_process(false)
	set_physics_process(false)
	exit_confirm.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$Title.text = "LA PARTIDA TERMINÓ"
	$Hint.text = "%s Volviendo al menú..." % reason
	get_tree().create_timer(SESSION_ENDED_NOTICE_SEC).connect("timeout", self, "_go_to_menu")

func _go_to_menu() -> void:
	get_tree().change_scene("res://scenes/Menu.tscn")
