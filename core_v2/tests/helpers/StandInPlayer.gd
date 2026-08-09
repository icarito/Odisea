extends KinematicBody

# Minimal stand-in for the player in prop tests: carries the group and the one
# property camera-framing props read and write. Instancing Pilot_v2 would drag in
# the whole controller, animator and camera rig for no benefit here.

var base_spring_length_3d := 5.5


func _init() -> void:
	add_to_group("player")


func _update_platform_tracking(_delta: float) -> void:
	pass
