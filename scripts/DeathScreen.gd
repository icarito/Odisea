extends CanvasLayer

signal respawn_requested

#onready var top_rect = $TopRect
#onready var bottom_rect = $BottomRect
#onready var offline_label = $OfflineLabel

var is_showing = false

func _ready():
	$TopRect.visible = false
	$BottomRect.visible = false
	$OfflineLabel.visible = false
	
	# Set font
	var font = DynamicFont.new()
	font.font_data = load("res://assets/fonts/SixtyFour-Regular-FontData.tres")

	if font.font_data != null:
		font.size = 95
		$OfflineLabel.set("custom_fonts/font", font)
	else:
		print("DeathScreen: Font not loaded! Using default font.")

func show_death_screen():
	if is_showing:
		return
	is_showing = true
	$TopRect.visible = true
	$BottomRect.visible = true
	$OfflineLabel.visible = true
	# Ocultar controles touch durante la pantalla de muerte
	var touch_controls = get_tree().current_scene.find_node("TouchControls", true, false)
	if touch_controls:
		touch_controls._set_controls_visible(false)
	# Ajustar tamaño y posición del label para que encaje en el viewport
	var vp_size = get_viewport().size
	# Ajustar tamaño de fuente y label dinámicamente según el viewport
	var offline_label = $OfflineLabel
	var font = offline_label.get("custom_fonts/font")
	if font:
		font.size = clamp(int(vp_size.y * 0.09), 40, 120)
	offline_label.anchor_left = 0.5
	offline_label.anchor_top = 0.5
	offline_label.anchor_right = 0.5
	offline_label.anchor_bottom = 0.5
	offline_label.grow_horizontal = Label.SIZE_EXPAND
	offline_label.grow_vertical = Label.SIZE_EXPAND
	offline_label.autowrap = true
	offline_label.rect_size = Vector2(vp_size.x * 0.8, font.size * 1.2)
	offline_label.rect_position = Vector2(vp_size.x/2 - offline_label.rect_size.x/2, vp_size.y/2 - offline_label.rect_size.y/2)
	offline_label.rect_scale = Vector2(min(0.5, vp_size.x/1920.0), min(0.5, vp_size.y/1080.0))
	offline_label.set_size(Vector2(vp_size.x * 0.8, 100 * min(1.0, vp_size.y/1080.0)))

	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property($TopRect, "rect_position:y", -vp_size.y / 2, 0, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.interpolate_property($BottomRect, "rect_position:y", vp_size.y, vp_size.y / 2, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.start()
	# Cambiar música
	if AudioSystem:
		AudioSystem.play_bgm("res://assets/music/One Choice Remains.mp3", 0.0, false)

func hide_death_screen():
	if not is_showing:
		return
	is_showing = false
	$TopRect.visible = false
	$BottomRect.visible = false
	$OfflineLabel.visible = false
	# Mostrar controles touch después de la pantalla de muerte
	var touch_controls = get_tree().current_scene.find_node("TouchControls", true, false)
	if touch_controls:
		touch_controls._set_controls_visible(true)
		touch_controls._restart_hide_timer()

func _input(event):
	if is_showing and event is InputEventScreenTouch and event.pressed:
		emit_signal("respawn_requested")
