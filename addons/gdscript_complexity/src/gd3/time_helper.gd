# Time helper for Godot 3.x

extends Object

func get_timestamp() -> String:
	if OS.has_method("get_datetime"):
		var info = OS.call("get_datetime")
		if info != null:
			return "%04d-%02d-%02d %02d:%02d:%02d" % [
				info.year, info.month, info.day, info.hour, info.minute, info.second
			]
	return ""

func get_msec() -> int:
	if OS.has_method("get_ticks_msec"):
		var value = OS.call("get_ticks_msec")
		if value != null:
			return int(value)
	return 0
