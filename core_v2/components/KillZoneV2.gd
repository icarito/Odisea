extends Area
class_name KillZoneV2

func _ready():
	add_to_group("KillZoneV2")
	connect("body_entered", self, "_on_body_entered")
	# Conectar la señal player_killed al TeleportSystem activo
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if teleport_system and has_signal("player_killed"):
		if not is_connected("player_killed", teleport_system, "_on_player_killed"):
			var res = connect("player_killed", teleport_system, "_on_player_killed")
			print("[KillZoneV2] Señal player_killed conectada a TeleportSystem:", teleport_system, "res=", res)
		else:
			print("[KillZoneV2] Señal player_killed YA conectada a TeleportSystem:", teleport_system)

signal player_killed

# Al entrar el jugador, dispara la señal de muerte.
func _on_body_entered(body):
	print("[KillZoneV2] body_entered:", body)
	if body.is_in_group("player"):
		print("[KillZoneV2] Player detected, emitting player_killed")
		emit_signal("player_killed")
