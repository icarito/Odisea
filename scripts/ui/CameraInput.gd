extends Control

signal camera_vector_changed(vector)

var touch_index = -1
var is_dragging = false
var start_pos = Vector2()

func _ready():
	set_process_input(true)
	# Move this control to the back of its siblings
	call_deferred("_move_to_back")

func _move_to_back():
	if get_parent():
		get_parent().move_child(self, 0)

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_index == -1 and not _is_on_ui(event.position):
				touch_index = event.index

				is_dragging = true

				start_pos = event.position

		elif event.index == touch_index:
			touch_index = -1

			is_dragging = false


	if event is InputEventScreenDrag and event.index == touch_index:
		if is_dragging:
			var delta = event.relative

			emit_signal("camera_vector_changed", delta)


func _is_on_ui(position):
	# Check if the touch is on any other UI element that is a sibling of this control
	for node in get_parent().get_children():
		if node != self and node is Control and node.visible and node.get_global_rect().has_point(position) and node.mouse_filter != MOUSE_FILTER_IGNORE:
			return true
	return false
