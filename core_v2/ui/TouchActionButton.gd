extends Button
class_name TouchActionButton

export(String) var action_name := ""

var _touch_index := -1

func _ready() -> void:
	add_to_group("touch_control")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		var rect = get_global_rect()
		if event.pressed:
			if rect.has_point(event.position) and _touch_index == -1:
				_touch_index = event.index
				_press()
				get_tree().set_input_as_handled()
		elif event.index == _touch_index:
			_release()
			_touch_index = -1
			get_tree().set_input_as_handled()
	
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			var rect = get_global_rect()
			if not rect.has_point(event.position):
				_release()
				_touch_index = -1

func _press() -> void:
	pressed = true
	if action_name != "":
		Input.action_press(action_name)

func _release() -> void:
	pressed = false
	if action_name != "":
		Input.action_release(action_name)
