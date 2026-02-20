extends CanvasLayer

onready var touch_camera: TouchCameraControls = $Container/TouchCameraArea
onready var jump_button: Button = $Container/ActionButtons/JumpButton
onready var sprint_button: Button = $Container/ActionButtons/SprintButton
onready var crouch_button: Button = $Container/ActionButtons/CrouchButton
onready var interact_button: Button = $Container/ActionButtons/InteractButton

func _ready() -> void:
	_connect_button(jump_button, "jump")
	_connect_button(sprint_button, "run")
	_connect_button(crouch_button, "crouch")
	_connect_button(interact_button, "interact")

func _connect_button(btn: Button, action: String) -> void:
	if not btn:
		return
	btn.connect("button_down", self, "_on_button_down", [action])
	btn.connect("button_up", self, "_on_button_up", [action])

func _on_button_down(action: String) -> void:
	Input.action_press(action)

func _on_button_up(action: String) -> void:
	Input.action_release(action)
