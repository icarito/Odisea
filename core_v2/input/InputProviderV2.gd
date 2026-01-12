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

const JOY_LOOK_SENSITIVITY := 15.0
const JOY_DEADZONE := 0.2


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
	
	# --- JOYSTICK SPRINT (Left Stick) ---
	# Auto-sprint si el stick se empuja casi a fondo (> 0.8).
	# Leemos los ejes crudos para no afectar al teclado (que siempre da 1.0).
	var joy_move = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_0),
		Input.get_joy_axis(0, JOY_AXIS_1)
	)
	if joy_move.length() > 0.8:
		d.sprint = true

	# Acumula y consume mouse_delta localmente
	# Consumir y limpiar aquí garantiza que cada frame use el delta exacto
	var mouse_d = Vector2(_q(mouse_delta_accum.x), _q(-mouse_delta_accum.y))
	
	# --- JOYSTICK CAMERA (Right Stick) ---
	# Ejes 2 y 3 suelen ser el stick derecho en gamepads estándar
	var joy_look = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_2),
		Input.get_joy_axis(0, JOY_AXIS_3)
	)
	
	if joy_look.length() > JOY_DEADZONE:
		# Aplicar curva o lineal. Aquí lineal simple post-deadzone.
		# Multiplicamos por sensibilidad para equiparar a "pixeles de mouse"
		mouse_d += joy_look * JOY_LOOK_SENSITIVITY

	d.mouse_delta = mouse_d
	
	# --- ZOOM ---
	d.zoom_delta = Input.get_action_strength("zoom_out") - Input.get_action_strength("zoom_in")

	# Limpiamos el acumulador de mouse real aquí
	mouse_delta_accum = Vector2()

	return d


func set_replay_data(data: Array):
	playback_buffer = data
	playback_index = 0
	mode = Mode.REPLAY

func set_live_mode():
	playback_buffer.clear()
	playback_index = 0
	mode = Mode.LIVE
