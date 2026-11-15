extends InteractableBaseV2
class_name DomeMaintenanceSeal

# DomeMaintenanceSeal.gd — Sello de mantenimiento del descenso del domo (Transit-Run).
#
# Sella el acceso de mantenimiento al pozo del blast door. El jugador lo FUERZA (interactúa)
# para abrir la ruta PRINCIPAL al hangar SIN depender de las 4 redes HEALTHY ni del gating del
# bus: la ruta principal del domo nunca queda bloqueada por los puzles. La apertura completa por
# 4/4 (BlastDoorController.on_blast_door_open) sigue siendo el atajo rápido.
#
# Interfaz: al completar su activación avisa a /root/DomeSystemDirector
# .request_maintenance_override(), que emite `maintenance_open` -> BlastDoorController
# .open_maintenance() (retrae el panel B = paso lateral lento al pozo/rampa).
#
# Determinismo: hereda de InteractableBaseV2 (grupo replay_sync, snapshot de is_active/
# anim_progress). Sin randf, sin Tween y sin tiempo de pared: el estado es pura función del
# input, así el replay es idéntico.
#
# `notify_director` permite desactivar el aviso (tests / escenas que cablean por su cuenta).

export(bool) var notify_director := true

func _on_animation_completed() -> void:
	._on_animation_completed()
	if is_active and notify_director:
		var director = get_node_or_null("/root/DomeSystemDirector")
		if director != null and director.has_method("request_maintenance_override"):
			director.request_maintenance_override()
