extends PropBaseV2
class_name ElevatorLogicInput
tool

# ElevatorLogicInput.gd
# Receives signals from OLCS and triggers elevator requests.

signal input_triggered(floor_index)

export(int) var floor_index = 0

func set_active(value: bool, immediate: bool = false):
    var prev = is_active
    .set_active(value, immediate)

    # Trigger on rising edge OR if we get repeated 'true' signals as momentary presses
    if is_active:
        emit_signal("input_triggered", floor_index)

func _update_visuals():
    # Optional: Indicator light logic can go here
    pass
