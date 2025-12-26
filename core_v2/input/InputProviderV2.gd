extends Reference

class_name InputProviderV2

enum Mode {
    LIVE,
    REPLAY
}

var mode = Mode.LIVE
var replay_buffer := []
var replay_index := 0


func get_frame_input() -> InputDataV2:
    if mode == Mode.LIVE:
        return _read_live_input()
    else:
        return _read_replay_input()


func _read_live_input() -> InputDataV2:
    var d = InputDataV2.new()

    d.move_vec = Vector2(
        Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
        Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
    )

    d.jump = Input.is_action_pressed("jump")
    d.sprint = Input.is_action_pressed("run")
    d.mouse_delta = Input.get_last_mouse_speed()

    # Quantize for determinism
    d.move_vec.x = _q(d.move_vec.x)
    d.move_vec.y = _q(d.move_vec.y)
    d.mouse_delta.x = _q(d.mouse_delta.x)
    d.mouse_delta.y = _q(d.mouse_delta.y)

    return d


func _q(v):
    return round(v * 1000) / 1000.0


func _read_replay_input() -> InputDataV2:
    if replay_index >= replay_buffer.size():
        return InputDataV2.new()

    var d = replay_buffer[replay_index]
    replay_index += 1
    return d


func set_replay_data(data:Array):
    replay_buffer = data
    replay_index = 0
    mode = Mode.REPLAY


func set_live_mode():
    mode = Mode.LIVE