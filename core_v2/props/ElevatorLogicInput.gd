extends PropBaseV2
class_name ElevatorLogicInput
tool

# ElevatorLogicInput.gd
# Receives signals from OLCS and triggers elevator requests.

signal input_triggered(floor_index)

export(int) var floor_index = 0

func set_active(value: bool):
    var prev = is_active
    .set_active(value)

    # Trigger on rising edge
    if is_active and not prev:
        emit_signal("input_triggered", floor_index)

func _update_visuals():
    # Optional: Indicator light logic can go here
    pass
