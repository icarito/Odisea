extends Control

var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")

onready var exit_confirm: ConfirmationDialog = $ExitConfirm
var _input_provider: InputProviderV2 = null
var _remote_control_manager: Node = null

func _ready() -> void:
	_remote_control_manager = get_node_or_null("/root/RemoteControlManager")
	_input_provider = InputProviderV2.new()
	exit_confirm.connect("confirmed", self, "_on_exit_confirmed")
	$ExitLayer/ExitButton.connect("pressed", self, "_on_exit_pressed")
	call_deferred("_connect_touch_camera")

func _connect_touch_camera() -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui and mobile_ui._touch_camera:
		mobile_ui._touch_camera.connect("camera_drag", self, "_on_camera_drag")
		mobile_ui._touch_camera.connect("camera_zoom", self, "_on_camera_zoom")

func _physics_process(_delta: float) -> void:
	if _remote_control_manager and _remote_control_manager.client:
		_remote_control_manager.client.send_input_data(_input_provider.get_input().to_dict())

func _on_camera_drag(delta: Vector2) -> void:
	_input_provider.add_touch_camera_drag(delta)

func _on_camera_zoom(delta: float) -> void:
	_input_provider.add_touch_camera_zoom(delta)

func _on_exit_pressed() -> void:
	exit_confirm.popup_centered()

func _on_exit_confirmed() -> void:
	if _remote_control_manager and _remote_control_manager.client:
		_remote_control_manager.client.disconnect_from_host()
	get_tree().change_scene("res://scenes/Menu.tscn")
