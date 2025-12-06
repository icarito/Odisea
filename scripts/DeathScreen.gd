extends CanvasLayer

onready var top_rect = $TopRect
onready var bottom_rect = $BottomRect
onready var offline_label = $OfflineLabel

var is_showing = false

func _ready():
	top_rect.visible = false
	bottom_rect.visible = false
	offline_label.visible = false
	# Set font
	var font = DynamicFont.new()
	font.font_data = load("res://assets/Sixtyfour-Regular-VariableFont_BLED,SCAN.ttf")
	if font.font_data != null:
		font.size = 95
		offline_label.set("custom_fonts/font", font)
	else:
		print("DeathScreen: Font not loaded! Using default font.")

func show_death_screen():
	if is_showing:
		return
	is_showing = true
	top_rect.visible = true
	bottom_rect.visible = true
	offline_label.visible = true
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(top_rect, "rect_position:y", -get_viewport().size.y / 2, 0, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.interpolate_property(bottom_rect, "rect_position:y", get_viewport().size.y, get_viewport().size.y / 2, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.start()
	# Cambiar música
	if AudioSystem:
		AudioSystem.play_bgm("res://assets/music/One Choice Remains.mp3", 0.0, false)

func hide_death_screen():
	if not is_showing:
		return
	is_showing = false
	top_rect.visible = false
	bottom_rect.visible = false
	offline_label.visible = false
	# Reiniciar música del nivel
	if AudioSystem:
		AudioSystem.play_bgm("res://assets/music/Rust and Ruin.mp3", 0.0, true)
