extends Reference

var _queue := []
var _mutex := Mutex.new()

func push(command: Dictionary) -> void:
	_mutex.lock()
	_queue.push_back(command)
	_mutex.unlock()

func pop_all() -> Array:
	_mutex.lock()
	var all = _queue.duplicate()
	_queue.clear()
	_mutex.unlock()
	return all

func size() -> int:
	_mutex.lock()
	var s = _queue.size()
	_mutex.unlock()
	return s
