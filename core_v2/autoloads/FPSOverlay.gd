extends CanvasLayer
# FPS overlay toggled with "/" key.

var _label: Label
var _visible_fps := true

func _ready() -> void:
	layer = 120
	pause_mode = Node.PAUSE_MODE_PROCESS

	_label = Label.new()
	_label.name = "FPSLabel"
	_label.rect_position = Vector2(10, 10)
	_label.add_color_override("font_color", Color(0.0, 1.0, 0.2))
	_label.visible = true
	add_child(_label)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_SLASH:
			_visible_fps = not _visible_fps
			_label.visible = _visible_fps
			get_tree().set_input_as_handled()

func _process(_delta: float) -> void:
	if _visible_fps:
		_label.text = "FPS: %d" % Engine.get_frames_per_second()
