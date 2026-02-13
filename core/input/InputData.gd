extends Reference

class_name InputData


var move_vec := Vector2() # rango -1..1
var jump := false
var sprint := false
var crouch := false
var interact := false
var mouse_delta := Vector2()
var zoom_delta := 0.0
var fov_override := -1.0 # -1 means no override

# Serialización a Dictionary
func to_dict() -> Dictionary:
	return {
		"move_vec": [move_vec.x, move_vec.y],
		"mouse_delta": [mouse_delta.x, mouse_delta.y],
		"zoom_delta": zoom_delta,
		"fov_override": fov_override,
		"jump": jump,
		"sprint": sprint,
		"crouch": crouch,
		"interact": interact
	}

# Deserialización desde Dictionary
func from_dict(d: Dictionary) -> void:
	if d.has("move_vec"):
		move_vec = Vector2(d["move_vec"][0], d["move_vec"][1])
	if d.has("mouse_delta"):
		mouse_delta = Vector2(d["mouse_delta"][0], d["mouse_delta"][1])
	if d.has("zoom_delta"):
		zoom_delta = d["zoom_delta"]
	if d.has("fov_override"):
		fov_override = d["fov_override"]
	if d.has("jump"):
		jump = d["jump"]
	if d.has("sprint"):
		sprint = d["sprint"]
	if d.has("crouch"):
		crouch = d["crouch"]
	if d.has("interact"):
		interact = d["interact"]
