extends CanvasLayer

onready var joystick = $Joystick

func _ready():
	UIManager.register_joystick(joystick)
