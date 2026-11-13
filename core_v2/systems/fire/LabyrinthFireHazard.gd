extends FireSystem
class_name LabyrinthFireHazard

# FD-051 extendido para la sección laberíntica de la bahía (spike 2026-11-13).
#
# FireSystem escanea por Y GLOBAL: cualquier cuerpo del grupo `fire_vulnerable`
# bajo el techo de calor recibe la señal. En una bahía con varios niveles eso
# dañaría al jugador en toda la escena. Este hazard añade una compuerta
# posicional (bounds X/Z en el frame local de la sección) para que el calor
# aplique SOLO dentro del laberinto. El resto de la lógica (fire_height,
# heat_band, snapshot, señales) es idéntico al FireSystem base.

export(Vector3) var gate_local_center := Vector3(6.0, 0.0, 12.0)
export(Vector3) var gate_local_half_extents := Vector3(7.5, 100.0, 13.5)

func _within_gate(world_pos: Vector3) -> bool:
	var lp := to_local(world_pos)
	return abs(lp.x - gate_local_center.x) <= gate_local_half_extents.x \
		and abs(lp.z - gate_local_center.z) <= gate_local_half_extents.z

func _scan_vulnerable_bodies(_delta: float) -> void:
	var ceiling := get_heat_ceiling()
	for body in get_tree().get_nodes_in_group(GROUP_VULNERABLE):
		if not is_instance_valid(body) or not (body is Spatial):
			continue
		var body_pos: Vector3 = body.global_transform.origin
		if body_pos.y > ceiling:
			continue
		if not _within_gate(body_pos):
			continue
		var in_core: bool = body_pos.y <= fire_height
		var dps := damage_per_second
		if in_core:
			dps *= core_damage_multiplier
		emit_signal("heat_contact", body, dps, in_core)
