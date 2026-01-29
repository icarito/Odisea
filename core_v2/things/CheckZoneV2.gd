extends Area
class_name CheckZoneV2

func _ready():
	add_to_group("CheckZoneV2")
	connect("body_entered", self, "_on_body_entered")
	# Conectar la señal checkpoint_reached al TeleportSystem activo
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if teleport_system and has_signal("checkpoint_reached"):
		if not is_connected("checkpoint_reached", teleport_system, "_on_checkpoint_reached"):
			var res = connect("checkpoint_reached", teleport_system, "_on_checkpoint_reached")
			print("[CheckZoneV2] Señal checkpoint_reached conectada a TeleportSystem:", teleport_system, "res=", res)
		else:
			print("[CheckZoneV2] Señal checkpoint_reached YA conectada a TeleportSystem:", teleport_system)

signal checkpoint_reached(transform)


# Al entrar el jugador, dispara la señal para guardar checkpoint en la base de la zona.
func _on_body_entered(body):
	print("[CheckZoneV2] body_entered:", body)
	if body.is_in_group("player"):
		print("[CheckZoneV2] Player detected, emitting checkpoint_reached (base)")
		var base_transform = _get_base_transform()
		emit_signal("checkpoint_reached", base_transform)

# Calcula el transform en la base (cara inferior) del área, usando el CollisionShape si es BoxShape.
func _get_base_transform():
	var col = get_node_or_null("CollisionShape")
	if col and col.shape and col.shape is BoxShape:
		# Extents es la mitad del tamaño total
		var extents = col.shape.extents
		# La base está en -Y local, así que bajamos desde el centro
		var local_base = Vector3(0, -extents.y, 0)
		var global_base = col.to_global(local_base)
		var t = Transform()
		t.origin = global_base
		t.basis = global_transform.basis # Mantener orientación de la zona
		return t
	# Fallback: usar el centro del área
	print("[CheckZoneV2] WARNING: No CollisionShape BoxShape, usando centro del área")
	return global_transform
