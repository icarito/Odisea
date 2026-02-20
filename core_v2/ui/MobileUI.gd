extends CanvasLayer

onready var touch_camera: TouchCameraControls = $Container/TouchCameraArea
onready var jump_button: Button = $Container/ActionButtons/JumpButton
onready var sprint_button: Button = $Container/ActionButtons/SprintButton
onready var crouch_button: Button = $Container/ActionButtons/CrouchButton
onready var interact_button: Button = $Container/ActionButtons/InteractButton
onready var move_joystick = $Container/MoveJoystick

func _ready() -> void:
	if move_joystick:
		move_joystick.add_to_group("touch_control")
	
	if jump_button:
		jump_button.add_to_group("touch_control")
		jump_button.connect("button_down", self, "_on_button_down", ["jump"])
		jump_button.connect("button_up", self, "_on_button_up", ["jump"])
	
	if sprint_button:
		sprint_button.add_to_group("touch_control")
		sprint_button.connect("button_down", self, "_on_button_down", ["run"])
		sprint_button.connect("button_up", self, "_on_button_up", ["run"])
	
	if crouch_button:
		crouch_button.add_to_group("touch_control")
		crouch_button.connect("button_down", self, "_on_button_down", ["crouch"])
		crouch_button.connect("button_up", self, "_on_button_up", ["crouch"])
	
	if interact_button:
		interact_button.add_to_group("touch_control")
		interact_button.connect("button_down", self, "_on_button_down", ["interact"])
		interact_button.connect("button_up", self, "_on_button_up", ["interact"])

func _on_button_down(action: String) -> void:
	Input.action_press(action)

func _on_button_up(action: String) -> void:
	Input.action_release(action)
