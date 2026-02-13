extends Control

# Lista de botones a verificar para toques
var buttons = []

func _gui_input(event):
    if event is InputEventScreenTouch and event.pressed:
        var pos = event.position
        for button in buttons:
            if button.get_global_rect().has_point(pos):
                button.emit_signal("pressed")
                get_viewport().set_input_as_handled()
                break
    # Ignorar InputEventScreenDrag y otros eventos no-touch