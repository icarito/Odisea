tool
extends BaseZoneV2

# CinematicCameraZone.gd - Trigger zone to activate a cinematic rig

export(String) var rig_id := ""
export(CinematicManager.ControlMode) var control_mode = CinematicManager.ControlMode.FREE

func _ready():
	if debug_color == Color(0, 1, 0, 0.2): # Only if default
		set_debug_color(Color(1.0, 0.5, 0.0, 0.3)) # Orange for cinematic zones

func _on_zone_entered(_body: Node):
	if rig_id != "":
		CinematicManager.activate_rig(rig_id, control_mode)

func _on_zone_exited(_body: Node):
	CinematicManager.deactivate_rig()
