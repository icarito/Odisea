extends Control

# InfoOverlay.gd - HUD Overlay for AreaInfoScreen

signal closed()

var title := ""
var body := ""
var map_texture: Texture = null
var accent_color := Color.cyan

onready var background = $Background
onready var panel = $CenterContainer/Panel
onready var title_label = $CenterContainer/Panel/VBox/Title
onready var body_label = $CenterContainer/Panel/VBox/Scroll/Body
onready var map_rect = $CenterContainer/Panel/VBox/MapRect
onready var footer = $CenterContainer/Panel/VBox/Footer
onready var tween = $Tween

var _is_closing := false

func _ready():
	visible = false
	modulate.a = 0
	panel.rect_scale = Vector2(0.9, 0.9)
	pause_mode = PAUSE_MODE_PROCESS
	
	# Resolve interact key for footer
	var interact_key = "E" # Default
	var events = InputMap.get_action_list("interact")
	for event in events:
		if event is InputEventKey:
			interact_key = OS.get_scancode_string(event.scancode)
			break
	footer.text = "Presiona %s o ESC para cerrar" % interact_key

func setup(p_title: String, p_body: String, p_map: Texture, p_color: Color):
	title = p_title
	body = p_body
	map_texture = p_map
	accent_color = p_color
	
	title_label.text = title.to_upper()
	title_label.add_color_override("font_color", accent_color)
	
	if map_texture:
		map_rect.texture = map_texture
		map_rect.visible = true
		$CenterContainer/Panel/VBox/Scroll.visible = false
		# Adjust panel size for map
		panel.rect_min_size = Vector2(600, 450)
		panel.rect_pivot_offset = Vector2(300, 225)
	else:
		body_label.text = body
		map_rect.visible = false
		$CenterContainer/Panel/VBox/Scroll.visible = true
		panel.rect_min_size = Vector2(400, 220)
		panel.rect_pivot_offset = Vector2(200, 110)
	
	var style = panel.get_stylebox("panel").duplicate()
	if style is StyleBoxFlat:
		style.border_color = accent_color
		panel.add_stylebox_override("panel", style)

func open():
	visible = true
	_is_closing = false
	get_tree().paused = true
	_refresh_mobile_ui()

	tween.stop_all()
	tween.interpolate_property(self, "modulate:a", 0.0, 1.0, 0.2, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.interpolate_property(panel, "rect_scale", Vector2(0.9, 0.9), Vector2(1.0, 1.0), 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	tween.start()

func close():
	if _is_closing: return
	_is_closing = true
	
	tween.stop_all()
	tween.interpolate_property(self, "modulate:a", modulate.a, 0.0, 0.1, Tween.TRANS_SINE, Tween.EASE_IN)
	tween.start()
	
	# We use a timer because yield with Tween can be flaky if Tween is stopped
	var timer = get_tree().create_timer(0.12)
	yield(timer, "timeout")
	
	visible = false
	get_tree().paused = false
	_refresh_mobile_ui()
	emit_signal("closed")
	queue_free()

func _refresh_mobile_ui() -> void:
	# Keep on-screen touch controls in sync with pause state; they sit on a high
	# CanvasLayer and would otherwise intercept touches meant for this overlay.
	var mobile = get_node_or_null("/root/MobileUIManager")
	if mobile and mobile.has_method("refresh_for_pause"):
		mobile.refresh_for_pause()

func _input(event):
	if not visible or _is_closing: return
	
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		close()
		get_tree().set_input_as_handled()
