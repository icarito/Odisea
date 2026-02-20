extends Control
class_name TouchCameraControls

export(float) var sensitivity := 3.5
export(float) var zoom_sensitivity := 0.05
export(bool) var invert_x := true
export(bool) var invert_y := false
export(bool) var tap_to_jump := false
export(float) var tap_max_duration := 0.3
export(float) var tap_max_distance := 20.0

var _touch_index := -1
var _last_touch_pos := Vector2.ZERO
var _pinch_touches := {}
var _pinch_active := false
var _pinch_start_distance := 0.0
var _touch_controls_cache := []
var _cache_valid := false

var _tap_start_time := 0
var _tap_start_pos := Vector2.ZERO

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
			_tap_start_time = OS.get_ticks_msec()
			_tap_start_pos = event.position
		
		if _pinch_touches.size() == 2:
			_start_pinch()
	else:
		_pinch_touches.erase(event.index)
		
		if event.index == _touch_index:
			_check_tap(event.position)
			_touch_index = -1
		
		if _pinch_touches.size() < 2:
			_pinch_active = false

func _check_tap(end_pos: Vector2) -> void:
	if not tap_to_jump:
		return
	
	var duration = (OS.get_ticks_msec() - _tap_start_time) / 1000.0
	var distance = end_pos.distance_to(_tap_start_pos)
	
	if duration <= tap_max_duration and distance <= tap_max_distance:
		Input.action_press("jump")
		yield(get_tree().create_timer(0.05), "timeout")
		Input.action_release("jump")

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
			var x_mult = -1.0 if invert_x else 1.0
			var y_mult = -1.0 if invert_y else 1.0
			emit_signal("camera_drag", Vector2(delta.x * x_mult, delta.y * y_mult) * sensitivity)

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
