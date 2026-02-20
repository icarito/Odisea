extends Control
class_name TouchCameraControls

export(float) var sensitivity := 1.0
export(float) var zoom_sensitivity := 0.5
export var deadzone_radius := 10.0

var _touch_index := -1
var _last_touch_pos := Vector2.ZERO
var _drag_delta := Vector2.ZERO
var _zoom_delta := 0.0
var _pinch_active := false
var _pinch_start_distance := 0.0
var _pinch_touches := {}

signal camera_drag(delta)
signal camera_zoom(delta)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _is_over_control(pos: Vector2) -> bool:
	var controls = get_tree().get_nodes_in_group("touch_control")
	for ctrl in controls:
		if is_instance_valid(ctrl) and ctrl.is_inside_tree():
			var rect = ctrl.get_global_rect()
			if rect.has_point(pos):
				return true
	return false

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _is_over_control(event.position):
			return
		
		_pinch_touches[event.index] = event.position
		
		if _touch_index == -1:
			_touch_index = event.index
			_last_touch_pos = event.position
			_drag_delta = Vector2.ZERO
		
		if _pinch_touches.size() == 2:
			_start_pinch()
	else:
		_pinch_touches.erase(event.index)
		
		if event.index == _touch_index:
			_touch_index = -1
			_drag_delta = Vector2.ZERO
		
		if _pinch_touches.size() < 2:
			_pinch_active = false

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index in _pinch_touches:
		_pinch_touches[event.index] = event.position
	
	if _pinch_active and _pinch_touches.size() == 2:
		_update_pinch()
		return
	
	if event.index == _touch_index:
		var delta = event.position - _last_touch_pos
		if delta.length() > deadzone_radius:
			_drag_delta = delta * sensitivity
			_last_touch_pos = event.position
			emit_signal("camera_drag", _drag_delta)
			_drag_delta = Vector2.ZERO

func _start_pinch() -> void:
	_pinch_active = true
	var positions = _pinch_touches.values()
	_pinch_start_distance = positions[0].distance_to(positions[1])

func _update_pinch() -> void:
	var positions = _pinch_touches.values()
	if positions.size() < 2:
		return
	
	var current_distance = positions[0].distance_to(positions[1])
	var delta = (current_distance - _pinch_start_distance) * zoom_sensitivity * 0.01
	_pinch_start_distance = current_distance
	_zoom_delta = delta
	emit_signal("camera_zoom", _zoom_delta)
	_zoom_delta = 0.0

func get_drag_delta() -> Vector2:
	var d = _drag_delta
	_drag_delta = Vector2.ZERO
	return d

func get_zoom_delta() -> float:
	var z = _zoom_delta
	_zoom_delta = 0.0
	return z

func consume_drag() -> Vector2:
	var d = _drag_delta
	_drag_delta = Vector2.ZERO
	return d

func consume_zoom() -> float:
	var z = _zoom_delta
	_zoom_delta = 0.0
	return z
