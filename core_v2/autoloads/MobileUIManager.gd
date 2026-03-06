extends CanvasLayer

const MobileUI = preload("res://core_v2/ui/MobileUI.tscn")

var _mobile_ui: CanvasLayer = null
var _touch_camera: TouchCameraControls = null
var _is_mobile := false

func _ready() -> void:
	layer = 100
	
	_is_mobile = (OS.has_touchscreen_ui_hint() or HardwareProfile.is_android() or HardwareProfile.get_platform() == HardwareProfile.PlatformType.IOS) and not HardwareProfile.is_switch()
	
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
	var input_provider = _get_active_input_provider()
	if input_provider:
		input_provider.add_touch_camera_drag(delta)

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

func get_reserved_overlay_margins(padding: float = 16.0) -> Dictionary:
	var margins = {
		"left": 0.0,
		"top": 0.0,
		"right": 0.0,
		"bottom": 0.0
	}
	if not is_instance_valid(_mobile_ui):
		return margins

	var viewport_size = get_viewport().get_visible_rect().size
	margins = _expand_overlay_margins(margins, _mobile_ui.get_node_or_null("Container/MoveJoystick"), viewport_size, padding)
	margins = _expand_overlay_margins(margins, _mobile_ui.get_node_or_null("Container/ActionButtons"), viewport_size, padding)
	return margins

func _expand_overlay_margins(margins: Dictionary, ctrl: Control, viewport_size: Vector2, padding: float) -> Dictionary:
	if not is_instance_valid(ctrl) or not ctrl.visible:
		return margins

	var top_left = ctrl.rect_global_position
	var scale = ctrl.rect_scale
	var size = Vector2(ctrl.rect_size.x * abs(scale.x), ctrl.rect_size.y * abs(scale.y))
	var bottom_right = top_left + size

	margins["bottom"] = max(float(margins.get("bottom", 0.0)), max(0.0, viewport_size.y - top_left.y + padding))
	if bottom_right.x <= viewport_size.x * 0.5:
		margins["left"] = max(float(margins.get("left", 0.0)), bottom_right.x + padding)
	if top_left.x >= viewport_size.x * 0.5:
		margins["right"] = max(float(margins.get("right", 0.0)), viewport_size.x - top_left.x + padding)
	return margins
