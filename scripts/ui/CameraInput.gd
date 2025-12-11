extends Control

signal camera_vector_changed(vector)

var touch_index = -1
var is_dragging = false
var start_pos = Vector2()

func _ready():
	print("[CameraInput] _ready called")
	set_process_input(true)
	# Move this control to the back of its siblings
	call_deferred("_move_to_back")

func _move_to_back():
	print("[CameraInput] _move_to_back called")
	if get_parent():
		print("[CameraInput] parent found, moving to back")
		get_parent().move_child(self, 0)
	else:
		print("[CameraInput] parent NOT found")

func _input(event):
	if event is InputEventScreenTouch:
		print("[CameraInput] InputEventScreenTouch received")
		if event.pressed:
			print("[CameraInput] Touch pressed at: ", event.position)
			if touch_index == -1 and not _is_on_ui(event.position):
				print("[CameraInput] Starting drag")
				touch_index = event.index
				is_dragging = true
				start_pos = event.position
		elif event.index == touch_index:
			print("[CameraInput] Stopping drag")
			touch_index = -1
			is_dragging = false

	if event is InputEventScreenDrag and event.index == touch_index:
		if is_dragging:
			var delta = event.relative
			print("[CameraInput] Dragging, delta: ", delta)
			emit_signal("camera_vector_changed", delta)

func _is_on_ui(position):
	# Check if the touch is on any other UI element that is a sibling of this control
	for node in get_parent().get_children():
		if node != self and node is Control and node.visible and node.get_global_rect().has_point(position) and node.mouse_filter != MOUSE_FILTER_IGNORE:
			print("[CameraInput] UI element found at position: ", position)
			return true
	return false

