extends Control

signal protocol_closed()
signal protocol_next()

onready var _background = $Background
onready var _title_label = $Background/Margin/VBox/TitleLabel
onready var _body_label = $Background/Margin/VBox/BodyLabel
onready var _icon_rect = $Background/Margin/VBox/IconRect
onready var _btn_close = $Background/Margin/VBox/HBox/BtnClose
onready var _btn_next = $Background/Margin/VBox/HBox/BtnNext

func _ready() -> void:
	visible = false
	_background.color = Color(0, 0, 0, 0.7)
	_btn_close.connect("pressed", self, "_on_close_pressed")
	_btn_next.connect("pressed", self, "_on_next_pressed")

func show_protocol(config: Dictionary) -> void:
	var title = config.get("title", "")
	var body = config.get("body", "")
	var icon = config.get("icon", null)
	var show_title = config.get("show_title", true)
	var show_icon = config.get("show_icon", false)
	var show_close = config.get("show_close_button", true)
	var show_next = config.get("show_next_button", false)

	_title_label.text = title
	_title_label.visible = show_title

	_body_label.text = body

	if icon:
		_icon_rect.texture = icon
		_icon_rect.visible = show_icon
	else:
		_icon_rect.visible = false

	_btn_close.visible = show_close
	_btn_next.visible = show_next

	visible = true

func hide_protocol() -> void:
	visible = false

func _on_close_pressed() -> void:
	hide_protocol()
	emit_signal("protocol_closed")

func _on_next_pressed() -> void:
	emit_signal("protocol_next")
