extends BaseZone
tool
class_name CheckZone

signal checkpoint_reached(transform)

func _ready():
	add_to_group("CheckZone")
	# Set default debug color for CheckZone
	if debug_color == Color(0, 1, 0, 0.2): # Only if default
		set_debug_color(Color(0.0, 1.0, 0.5, 0.3)) # Cyanish green

	# Conectar la señal checkpoint_reached al TeleportSystem activo
	var teleport_system = get_tree().get_root().find_node("TeleportSystem", true, false)
	if teleport_system:
		if not is_connected("checkpoint_reached", teleport_system, "_on_checkpoint_reached"):
			var res = connect("checkpoint_reached", teleport_system, "_on_checkpoint_reached")
			print("[CheckZone] Señal checkpoint_reached conectada a TeleportSystem:", teleport_system, "res=", res)

func _on_zone_entered(body: Node):
	print("[CheckZone] body_entered:", body)
	print("[CheckZone] Player detected, emitting checkpoint_reached (base)")
	var base_transform = _get_base_transform()
	emit_signal("checkpoint_reached", base_transform)

# Calcula el transform en la base (cara inferior) del área, usando el CollisionShape si es BoxShape.
func _get_base_transform():
	var col = null
	if _host_area:
		for child in _host_area.get_children():
			if child is CollisionShape:
				col = child
				break
				
	if col and col.shape and col.shape is BoxShape:
		# Extents es la mitad del tamaño total
		var extents = col.shape.extents
		# La base está en -Y local, así que bajamos desde el centro
		var local_base = Vector3(0, -extents.y, 0)
		var global_base = col.to_global(local_base)
		var t = Transform()
		t.origin = global_base
		t.basis = _host_area.global_transform.basis # Mantener orientación de la zona
		return t
	# Fallback: usar el centro del área o del host
	var fallback_transform = global_transform if not _host_area else _host_area.global_transform
	print("[CheckZone] WARNING: No CollisionShape BoxShape, usando centro.")
	return fallback_transform
