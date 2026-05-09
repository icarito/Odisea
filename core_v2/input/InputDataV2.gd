extends Reference

class_name InputDataV2


var move_vec := Vector2() # rango -1..1
var jump := false
var sprint := false
var crouch := false
var interact := false
var focus := false
var mouse_delta := Vector2()
var zoom_delta := 0.0
var fov_override := -1.0 # -1 means no override
var hardware_mouse_active := false # True when real mouse hardware contributed to mouse_delta

func _canonical_float(v: float) -> float:
	# Avoid noisy JSON diffs from signed zero (-0.0 vs 0.0).
	return 0.0 if v == 0.0 else v

# Serialización a Dictionary
func to_dict() -> Dictionary:
	return {
		"move_vec": [_canonical_float(move_vec.x), _canonical_float(move_vec.y)],
		"mouse_delta": [_canonical_float(mouse_delta.x), _canonical_float(mouse_delta.y)],
		"zoom_delta": _canonical_float(zoom_delta),
		"fov_override": _canonical_float(fov_override),
		"jump": jump,
		"sprint": sprint,
		"crouch": crouch,
		"interact": interact,
		"focus": focus,
		"hardware_mouse_active": hardware_mouse_active
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
	if d.has("focus"):
		focus = d["focus"]
	if d.has("hardware_mouse_active"):
		hardware_mouse_active = d["hardware_mouse_active"]
