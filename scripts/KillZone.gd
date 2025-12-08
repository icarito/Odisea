extends Area

var death_screen: CanvasLayer
var is_dead = false

signal player_killed()
signal player_respawn_requested()

func _ready() -> void:
	add_to_group("killzones")
	connect("body_entered", self, "_on_body_entered")
	# Instanciar DeathScreen
	death_screen = preload("res://scenes/ui/DeathScreen.tscn").instance()
	add_child(death_screen)

func _on_body_entered(body: Object) -> void:
	print("KillZone: Body entered - ", body.name if body else "null")
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
	death_screen.show_death_screen()
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
	death_screen.hide_death_screen()
	set_process_input(false)

	# Emitir señal para que el receptor maneje el respawn
	emit_signal("player_respawn_requested")
