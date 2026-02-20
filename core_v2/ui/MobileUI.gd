extends CanvasLayer

onready var touch_camera: TouchCameraControls = $Container/TouchCameraArea
onready var move_joystick = $Container/MoveJoystick

func _ready() -> void:
	if move_joystick:
		move_joystick.add_to_group("touch_control")
