extends CanvasLayer

onready var touch_camera: TouchCameraControls = $Container/TouchCameraArea
onready var move_joystick = $Container/MoveJoystick
onready var zero_g_buttons = $Container/ZeroGButtons
onready var skip_button = $Container/SkipButton

func _ready() -> void:
	if move_joystick:
		move_joystick.add_to_group("touch_control")

func set_zero_g_mode(enabled: bool) -> void:
	if zero_g_buttons:
		zero_g_buttons.visible = enabled

func set_skip_visible(enabled: bool) -> void:
	if skip_button:
		skip_button.visible = enabled
