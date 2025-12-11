extends Area

var death_screen: CanvasLayer

signal player_killed(player)
signal player_respawn_requested(player)


func _ready() -> void:
	print("[KillZone] _ready called, self:", self)
	set_process_input(false)  # Deshabilitar input hasta que el jugador muera
	call_deferred("setup_killzones")
	# Conectar señales a PlayerManager si está disponible y no es COPILOT (single player)
	if typeof(PlayerManager) != TYPE_NIL and GameGlobals.current_mode != GameGlobals.GAME_MODE.COPILOT:
		print("[KillZone] Connecting signals to PlayerManager:", PlayerManager)
		connect("player_killed", PlayerManager, "kill_player_instant")
		connect("player_respawn_requested", PlayerManager, "respawn_player")
		print("[KillZone] Signals connected to PlayerManager.")

func _on_body_entered(body: Object) -> void:
	print("[KillZone] _on_body_entered called with body: ", body, " PlayerManager ref:", PlayerManager)
	# Si el jugador cae en la zona, iniciar efecto de muerte
	if body and body.has_method("set_physics_process"):
		print("[KillZone] Disabling physics for body:", body)
		body.set_physics_process(false)
	print("[KillZone] Calling kill_player for body:", body)
	kill_player(body)

func kill_player(player):
	print("[KillZone] kill_player called. Player killed:", player)
	if death_screen:
		death_screen.show_death_screen()
	emit_signal("player_killed", player)
	# En single player, esperar input para respawn
	if GameGlobals.current_mode != GameGlobals.GAME_MODE.COPILOT:
		set_process_input(true)

func _input(event):
	if death_screen and death_screen.is_showing and Input.is_action_pressed("jump"):
		# Suponemos que solo hay un jugador afectado por esta KillZone
		var player = null
		if typeof(PlayerManager) != TYPE_NIL and PlayerManager.is_spawned():
			player = PlayerManager.get_player()
		respawn(player)

func respawn(player):
	print("[KillZone] respawn called. Respawning player:", player)
	if death_screen:
		death_screen.hide_death_screen()
	set_process_input(false)
	# Reactivar físicas del jugador
	if player and player.has_method("set_physics_process"):
		print("[KillZone] Enabling physics for player:", player)
		player.set_physics_process(true)
	# Emitir señal para que el receptor maneje el respawn
	if GameGlobals.current_mode != GameGlobals.GAME_MODE.COPILOT:
		emit_signal("player_respawn_requested")
	else:
		emit_signal("player_respawn_requested", player)

func setup_killzones():
	print("[KillZone] setup_killzones called. Adding to group and connecting body_entered.")
	add_to_group("killzones")
	connect("body_entered", self, "_on_body_entered")
	# Instanciar DeathScreen solo en single player
	if GameGlobals.current_mode != GameGlobals.GAME_MODE.COPILOT:
		death_screen = preload("res://scenes/ui/DeathScreen.tscn").instance()
		get_tree().get_root().add_child(death_screen)
		print("[KillZone] DeathScreen instanced and added to root.")
