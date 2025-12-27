extends Reference

class_name InputDataV2


var move_vec := Vector2()   # rango -1..1
var jump := false
var sprint := false
var mouse_delta := Vector2()

# Serialización a Dictionary
func to_dict() -> Dictionary:
	return {
		"move_vec": [move_vec.x, move_vec.y],
		"mouse_delta": [mouse_delta.x, mouse_delta.y],
		"jump": jump,
		"sprint": sprint
	}

# Deserialización desde Dictionary
func from_dict(d: Dictionary) -> void:
	if d.has("move_vec"):
		move_vec = Vector2(d["move_vec"][0], d["move_vec"][1])
	if d.has("mouse_delta"):
		mouse_delta = Vector2(d["mouse_delta"][0], d["mouse_delta"][1])
	if d.has("jump"):
		jump = d["jump"]
	if d.has("sprint"):
		sprint = d["sprint"]