extends CanvasLayer

const MobileUI = preload("res://core_v2/ui/MobileUI.tscn")

var _mobile_ui: CanvasLayer = null
var _touch_camera: TouchCameraControls = null
var _is_mobile := false

func _ready() -> void:
	layer = 100
	
	_is_mobile = OS.has_touchscreen_ui_hint() or OS.get_name() in ["Android", "iOS"]
	
	if _is_mobile:
		_spawn_mobile_ui()

func _spawn_mobile_ui() -> void:
	if _mobile_ui:
		return
	
	_mobile_ui = MobileUI.instance()
	add_child(_mobile_ui)
	
	_touch_camera = _get_touch_camera_control()
	if _touch_camera:
		_touch_camera.connect("camera_drag", self, "_on_camera_drag")
		_touch_camera.connect("camera_zoom", self, "_on_camera_zoom")

func _get_touch_camera_control() -> TouchCameraControls:
	if not _mobile_ui:
		return null
	var container = _mobile_ui.get_node_or_null("Container")
	if not container:
		return null
	return container.get_node_or_null("TouchCameraArea")

func _on_camera_drag(delta: Vector2) -> void:
	print("[MobileUIManager] Camera drag received: ", delta)
	var input_provider = _get_active_input_provider()
	if input_provider:
		input_provider.add_touch_camera_drag(delta)
	else:
		print("[MobileUIManager] No input provider found!")

func _on_camera_zoom(delta: float) -> void:
	var input_provider = _get_active_input_provider()
	if input_provider:
		input_provider.add_touch_camera_zoom(delta)

func _get_active_input_provider():
	var session = get_node_or_null("/root/SessionManager")
	if session and session.player and session.player.input_provider:
		return session.player.input_provider
	return null

func is_mobile() -> bool:
	return _is_mobile
