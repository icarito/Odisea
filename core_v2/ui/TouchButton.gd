extends Control
class_name TouchButton

export(String) var action_name := ""
export var is_toggle := false

var _is_pressed := false
var _touch_index := -1

onready var _button: Button = $Button

func _ready() -> void:
	if _button:
		_button.toggle_mode = is_toggle

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		if event.pressed:
			var rect = get_global_rect()
			if rect.has_point(event.position) and _touch_index == -1:
				_touch_index = event.index
				_press()
				get_tree().set_input_as_handled()
		elif event.index == _touch_index:
			_release()
			_touch_index = -1
			get_tree().set_input_as_handled()

func _press() -> void:
	_is_pressed = true
	if _button:
		_button.pressed = true
	if action_name != "":
		Input.action_press(action_name)

func _release() -> void:
	_is_pressed = false
	if _button:
		_button.pressed = false
	if action_name != "":
		Input.action_release(action_name)

func is_button_pressed() -> bool:
	return _is_pressed
