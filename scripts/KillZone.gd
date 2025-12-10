extends Area

var death_screen: CanvasLayer
var is_dead = false

signal player_killed()
signal player_respawn_requested()


func _ready() -> void:
	print("[KillZone] _ready called, self:", self)
	call_deferred("setup_killzones")
	# Conectar señales a PlayerManager si está disponible
	if typeof(PlayerManager) != TYPE_NIL:
		print("[KillZone] Connecting signals to PlayerManager:", PlayerManager)
		connect("player_killed", PlayerManager, "kill_player_instant")
		connect("player_respawn_requested", PlayerManager, "respawn_player")
		print("[KillZone] Signals connected to PlayerManager.")

func _on_body_entered(body: Object) -> void:
	print("[KillZone] _on_body_entered called with body: ", body, " PlayerManager ref:", PlayerManager)
	if GameGlobals.current_mode == GameGlobals.GAME_MODE.COPILOT:
		print("[KillZone] COPILOT mode, ignoring")
		return
	if is_dead:
		print("[KillZone] Already dead, ignoring")
		return
	# Si el jugador cae en la zona, iniciar efecto de muerte
	if typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.is_spawned():
		var p = PlayerManager.get_player()
		print("[KillZone] PlayerManager.get_player() = ", p)
		# Asegurarnos que el cuerpo es el jugador
		if is_instance_valid(p) and body == p:
			print("[KillZone] Body is player, calling kill_player()")
			kill_player()
		else:
			print("[KillZone] Body is not player or not valid")
	else:
		print("[KillZone] PlayerManager not valid or not spawned")

func kill_player():
	print("[KillZone] kill_player called. Player killed")
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
	print("[KillZone] respawn called. Respawning player")
	is_dead = false
	death_screen.hide_death_screen()
	set_process_input(false)

	# Emitir señal para que el receptor maneje el respawn
	emit_signal("player_respawn_requested")

func setup_killzones():
	print("[KillZone] setup_killzones called. Adding to group and connecting body_entered.")
	add_to_group("killzones")
	connect("body_entered", self, "_on_body_entered")
	# Instanciar DeathScreen
	death_screen = preload("res://scenes/ui/DeathScreen.tscn").instance()
	get_tree().get_root().add_child(death_screen)
	print("[KillZone] DeathScreen instanced and added to root.")
