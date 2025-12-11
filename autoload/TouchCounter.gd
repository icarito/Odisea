extends Node

var active_touches = {}

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = true
		elif active_touches.has(event.index):
			active_touches.erase(event.index)

func get_touch_count() -> int:
	return active_touches.size()
