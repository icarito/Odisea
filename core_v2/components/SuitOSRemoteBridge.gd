extends Node

# SuitOSRemoteBridge.gd - Bridges SuitOS with RemoteControlServer (FD-296 F4)
# Sends screen_list, screen_active, screen_data, and haptic directives to connected mobile client.
# Handles incoming screen_select and remote_action directives.

var server: Node = null # Explicit override for testing
var _remote_active_screen_id: String = ""

func _ready() -> void:
	_connect_suitos_signals()
	_connect_server_signals()

func _connect_suitos_signals() -> void:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return

	if not suit_os.is_connected("screen_registered", self, "_on_screen_registered"):
		suit_os.connect("screen_registered", self, "_on_screen_registered")
	if not suit_os.is_connected("screen_unregistered", self, "_on_screen_unregistered"):
		suit_os.connect("screen_unregistered", self, "_on_screen_unregistered")
	if not suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
		suit_os.connect("widget_changed", self, "_on_widget_changed")
	if not suit_os.is_connected("haptic", self, "_on_suitos_haptic"):
		suit_os.connect("haptic", self, "_on_suitos_haptic")

func _connect_server_signals() -> void:
	var server = _get_server()
	if server == null:
		return

	if not server.is_connected("client_connected", self, "_on_client_connected"):
		server.connect("client_connected", self, "_on_client_connected")
	if not server.is_connected("ui_directive_received", self, "_on_ui_directive_received"):
		server.connect("ui_directive_received", self, "_on_ui_directive_received")

func _get_server() -> Node:
	if is_instance_valid(server):
		return server
	var parent = get_parent()
	if is_instance_valid(parent) and "server" in parent and is_instance_valid(parent.server):
		return parent.server
	var mgr = get_node_or_null("/root/RemoteControlManager")
	if is_instance_valid(mgr) and "server" in mgr and is_instance_valid(mgr.server):
		return mgr.server
	return null

func _on_client_connected(_device_name: String) -> void:
	_send_screen_list()
	if not _remote_active_screen_id.empty():
		_refresh_remote_active_screen()

func _send_screen_list() -> void:
	var server = _get_server()
	if server == null or not server.has_method("has_paired_client") or not server.has_paired_client():
		return

	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return

	var screens_list: Array = []
	var context: Dictionary = suit_os.get_context() if suit_os.has_method("get_context") else {}

	for id in suit_os.get_registered_screens():
		var screen = suit_os.get_screen(id)
		if is_instance_valid(screen):
			var title: String = screen.screen_title() if screen.has_method("screen_title") else String(id)
			var rel: float = screen.relevance(context) if screen.has_method("relevance") else 0.0
			var entry: Dictionary = {
				"id": id,
				"title": title,
				"relevance": rel
			}
			# El control remoto no tiene estas pantallas registradas (no corre el mundo),
			# asi que no puede resolver ni su widget ni sus datos: sin esto mostraba la
			# ruta cruda como nombre y "EN ESPERA" como estado. Los dos lados corren el
			# mismo build, asi que la ruta de la escena le sirve tal cual.
			if screen.has_method("widget_scene"):
				var widget_scene = screen.widget_scene()
				if widget_scene != null:
					entry["widget"] = widget_scene.resource_path
			if screen.has_method("widget_snapshot"):
				entry["snapshot"] = screen.widget_snapshot()
			screens_list.append(entry)

	server.send_ui_directive("screen_list", screens_list)

func _on_screen_registered(_id: String) -> void:
	_send_screen_list()

func _on_screen_unregistered(id: String) -> void:
	_send_screen_list()
	if id == _remote_active_screen_id:
		set_remote_active_screen("")

func _on_widget_changed(_slot: String, snapshot: Dictionary) -> void:
	if not _has_paired_client():
		return
	var snap_id: String = String(snapshot.get("id", ""))
	if not snap_id.empty():
		_send_screen_data(snap_id, snapshot)

func _on_suitos_haptic(kind: String, intensity: float = 1.0) -> void:
	var server = _get_server()
	if server != null and _has_paired_client():
		server.send_ui_directive("haptic", {"kind": kind, "intensity": intensity})

func _has_paired_client() -> bool:
	var server = _get_server()
	return server != null and server.has_method("has_paired_client") and server.has_paired_client()

func _on_ui_directive_received(op: String, payload) -> void:
	match op:
		"screen_select":
			var target_id: String = ""
			if typeof(payload) == TYPE_DICTIONARY:
				target_id = String((payload as Dictionary).get("id", ""))
			set_remote_active_screen(target_id)

		"remote_action":
			# Con la partida en pausa el mundo esta congelado: un widget del control no la cambia
			# (la linterna no se prende en pausa). Aca y no solo en el control, que puede tener
			# el aviso de pausa atrasado.
			if get_tree().paused:
				return
			if typeof(payload) == TYPE_DICTIONARY:
				var dict: Dictionary = payload as Dictionary
				var screen_id: String = String(dict.get("screen_id", ""))
				var action_op: String = String(dict.get("op", ""))
				var args: Dictionary = dict.get("args", {}) if typeof(dict.get("args")) == TYPE_DICTIONARY else {}

				var suit_os = get_node_or_null("/root/SuitOS")
				if suit_os != null and suit_os.has_screen(screen_id):
					var result = suit_os.perform_action(screen_id, action_op, args)
					if screen_id == _remote_active_screen_id:
						_refresh_remote_active_screen()

func set_remote_active_screen(id: String) -> void:
	_remote_active_screen_id = id
	_refresh_remote_active_screen()

func get_remote_active_screen_id() -> String:
	return _remote_active_screen_id

func _refresh_remote_active_screen() -> void:
	var server = _get_server()
	if server == null or not _has_paired_client():
		return

	if _remote_active_screen_id.empty():
		server.send_ui_directive("screen_active", {
			"id": "",
			"title": "",
			"view": "widget",
			"snapshot": {}
		})
		return

	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null or not suit_os.has_screen(_remote_active_screen_id):
		_remote_active_screen_id = ""
		server.send_ui_directive("screen_active", {
			"id": "",
			"title": "",
			"view": "widget",
			"snapshot": {}
		})
		return

	var screen = suit_os.get_screen(_remote_active_screen_id)
	var title: String = screen.screen_title() if screen.has_method("screen_title") else _remote_active_screen_id
	var view_type: String = "widget"
	# La vista completa (la UI del terminal) es una escena en disco cuando el contenido es
	# estatico. El control no la puede resolver por su cuenta -- no tiene la pantalla
	# registrada -- asi que viaja la ruta y su resolucion de diseño. Si la pantalla presta
	# su Viewport en vivo (view_is_source) no hay escena que mandar: alla solo va el widget.
	var view_path: String = ""
	var view_size: Array = []
	if screen.has_method("view_scene"):
		var view_scene = screen.view_scene()
		if view_scene != null:
			view_type = "scene"
			view_path = view_scene.resource_path
			if screen.has_method("view_size"):
				var design: Vector2 = screen.view_size()
				if design.x > 0.0 and design.y > 0.0:
					view_size = [design.x, design.y]

	var snap: Dictionary = {}
	if screen.has_method("widget_snapshot"):
		snap = screen.widget_snapshot()

	server.send_ui_directive("screen_active", {
		"id": _remote_active_screen_id,
		"title": title,
		"view": view_type,
		"view_scene": view_path,
		"view_size": view_size,
		"snapshot": snap
	})

func _send_screen_data(id: String, snapshot: Dictionary) -> void:
	var server = _get_server()
	if server != null and _has_paired_client():
		server.send_ui_directive("screen_data", {
			"id": id,
			"snapshot": snapshot
		})
