extends Reference

class_name InputDataV2


var move_vec := Vector2() # rango -1..1
var jump := false
var sprint := false
var crouch := false
var interact := false
# Flanco (interact) vs sostenido (interact_held): el primero dispara una vez al pulsar,
# el segundo dura lo que dure la tecla. Los mecanismos de mantener presionado usan este.
var interact_held := false
var focus := false
var rotate_left := false
var rotate_right := false
var roll_left := false
var roll_right := false
var tool_fire_primary := false
var tool_fire_secondary := false
var tool_next_mode := false
var tool_prev_mode := false
var cargol_ability := false
var mouse_delta := Vector2()
var zoom_delta := 0.0
var fov_override := -1.0 # -1 means no override
var hardware_mouse_active := false # True when real mouse hardware contributed to mouse_delta
# True cuando move_vec viene de un STICK —fisico o el joystick virtual de touch— y no de
# teclas. Se graba junto al resto del frame a proposito: quien lo consume necesita saber de
# donde salio el movimiento, y resolverlo mirando el dispositivo en el momento de reproducir
# haria que el mismo replay se comportara distinto en escritorio que en Android.
var analog_move_active := false

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
		"interact_held": interact_held,
		"focus": focus,
		"rotate_left": rotate_left,
		"rotate_right": rotate_right,
		"roll_left": roll_left,
		"roll_right": roll_right,
		"tool_fire_primary": tool_fire_primary,
		"tool_fire_secondary": tool_fire_secondary,
		"tool_next_mode": tool_next_mode,
		"tool_prev_mode": tool_prev_mode,
		"cargol_ability": cargol_ability,
		"hardware_mouse_active": hardware_mouse_active,
		"analog_move_active": analog_move_active
	}

func is_equal_to(other) -> bool:
	if other == null:
		return false
	if not is_equal_approx(move_vec.x, other.move_vec.x) or not is_equal_approx(move_vec.y, other.move_vec.y):
		return false
	if not is_equal_approx(mouse_delta.x, other.mouse_delta.x) or not is_equal_approx(mouse_delta.y, other.mouse_delta.y):
		return false
	if not is_equal_approx(zoom_delta, other.zoom_delta):
		return false
	if not is_equal_approx(fov_override, other.fov_override):
		return false
	if jump != other.jump:
		return false
	if sprint != other.sprint:
		return false
	if crouch != other.crouch:
		return false
	if interact != other.interact:
		return false
	if focus != other.focus:
		return false
	if rotate_left != other.rotate_left:
		return false
	if rotate_right != other.rotate_right:
		return false
	if roll_left != other.roll_left:
		return false
	if roll_right != other.roll_right:
		return false
	if tool_fire_primary != other.tool_fire_primary:
		return false
	if tool_fire_secondary != other.tool_fire_secondary:
		return false
	if tool_next_mode != other.tool_next_mode:
		return false
	if tool_prev_mode != other.tool_prev_mode:
		return false
	if cargol_ability != other.cargol_ability:
		return false
	if hardware_mouse_active != other.hardware_mouse_active:
		return false
	if analog_move_active != other.analog_move_active:
		return false
	return true

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
	if d.has("interact_held"):
		interact_held = d["interact_held"]
	if d.has("focus"):
		focus = d["focus"]
	if d.has("rotate_left"):
		rotate_left = d["rotate_left"]
	if d.has("rotate_right"):
		rotate_right = d["rotate_right"]
	if d.has("roll_left"):
		roll_left = d["roll_left"]
	if d.has("roll_right"):
		roll_right = d["roll_right"]
	if d.has("tool_fire_primary"):
		tool_fire_primary = d["tool_fire_primary"]
	if d.has("tool_fire_secondary"):
		tool_fire_secondary = d["tool_fire_secondary"]
	if d.has("tool_next_mode"):
		tool_next_mode = d["tool_next_mode"]
	if d.has("tool_prev_mode"):
		tool_prev_mode = d["tool_prev_mode"]
	if d.has("cargol_ability"):
		cargol_ability = d["cargol_ability"]
	if d.has("hardware_mouse_active"):
		hardware_mouse_active = d["hardware_mouse_active"]
	if d.has("analog_move_active"):
		analog_move_active = d["analog_move_active"]
