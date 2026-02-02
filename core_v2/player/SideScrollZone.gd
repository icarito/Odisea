tool
extends BaseZoneV2
class_name SideScrollZoneV2

enum Axis {LOCK_Z, LOCK_X}
export(Axis) var lock_axis = Axis.LOCK_Z
export(bool) var invert_side = false
export(bool) var allow_depth_movement = false
export(float) var target_distance = 0.0 # 0.0 means use default 2.5D distance

# --- Direction Latch Control ---
export(bool) var latch_on_enter := true # Si true, activa el latch de dirección al entrar a la zona
export(bool) var latch_on_exit := true  # Si true, activa el latch de dirección al salir de la zona

func _ready():
	add_to_group("SideScrollZoneV2")
	if debug_color == Color(0, 1, 0, 0.2): # Only if default
		set_debug_color(Color(0.2, 0.5, 1.0, 0.3)) # Blueish

func _on_zone_entered(body: Node):
	if body.has_method("enter_25d_mode"):
		var coord = _host_area.global_transform.origin.z if lock_axis == Axis.LOCK_Z else _host_area.global_transform.origin.x
		# 1 for X, 2 for Z
		var axis_int = 2 if lock_axis == Axis.LOCK_Z else 1
		body.enter_25d_mode(self, axis_int, coord, invert_side, target_distance, allow_depth_movement)

func _on_zone_exited(body: Node):
	if body.has_method("exit_25d_mode"):
		body.exit_25d_mode(self)
