extends Node

var is_pushing := false
var _wish_direction := Vector3.ZERO

func set_wish_direction(value: Vector3) -> void:
	_wish_direction = value

func get_wish_direction() -> Vector3:
	return _wish_direction
