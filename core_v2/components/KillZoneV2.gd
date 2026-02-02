extends BaseZoneV2
tool
class_name KillZoneV2

signal player_killed

func _ready():
	add_to_group("KillZoneV2")
	# Set default debug color for KillZone
	if debug_color == Color(0, 1, 0, 0.2): # Only if default
		set_debug_color(Color(1.0, 0.0, 0.0, 0.3)) # Red

	# Conectar la señal player_killed al TeleportSystem activo
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if teleport_system:
		if not is_connected("player_killed", teleport_system, "_on_player_killed"):
			var res = connect("player_killed", teleport_system, "_on_player_killed")
			print("[KillZoneV2] Señal player_killed conectada a TeleportSystem:", teleport_system, "res=", res)

# Al entrar el jugador, dispara la señal de muerte.
func _on_zone_entered(body: Node):
	print("[KillZoneV2] body_entered:", body)
	print("[KillZoneV2] Player detected, emitting player_killed")
	emit_signal("player_killed")
