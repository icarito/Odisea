extends Reference
class_name InputProviderV2

enum Mode {
	LIVE,
	REPLAY
}

var mode = Mode.LIVE
var playback_buffer := []
var playback_index := 0
var mouse_delta_accum := Vector2()


# Universal input getter
func get_input() -> InputDataV2:
	if mode == Mode.REPLAY:
		if playback_index < playback_buffer.size():
			var d = InputDataV2.new()
			d.from_dict(playback_buffer[playback_index])
			playback_index += 1
			return d
		return InputDataV2.new() # Input neutro si se acaba el buffer
	else:
		return _read_live_input()


func _q(v):
	return round(v * 1000.0) / 1000.0



func _read_live_input() -> InputDataV2:
	var d = InputDataV2.new()

	d.move_vec = Vector2(
		Input.get_action_strength("move_left") - Input.get_action_strength("move_right"),
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)

	d.move_vec.x = _q(d.move_vec.x)
	d.move_vec.y = _q(d.move_vec.y)

	d.jump = Input.is_action_pressed("jump")
	d.sprint = Input.is_action_pressed("run")

	# Acumula y consume mouse_delta localmente
	# Consumir y limpiar aquí garantiza que cada frame use el delta exacto
	d.mouse_delta = Vector2(_q(mouse_delta_accum.x), _q(-mouse_delta_accum.y))
	# Limpiamos el acumulador aquí: el proveedor es la única fuente que lo gestiona
	mouse_delta_accum = Vector2()

	return d




func set_replay_data(data:Array):
	playback_buffer = data
	playback_index = 0
	mode = Mode.REPLAY

func set_live_mode():
	playback_buffer.clear()
	playback_index = 0
	mode = Mode.LIVE
