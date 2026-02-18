extends BaseZoneV2
tool
class_name KillZoneV2

signal player_killed

func _ready():
	._ready() # Call parent BaseZoneV2 to connect signals and setup host
	add_to_group("KillZoneV2")
	# Set default debug color for KillZone
	if debug_color == Color(0, 1, 0, 0.2): # Only if default
		set_debug_color(Color(1.0, 0.0, 0.0, 0.3)) # Red

	# Conectar la señal player_killed al TeleportSystem activo
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if teleport_system:
		if not is_connected("player_killed", teleport_system, "_on_player_killed"):
			var _res = connect("player_killed", teleport_system, "_on_player_killed")
	else:
		# TeleportSystem aún no disponible; intentar conectar en el siguiente frame
		call_deferred("_deferred_connect")

func _deferred_connect():
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if teleport_system:
		if not is_connected("player_killed", teleport_system, "_on_player_killed"):
			var _res = connect("player_killed", teleport_system, "_on_player_killed")

# Al entrar el jugador, dispara la señal de muerte.
func _on_zone_entered(body: Node):
	emit_signal("player_killed")
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if not teleport_system:
		teleport_system = get_node_or_null("/root/SessionManager/TeleportSystem")
	
	if teleport_system:
		if not is_connected("player_killed", teleport_system, "_on_player_killed"):
			if teleport_system.has_method("_on_player_killed"):
				teleport_system._on_player_killed()
