# FPS Debug Overlay
# This script adds an FPS counter to the screen

var label: Label

func _ready():
    label = Label.new()
    label.name = \"FPSLabel\"
    label.rect_position = Vector2(10, 10)
    label.add_color_override(\"font_color\", Color(0, 1, 0))
    get_tree().root.add_child(label)

func _process(_delta):
    if label:
        var fps = Engine.get_frames_per_second()
        label.text = \"FPS: %d\" % fps
