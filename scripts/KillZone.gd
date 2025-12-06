extends Area

onready var top_rect = $DeathScreen/TopRect
onready var bottom_rect = $DeathScreen/BottomRect
var offline_label
var is_dead = false

signal player_killed()
signal player_respawn_requested()

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")
	top_rect.visible = false
	bottom_rect.visible = false
	# Create offline label
	offline_label = Label.new()
	var font = DynamicFont.new()
	font.font_data = load("res://assets/Sixtyfour-Regular-VariableFont_BLED,SCAN.ttf")
	font.size = 95
	offline_label.set("custom_fonts/font", font)
	offline_label.text = "Odisea"
	offline_label.align = Label.ALIGN_CENTER
	offline_label.uppercase = true
	offline_label.visible = false
	$DeathScreen.add_child(offline_label)
	# Position it in the center
	offline_label.rect_size = Vector2(get_viewport().size.x, 100)
	offline_label.rect_position = Vector2(0, get_viewport().size.y / 2 - 50)

func _on_body_entered(body: Object) -> void:
	if GameGlobals.current_mode == GameGlobals.GAME_MODE.COPILOT:
		return
	if is_dead:
		return
	# Si el jugador cae en la zona, iniciar efecto de muerte
	if typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.is_spawned():
		var p = PlayerManager.get_player()
		# Asegurarnos que el cuerpo es el jugador
		if is_instance_valid(p) and body == p:
			kill_player()

func kill_player():
	print("Player killed")
	# Desactivar input del jugador para que no se mueva mientras la pantalla de muerte está activa
	# Nota: physics_process se desactiva en PlayerManager.kill_player_instant()
	is_dead = true
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
	# Emitir señal de muerte (desacopla de PlayerManager)
	emit_signal("player_killed")
	# Esperar input para respawn
	set_process_input(true)

func _input(event):
	if is_dead and event.is_pressed() and not event.is_echo():
		respawn()

func respawn():
	print("Respawning player")
	is_dead = false
	top_rect.visible = false
	bottom_rect.visible = false
	offline_label.visible = false
	set_process_input(false)

	# Emitir señal para que el receptor maneje el respawn
	emit_signal("player_respawn_requested")

	# Reiniciar música del nivel
	if AudioSystem:
		AudioSystem.play_bgm("res://assets/music/Rust and Ruin.mp3", 0.0, true)
