extends Control
class_name TouchCameraControls

export(float) var sensitivity := 2.0
export(float) var zoom_sensitivity := 0.05

var _touch_index := -1
var _last_touch_pos := Vector2.ZERO
var _pinch_touches := {}
var _pinch_active := false
var _pinch_start_distance := 0.0
var _touch_controls_cache := []
var _cache_valid := false

signal camera_drag(delta)
signal camera_zoom(delta)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().connect("node_added", self, "_on_node_added")
	get_tree().connect("node_removed", self, "_on_node_removed")

func _on_node_added(node: Node) -> void:
	if node.is_in_group("touch_control"):
		_cache_valid = false

func _on_node_removed(node: Node) -> void:
	if node.is_in_group("touch_control"):
		_cache_valid = false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _get_touch_controls() -> Array:
	if not _cache_valid:
		_touch_controls_cache = get_tree().get_nodes_in_group("touch_control")
		_cache_valid = true
	return _touch_controls_cache

func _is_over_control(pos: Vector2) -> bool:
	for ctrl in _get_touch_controls():
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
		
		if _pinch_touches.size() == 2:
			_start_pinch()
	else:
		_pinch_touches.erase(event.index)
		
		if event.index == _touch_index:
			_touch_index = -1
		
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
		_last_touch_pos = event.position
		if delta.length_squared() > 0.1:
			emit_signal("camera_drag", Vector2(-delta.x, -delta.y) * sensitivity)

func _start_pinch() -> void:
	_pinch_active = true
	var positions = _pinch_touches.values()
	_pinch_start_distance = positions[0].distance_to(positions[1])

func _update_pinch() -> void:
	var positions = _pinch_touches.values()
	if positions.size() < 2:
		return
	
	var current_distance = positions[0].distance_to(positions[1])
	var delta = (_pinch_start_distance - current_distance) * zoom_sensitivity
	_pinch_start_distance = current_distance
	emit_signal("camera_zoom", delta)
