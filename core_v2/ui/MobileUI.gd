extends CanvasLayer

onready var touch_camera: TouchCameraControls = $Container/TouchCameraArea

func _ready() -> void:
	if touch_camera:
		touch_camera.connect("camera_drag", self, "_on_camera_drag")
		touch_camera.connect("camera_zoom", self, "_on_camera_zoom")

func _on_camera_drag(delta: Vector2) -> void:
	var player = _get_player_controller()
	if player and player.input_provider:
		player.input_provider.add_touch_camera_drag(delta)

func _on_camera_zoom(delta: float) -> void:
	var player = _get_player_controller()
	if player and player.input_provider:
		player.input_provider.add_touch_camera_zoom(delta)

func _get_player_controller():
	var pilot = get_tree().get_nodes_in_group("player")
	if pilot.size() > 0:
		return pilot[0]
	return null
