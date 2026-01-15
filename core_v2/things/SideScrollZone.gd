# /mnt/sdd/home/icarito/Proyectos/Odisea_Game/src/core_v2/things/SideScrollTransitionZone.gd
extends Area

enum Axis {LOCK_Z, LOCK_X}
export(Axis) var lock_axis = Axis.LOCK_Z
export(bool) var invert_side = false
export(float) var target_distance = 0.0 # 0.0 means use default 2.5D distance

func _ready():
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

func _on_body_entered(body: Node):
	if body.has_method("enter_25d_mode"):
		var coord = global_transform.origin.z if lock_axis == Axis.LOCK_Z else global_transform.origin.x
		# 1 for X, 2 for Z
		var axis_int = 2 if lock_axis == Axis.LOCK_Z else 1
		body.enter_25d_mode(axis_int, coord, invert_side, target_distance)

func _on_body_exited(body: Node):
	if body.has_method("exit_25d_mode"):
		body.exit_25d_mode()
